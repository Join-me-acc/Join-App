import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:join_app/core/models/activity_lifecycle.dart';
import 'package:join_app/core/models/activity_model.dart';
import 'package:join_app/core/providers/app_state.dart';
import 'package:join_app/core/widgets/user_avatar.dart';

/// Calificación del plan al terminar.
///
/// Antes esta pantalla mostraba "¡Gracias!" sin guardar nada. Ahora guarda
/// en `event_feedback`; el servidor aplica las reglas (sólo con el plan
/// terminado, una vez por persona y nunca al propio plan) y recalcula la
/// nota del organizador.
class EventFeedbackScreen extends StatefulWidget {
  final String activityId;

  const EventFeedbackScreen({super.key, required this.activityId});

  @override
  State<EventFeedbackScreen> createState() => _EventFeedbackScreenState();
}

enum _Gate { loading, open, notEnded, organizer, alreadyRated, sent }

class _EventFeedbackScreenState extends State<EventFeedbackScreen> {
  static const _accent = Color(0xFFF59E0B);
  static const _bestOptions = [
    'Organización',
    'La gente',
    'El lugar',
    'La actividad',
    'Buen ambiente',
    'Conversaciones',
    'Puntualidad',
    'Duración justa',
  ];

  int _rating = 0;
  int _attendance = 0;
  bool _again = true;
  final _best = <String>{};
  final _comment = TextEditingController();
  _Gate _gate = _Gate.loading;
  bool _sending = false;

  Activity? get _activity => context
      .read<AppState>()
      .activities
      .where((a) => a.id == widget.activityId)
      .firstOrNull;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    final appState = context.read<AppState>();
    final activity = _activity;
    final me = appState.currentUser?.id;
    _Gate gate;
    if (activity == null || !activity.hasEnded) {
      gate = _Gate.notEnded;
    } else if (activity.organizerId == me) {
      gate = _Gate.organizer;
    } else {
      final rated = await appState.lifecycle
          .hasRated(widget.activityId)
          .catchError((_) => false);
      gate = rated ? _Gate.alreadyRated : _Gate.open;
    }
    if (mounted) setState(() => _gate = gate);
  }

  Future<void> _submit() async {
    if (_rating == 0 || _attendance == 0) return;
    setState(() => _sending = true);
    final appState = context.read<AppState>();
    try {
      await appState.lifecycle.submitFeedback(
        activityId: widget.activityId,
        groupRating: _rating,
        attendanceScore: _attendance,
        wouldAttendAgain: _again,
        comment: _comment.text,
        bestThings: _best.toList(),
      );
      HapticFeedback.mediumImpact();
      appState.markRated(widget.activityId);
      if (mounted) setState(() => _gate = _Gate.sent);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().contains('row-level security')
            ? 'Ya no se puede calificar este plan.'
            : 'No se pudo enviar. Revisa tu conexión.'),
      ));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activity = context
        .watch<AppState>()
        .activities
        .where((a) => a.id == widget.activityId)
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text('Califica el plan',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w800)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: switch (_gate) {
        _Gate.loading => const Center(child: CircularProgressIndicator()),
        _Gate.open => _form(activity),
        _Gate.notEnded => _message(
            Icons.event_available_rounded,
            'Aún no termina',
            'Podrás calificar este plan cuando acabe el día del evento.'),
        _Gate.organizer => _message(
            Icons.workspace_premium_rounded,
            'Es tu plan',
            'Los participantes lo calificarán y la nota aparecerá en tu perfil. '
                'Mientras tanto, sube tus fotos al mural de recuerdos.',
            mural: true),
        _Gate.alreadyRated => _message(Icons.check_circle_rounded,
            'Ya lo calificaste', '¡Gracias! Tu opinión ya cuenta.',
            mural: true),
        _Gate.sent => _message(
            Icons.celebration_rounded,
            '¡Gracias por calificar!',
            'Ahora sube tu foto al mural de recuerdos del plan.',
            mural: true),
      },
    );
  }

  Widget _message(IconData icon, String title, String body,
      {bool mural = false}) {
    final muted = Theme.of(context).brightness == Brightness.dark
        ? Colors.white60
        : const Color(0xFF64748B);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: _accent),
            ),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                    fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(body,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                    fontSize: 14.5, height: 1.4, color: muted)),
            if (mural) ...[
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: () => context.pushReplacement(
                    '/main/activity/${widget.activityId}/photos'),
                icon: const Icon(Icons.photo_library_rounded),
                label: const Text('Ir al mural de recuerdos'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFEC4899),
                  minimumSize: const Size(220, 48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _form(Activity? activity) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? const Color(0xFF161B24) : Colors.white;
    final muted = isDark ? Colors.white60 : const Color(0xFF64748B);
    final ready = _rating > 0 && _attendance > 0;

    Widget section(String title, Widget child, {String? hint}) => Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : const Color(0xFFEEF0F4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: GoogleFonts.outfit(
                      fontSize: 15.5, fontWeight: FontWeight.w800)),
              if (hint != null)
                Text(hint,
                    style: GoogleFonts.outfit(fontSize: 12.5, color: muted)),
              const SizedBox(height: 12),
              child,
            ],
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        if (activity != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                UserAvatar(
                    imageUrl: activity.organizerImageUrl,
                    name: activity.organizerName,
                    radius: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(activity.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                              fontSize: 19, fontWeight: FontWeight.w800)),
                      Text('Organizado por ${activity.organizerName}',
                          style: GoogleFonts.outfit(
                              fontSize: 13, color: muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        section(
          '¿Qué tal estuvo el plan?',
          _Stars(value: _rating, onChanged: (v) => setState(() => _rating = v)),
          hint: 'Esta nota se suma a la del organizador.',
        ),
        section(
          '¿El grupo fue puntual y cumplió?',
          _Stars(
              value: _attendance,
              onChanged: (v) => setState(() => _attendance = v)),
        ),
        section(
          'Lo mejor fue…',
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in _bestOptions)
                FilterChip(
                  label: Text(option),
                  selected: _best.contains(option),
                  onSelected: (on) => setState(
                      () => on ? _best.add(option) : _best.remove(option)),
                  selectedColor: _accent.withValues(alpha: 0.2),
                  checkmarkColor: const Color(0xFFB45309),
                ),
            ],
          ),
        ),
        section(
          '¿Volverías a un plan con este grupo?',
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                  value: true,
                  icon: Icon(Icons.thumb_up_alt_rounded),
                  label: Text('Sí')),
              ButtonSegment(
                  value: false,
                  icon: Icon(Icons.thumbs_up_down_rounded),
                  label: Text('Quizás no')),
            ],
            selected: {_again},
            onSelectionChanged: (v) => setState(() => _again = v.first),
          ),
        ),
        section(
          'Cuéntanos más (opcional)',
          TextField(
            controller: _comment,
            maxLines: 3,
            maxLength: 400,
            decoration: InputDecoration(
              hintText: '¿Qué recordarás de este plan?',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
          hint: 'No se muestra a nadie; al organizador sólo le llega el promedio.',
        ),
        const SizedBox(height: 4),
        FilledButton(
          onPressed: ready && !_sending ? _submit : null,
          style: FilledButton.styleFrom(
            backgroundColor: _accent,
            minimumSize: const Size.fromHeight(52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          child: _sending
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white))
              : Text(ready ? 'Enviar calificación' : 'Elige las estrellas',
                  style: GoogleFonts.outfit(
                      fontSize: 16, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

class _Stars extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _Stars({required this.value, required this.onChanged});

  static const _labels = ['Malo', 'Regular', 'Bien', 'Muy bien', '¡Excelente!'];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 1; i <= 5; i++)
              Semantics(
                button: true,
                selected: i <= value,
                label: '$i de 5 estrellas',
                excludeSemantics: true,
                child: IconButton(
                  iconSize: 38,
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    onChanged(i);
                  },
                  icon: Icon(
                    i <= value ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: const Color(0xFFF59E0B),
                  ),
                ),
              ),
          ],
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Text(
            value == 0 ? 'Toca una estrella' : _labels[value - 1],
            key: ValueKey(value),
            style: GoogleFonts.outfit(
                fontWeight: FontWeight.w700, color: const Color(0xFFB45309)),
          ),
        ),
      ],
    );
  }
}
