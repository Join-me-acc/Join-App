import 'package:flutter_test/flutter_test.dart';
import 'package:join_app/core/models/chat_message_model.dart';
import 'package:join_app/features/activity_games/data/activity_game_models.dart';
import 'package:join_app/features/activity_games/presentation/widgets/game_result_card.dart';

Map<String, dynamic> sessionJson({
  String status = 'playing',
  Map<String, dynamic> state = const {},
}) =>
    {
      'id': 's1',
      'activity_id': 'a1',
      'game_type': 'impostor',
      'host_user_id': 'u1',
      'status': status,
      'round': 2,
      'state': state,
      'updated_at': '2026-11-24T10:00:00Z',
      'players': [
        {
          'user_id': 'u2',
          'display_order': 2,
          'is_ready': true,
          'last_seen_at': DateTime.now().toUtc().toIso8601String(),
          'profile': {'display_name': 'Beto', 'profile_image_url': ''},
        },
        {
          'user_id': 'u1',
          'display_order': 1,
          'is_ready': false,
          'last_seen_at': '2020-01-01T00:00:00Z',
          'profile': {'display_name': 'Ana'},
        },
      ],
    };

void main() {
  group('GameSession', () {
    test('ordena jugadores y lee la fase', () {
      final s = GameSession.fromJson(sessionJson(state: {
        'phase': 'voting',
        'votes_count': 1,
        'player_count': 2,
      }));
      expect(s.players.map((p) => p.displayName), ['Ana', 'Beto']);
      expect(s.phase, ImpostorPhase.voting);
      expect(s.votesCount, 1);
      expect(s.round, 2);
      expect(s.isPlayer('u2'), isTrue);
      expect(s.isPlayer('x'), isFalse);
    });

    test('el lobby es lobby aunque el estado diga otra cosa', () {
      final s = GameSession.fromJson(
          sessionJson(status: 'lobby', state: {'phase': 'voting'}));
      expect(s.phase, ImpostorPhase.lobby);
      expect(s.isActive, isTrue);
    });

    test('presencia según el último latido', () {
      final s = GameSession.fromJson(sessionJson());
      final now = DateTime.now();
      expect(s.playerById('u2')!.isOnline(now), isTrue);
      expect(s.playerById('u1')!.isOnline(now), isFalse);
    });

    test('lee el resultado calculado por el servidor', () {
      final s = GameSession.fromJson(sessionJson(status: 'finished', state: {
        'phase': 'result',
        'result': {
          'winner': 'group',
          'summary': 'El grupo descubrió a Beto',
          'impostor_id': 'u2',
          'impostor_name': 'Beto',
          'word': 'Cancha',
          'tally': [
            {'user_id': 'u2', 'votes': 2},
          ],
          'participants': 3,
        },
      }));
      final r = s.result!;
      expect(r.groupWon, isTrue);
      expect(r.tally['u2'], 2);
      expect(r.word, 'Cancha');
      expect(s.phase, ImpostorPhase.result);
    });
  });

  group('ImpostorRole', () {
    test('al impostor nunca se le asigna palabra', () {
      final role = ImpostorRole.fromJson({
        'round': 1,
        'state': {'role': 'impostor', 'word': 'filtrada'},
      });
      expect(role.isImpostor, isTrue);
      expect(role.word, isNull);
    });

    test('el resto recibe la palabra', () {
      final role = ImpostorRole.fromJson({
        'round': 3,
        'state': {'role': 'crew', 'word': 'Ceviche'},
      });
      expect(role.isImpostor, isFalse);
      expect(role.word, 'Ceviche');
      expect(role.round, 3);
    });
  });

  group('GameResultPayload', () {
    test('ida y vuelta por el texto del chat', () {
      const payload = GameResultPayload(
        game: 'impostor',
        sessionId: 's1',
        winner: 'impostor',
        summary: 'Ana se salió con la suya',
        participants: 5,
        word: 'Mochila',
      );
      final parsed = GameResultCard.parse(
          '{"game":"impostor","session_id":"s1","winner":"impostor",'
          '"summary":"Ana se salió con la suya","participants":5,"word":"Mochila"}');
      expect(parsed!.toJson(), payload.toJson());
      expect(parsed.groupWon, isFalse);
    });

    test('texto ilegible o ajeno no es una tarjeta', () {
      expect(GameResultCard.parse('Mensaje cifrado'), isNull);
      expect(GameResultCard.parse('{"hola":1}'), isNull);
      expect(GameResultCard.parse('[1,2]'), isNull);
    });

    test('no incluye votos individuales', () {
      const result = ImpostorResult(
        winner: 'group',
        summary: 'x',
        tally: {'u1': 3},
        participants: 4,
      );
      final json = GameResultPayload.fromResult('s1', result).toJson();
      expect(json.containsKey('tally'), isFalse);
      expect(json['participants'], 4);
    });
  });

  test('el tipo game_result se lee y se escribe con su nombre de la base', () {
    expect(MessageTypeX.fromString('game_result'), MessageType.gameResult);
    expect(MessageType.gameResult.wireName, 'game_result');
    expect(MessageTypeX.fromString('image'), MessageType.image);
    expect(MessageTypeX.fromString('desconocido'), MessageType.text);
  });
}
