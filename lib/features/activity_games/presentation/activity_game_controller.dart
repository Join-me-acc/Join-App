import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/activity_game_models.dart';
import '../data/activity_game_repository.dart';

/// Estado de una sala de El Impostor en línea.
///
/// Se encarga de lo que no conviene repartir por la interfaz:
///  · volver a leer la sala cuando Realtime avisa, cuando la app vuelve a
///    primer plano y, como red de seguridad, cada pocos segundos;
///  · el latido que marca al jugador como conectado;
///  · la cuenta regresiva y el paso automático a la votación;
///  · aplicar de forma optimista "listo" y el voto para que la pantalla
///    responda al instante;
///  · publicar el resultado en el chat una sola vez (lo hace el host).
class ImpostorRoomController extends ChangeNotifier with WidgetsBindingObserver {
  final ActivityGameRepository repository;
  final String activityId;

  /// Palabras candidatas del catálogo de la categoría del plan.
  final List<String> words;

  /// Publica el resultado en el chat del plan. Lo inyecta la pantalla para
  /// que el controlador no dependa del cifrado del chat.
  final Future<void> Function(GameResultPayload payload)? publishResult;

  ImpostorRoomController({
    required this.repository,
    required this.activityId,
    required this.words,
    this.publishResult,
  });

  /// Sesiones cuyo resultado ya se publicó desde este dispositivo, para no
  /// duplicar la tarjeta si la pantalla se reconstruye.
  @visibleForTesting
  static final Set<String> publishedSessions = {};

  GameSession? _session;
  ImpostorRole? _role;
  String? _myVote;
  bool _loading = true;
  bool _busy = false;
  bool _offline = false;
  String? _error;
  bool _disposed = false;
  bool _autoAdvanceRequested = false;
  bool? _optimisticReady;

  /// Sala que se está siguiendo. Se fija antes de la primera lectura.
  String? _sessionId;

  Future<void> Function()? _unsubscribe;
  Timer? _heartbeat;
  Timer? _fallback;
  Timer? _ticker;
  Future<void>? _inFlight;
  bool _refreshQueued = false;

  GameSession? get session => _session;
  ImpostorRole? get role => _role;
  String? get myVote => _myVote;
  bool get loading => _loading;
  bool get busy => _busy;
  bool get offline => _offline;
  String? get error => _error;
  String? get userId => repository.currentUserId;

  bool get isHost => _session != null && _session!.hostUserId == userId;
  bool get isPlayer => _session?.isPlayer(userId) ?? false;

  bool get isReady {
    if (_optimisticReady != null) return _optimisticReady!;
    return _session?.playerById(userId)?.isReady ?? false;
  }

  /// Segundos que quedan de discusión, o null fuera de esa fase.
  int? get secondsLeft {
    final ends = _session?.discussionEndsAt;
    if (ends == null || _session?.phase != ImpostorPhase.discussion) {
      return null;
    }
    final left = ends.difference(DateTime.now()).inSeconds;
    return left < 0 ? 0 : left;
  }

  // ── Ciclo de vida ─────────────────────────────────────────────

  bool _observing = false;

  /// Entra a la sala [sessionId], abre la revancha de [rematchOf] o crea/une
  /// la sala activa del plan.
  Future<void> open({String? sessionId, String? rematchOf}) async {
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    _error = null;
    try {
      final id = sessionId ??
          (rematchOf != null
              ? await repository.rematch(rematchOf)
              : await repository.createOrJoin(activityId));
      _session = null;
      await _attach(id);
    } catch (e) {
      _error = friendlyGameError(e);
      _loading = false;
      _notify();
    }
  }

  Future<void> _attach(String sessionId) async {
    _detachRealtime();
    _sessionId = sessionId;
    _role = null;
    _myVote = null;
    _optimisticReady = null;
    _autoAdvanceRequested = false;

    // Con una sala anterior en pantalla se vuelve a "cargando" para no
    // mostrar por un instante la vieja.
    _loading = true;
    _notify();

    await refresh();
    _unsubscribe = repository.subscribe(sessionId, () => unawaited(refresh()));
    _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) {
      repository.heartbeat(sessionId).catchError((_) {});
    });
    _fallback = Timer.periodic(const Duration(seconds: 8), (_) => refresh());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _detachRealtime() {
    _heartbeat?.cancel();
    _fallback?.cancel();
    _ticker?.cancel();
    final unsubscribe = _unsubscribe;
    _unsubscribe = null;
    if (unsubscribe != null) unawaited(unsubscribe().catchError((_) {}));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final id = _session?.id;
      if (id != null) {
        unawaited(repository.heartbeat(id).catchError((_) {}));
        unawaited(refresh());
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    _detachRealtime();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ── Lectura ───────────────────────────────────────────────────

  /// Vuelve a leer la sala. Llamadas simultáneas se agrupan en una.
  Future<void> refresh() {
    if (_inFlight != null) {
      _refreshQueued = true;
      return _inFlight!;
    }
    final future = _doRefresh().whenComplete(() {
      _inFlight = null;
      if (_refreshQueued && !_disposed) {
        _refreshQueued = false;
        unawaited(refresh());
      }
    });
    _inFlight = future;
    return future;
  }

  Future<void> _doRefresh() async {
    final id = _sessionId;
    if (id == null) return;
    try {
      final fresh = await repository.fetchSession(id);
      if (_disposed) return;
      if (fresh == null) {
        _error = 'La sala ya no existe.';
        _loading = false;
        _notify();
        return;
      }

      final previous = _session;
      _session = fresh;
      _offline = false;
      _loading = false;

      // Lo optimista se descarta en cuanto el servidor confirma.
      if (_optimisticReady != null &&
          fresh.playerById(userId)?.isReady == _optimisticReady) {
        _optimisticReady = null;
      }
      if (fresh.status != GameSessionStatus.lobby) _optimisticReady = null;

      final needsRole = fresh.status != GameSessionStatus.lobby &&
          fresh.isPlayer(userId) &&
          (_role == null || _role!.round != fresh.round);
      if (needsRole) _role = await repository.fetchMyRole(id);

      if (fresh.phase == ImpostorPhase.voting ||
          fresh.phase == ImpostorPhase.result) {
        _myVote ??= await repository.fetchMyVote(id, fresh.round);
      }

      if (previous?.phase != fresh.phase) _autoAdvanceRequested = false;
      _maybePublishResult(fresh);
      _notify();
    } catch (e) {
      if (_disposed) return;
      // Se conserva lo último que se vio: perder la red un momento no debe
      // sacar a nadie de la partida.
      _offline = true;
      _loading = false;
      _notify();
    }
  }

  void _tick() {
    final s = _session;
    if (s == null || s.phase != ImpostorPhase.discussion) return;
    _notify();
    // Si se acaba el tiempo, cualquier jugador puede abrir la votación: así
    // la partida sigue aunque el host haya cerrado la app.
    if ((secondsLeft ?? 1) <= 0 && isPlayer && !_autoAdvanceRequested) {
      _autoAdvanceRequested = true;
      repository
          .advanceToVoting(s.id)
          .then((_) => refresh())
          .catchError((_) => refresh());
    }
  }

  void _maybePublishResult(GameSession s) {
    final result = s.result;
    if (s.status != GameSessionStatus.finished || result == null) return;
    if (!isHost || publishResult == null) return;
    if (!publishedSessions.add(s.id)) return;
    publishResult!(GameResultPayload.fromResult(s.id, result))
        .catchError((Object _) => publishedSessions.remove(s.id));
  }

  // ── Acciones ──────────────────────────────────────────────────

  Future<bool> _run(Future<void> Function() action) async {
    if (_busy) return false;
    _busy = true;
    _error = null;
    _notify();
    try {
      await action();
      await refresh();
      return true;
    } catch (e) {
      _error = friendlyGameError(e);
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  void clearError() {
    _error = null;
    _notify();
  }

  Future<void> toggleReady() async {
    final s = _session;
    if (s == null) return;
    final next = !isReady;
    _optimisticReady = next;
    _notify();
    try {
      await repository.setReady(s.id, next);
      await refresh();
    } catch (e) {
      _optimisticReady = null;
      _error = friendlyGameError(e);
      _notify();
    }
  }

  Future<bool> start({int discussionSeconds = 180}) {
    final s = _session;
    if (s == null) return Future.value(false);
    return _run(() => repository.startImpostor(
          s.id,
          words: words,
          discussionSeconds: discussionSeconds,
        ));
  }

  Future<bool> openVoting() {
    final s = _session;
    if (s == null) return Future.value(false);
    return _run(() => repository.advanceToVoting(s.id));
  }

  Future<void> vote(String targetId) async {
    final s = _session;
    if (s == null || targetId == userId) return;
    final previous = _myVote;
    _myVote = targetId;
    _notify();
    try {
      await repository.vote(s.id, targetId);
      await refresh();
    } catch (e) {
      _myVote = previous;
      _error = friendlyGameError(e);
      _notify();
    }
  }

  Future<bool> finish() {
    final s = _session;
    if (s == null) return Future.value(false);
    return _run(() => repository.finish(s.id));
  }

  Future<bool> cancel() {
    final s = _session;
    if (s == null) return Future.value(false);
    return _run(() => repository.cancel(s.id));
  }

  Future<void> rematch() async {
    final s = _session;
    if (s == null || _busy) return;
    _busy = true;
    _notify();
    try {
      final id = await repository.rematch(s.id);
      _session = null;
      await _attach(id);
    } catch (e) {
      _error = friendlyGameError(e);
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> leave() async {
    final s = _session;
    if (s == null) return;
    try {
      await repository.leave(s.id);
    } catch (_) {
      // Salir es lo último que se hace en la pantalla: si falla, la sala lo
      // resolverá cuando el jugador deje de mandar latidos.
    }
  }
}
