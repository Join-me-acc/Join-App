import 'package:flutter_test/flutter_test.dart';
import 'package:join_app/core/models/interest_model.dart';
import 'package:join_app/features/activity_games/domain/game_catalog.dart';

void main() {
  group('GameCatalog.forCategory', () {
    test('reconoce la categoría principal y la subcategoría guardada', () {
      final pack = GameCatalog.forCategory('Deportes,Fútbol');
      expect(pack.mainCategory, 'Deportes');
      expect(pack.subcategory, 'Fútbol');
      expect(pack.label, 'Fútbol');
    });

    test('las palabras de la subcategoría van antes que las de la principal', () {
      final pack = GameCatalog.forCategory('Deportes,Fútbol');
      expect(pack.impostorWords.first, 'Chimpunes');
      expect(pack.impostorWords, contains('Árbitro'));
    });

    test('una subcategoría sola resuelve su principal', () {
      final pack = GameCatalog.forCategory('Playa');
      expect(pack.mainCategory, 'Naturaleza');
      expect(pack.subcategory, 'Playa');
      expect(pack.bingo.first, 'Una concha');
    });

    test('sin categoría reconocida usa contenido general', () {
      final pack = GameCatalog.forCategory('Algo raro');
      expect(pack.mainCategory, isNull);
      expect(pack.impostorWords, contains('Karaoke'));
      expect(pack.featured, isNotEmpty);
      expect(pack.label, 'tu plan');
    });

    test('null no rompe', () {
      expect(GameCatalog.forCategory(null).impostorWords, isNotEmpty);
    });

    test('es indiferente a mayúsculas', () {
      expect(GameCatalog.forCategory('comida').mainCategory, 'Comida');
    });

    test('las sugerencias cambian según la categoría', () {
      expect(GameCatalog.forCategory('Deportes').featured.first, GameKind.teams);
      expect(GameCatalog.forCategory('Naturaleza').featured.first, GameKind.bingo);
      expect(GameCatalog.forCategory('Juegos online').featured.first,
          GameKind.bracket);
      expect(GameCatalog.forCategory('Académico').featured,
          contains(GameKind.debate));
    });
  });

  group('Contenido de cada categoría principal', () {
    for (final main in CategoryConstants.mainCategories) {
      test(main, () {
        final pack = GameCatalog.forCategory(main);
        expect(pack.mainCategory, main);
        // El Impostor necesita variedad para que no se repita la palabra.
        expect(pack.impostorWords.length, greaterThanOrEqualTo(8));
        expect(pack.initialChallenges.length, greaterThanOrEqualTo(4));
        // La trivia saca 8 preguntas por ronda.
        expect(pack.trivia.length, greaterThanOrEqualTo(8));
        // Un cartón de bingo tiene 9 casillas.
        expect(pack.bingo.length, greaterThanOrEqualTo(9));
        expect(pack.wouldYouRather, isNotEmpty);
        expect(pack.mostLikely, isNotEmpty);
        expect(pack.debateTopics, isNotEmpty);
        expect(pack.featured, isNotEmpty);
        expect(pack.impostorWords.toSet().length, pack.impostorWords.length,
            reason: 'palabras repetidas en $main');
      });
    }
  });

  test('cada pregunta de trivia tiene una respuesta válida', () {
    for (final main in [...CategoryConstants.mainCategories, null]) {
      for (final q in GameCatalog.forCategory(main).trivia) {
        expect(q.options.length, greaterThanOrEqualTo(2), reason: q.question);
        expect(q.answer, inInclusiveRange(0, q.options.length - 1),
            reason: q.question);
        expect(q.options.toSet().length, q.options.length, reason: q.question);
      }
    }
  });

  test('todos los juegos tienen metadatos', () {
    for (final kind in GameKind.values) {
      final info = GameCatalog.info[kind];
      expect(info, isNotNull, reason: '$kind sin GameInfo');
      expect(info!.kind, kind);
      expect(info.meta, contains('min'));
    }
  });
}
