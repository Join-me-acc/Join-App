import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:join_app/features/activity_games/domain/game_catalog.dart';
import 'package:join_app/features/activity_games/domain/game_logic.dart';

void main() {
  group('splitIntoTeams', () {
    test('reparte a todos sin repetir y con tamaños parejos', () {
      final players = List.generate(11, (i) => 'P$i');
      final teams = splitIntoTeams(players, 3, Random(1));
      expect(teams, hasLength(3));
      expect(teams.expand((t) => t).toSet(), players.toSet());
      final sizes = teams.map((t) => t.length).toList()..sort();
      expect(sizes.last - sizes.first, lessThanOrEqualTo(1));
    });
  });

  group('Bracket', () {
    test('8 jugadores: 3 rondas sin pases directos', () {
      final b = Bracket.seeded(List.generate(8, (i) => 'P$i'), random: Random(2));
      expect(b.rounds.map((r) => r.length), [4, 2, 1]);
      expect(b.rounds.first.any((m) => m.isBye), isFalse);
      expect(b.roundName(0), 'Cuartos de final');
      expect(b.roundName(2), 'Final');
    });

    test('5 jugadores: 3 pases directos que ya avanzan', () {
      final b = Bracket.seeded(List.generate(5, (i) => 'P$i'), random: Random(3));
      expect(b.rounds.first.where((m) => m.isBye), hasLength(3));
      final names = <String>{
        for (final m in b.rounds.first) ...[m.a, m.b].whereType<String>(),
      };
      expect(names, hasLength(5));
      // Los ganadores por pase directo ya están en la ronda siguiente.
      expect(b.rounds[1][0].isPlayable, isTrue);
    });

    test('jugar hasta la final declara campeón', () {
      final b = Bracket.seeded(['A', 'B', 'C', 'D'], random: Random(4));
      for (var m = 0; m < 2; m++) {
        b.setWinner(0, m, b.rounds[0][m].a!);
      }
      final finalMatch = b.rounds[1][0];
      expect(finalMatch.isPlayable, isTrue);
      b.setWinner(1, 0, finalMatch.b!);
      expect(b.champion, finalMatch.b);
    });

    test('cambiar un resultado anterior borra lo que dependía de él', () {
      final b = Bracket.seeded(['A', 'B', 'C', 'D'], random: Random(5));
      final first = b.rounds[0][0];
      b.setWinner(0, 0, first.a!);
      b.setWinner(0, 1, b.rounds[0][1].a!);
      b.setWinner(1, 0, first.a!);
      expect(b.champion, first.a);

      b.setWinner(0, 0, first.b!);
      expect(b.rounds[1][0].a, first.b);
      expect(b.champion, isNull);
    });

    test('no acepta como ganador a quien no juega el partido', () {
      final b = Bracket.seeded(['A', 'B', 'C', 'D'], random: Random(6));
      b.setWinner(0, 0, 'Z');
      expect(b.rounds[0][0].winner, isNull);
    });
  });

  group('Bingo', () {
    test('cuenta filas, columnas y diagonales', () {
      expect(completedBingoLines({}), 0);
      expect(completedBingoLines({0, 1, 2}), 1);
      expect(completedBingoLines({0, 4, 8}), 1);
      expect(completedBingoLines({0, 1, 2, 3, 6}), 2);
      expect(completedBingoLines({0, 1, 2, 3, 4, 5, 6, 7, 8}), 8);
    });

    test('el cartón tiene 9 casillas distintas', () {
      final card = pickBingoCard(
          GameCatalog.forCategory('Naturaleza').bingo, Random(7));
      expect(card, hasLength(9));
      expect(card.toSet(), hasLength(9));
    });
  });

  group('Trivia', () {
    test('barajar opciones conserva la respuesta correcta', () {
      const q = TriviaQuestion('¿?', ['a', 'b', 'c', 'd'], 2);
      for (var seed = 0; seed < 20; seed++) {
        final s = shuffleOptions(q, Random(seed));
        expect(s.options[s.answer], 'c');
        expect(s.options.toSet(), {'a', 'b', 'c', 'd'});
      }
    });

    test('pickTrivia no repite preguntas', () {
      final round =
          pickTrivia(GameCatalog.forCategory('Comida').trivia, 8, Random(8));
      expect(round, hasLength(8));
      expect(round.map((q) => q.question).toSet(), hasLength(8));
    });
  });

  test('drawFresh evita lo reciente mientras haya alternativas', () {
    final items = ['a', 'b', 'c'];
    for (var seed = 0; seed < 10; seed++) {
      expect(drawFresh(items, ['a', 'b'], Random(seed)).single, 'c');
    }
    expect(drawFresh(items, items, Random(1)).single, isIn(items));
  });
}
