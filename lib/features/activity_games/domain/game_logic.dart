import 'dart:math';

import 'game_catalog.dart';

/// Reparte [players] en [teamCount] equipos al azar, con tamaños que difieren
/// a lo sumo en uno.
List<List<String>> splitIntoTeams(
    List<String> players, int teamCount, Random random) {
  assert(teamCount >= 2);
  final shuffled = [...players]..shuffle(random);
  final teams = List.generate(teamCount, (_) => <String>[]);
  for (final (i, player) in shuffled.indexed) {
    teams[i % teamCount].add(player);
  }
  return teams;
}

// ════════════════════════════════════════════════════════════════════
//  Bracket de eliminación directa
// ════════════════════════════════════════════════════════════════════

class BracketMatch {
  String? a;
  String? b;
  String? winner;

  /// Primera ronda con un solo jugador: pasa directo.
  final bool isBye;

  BracketMatch({this.a, this.b, this.winner, this.isBye = false});

  bool get isPlayable => a != null && b != null;
}

class Bracket {
  final List<List<BracketMatch>> rounds;

  Bracket._(this.rounds);

  /// Sortea las llaves. Si los jugadores no son potencia de dos, los
  /// primeros sorteados pasan directo a la segunda ronda.
  factory Bracket.seeded(List<String> players, {Random? random}) {
    assert(players.length >= 2);
    final shuffled = [...players]..shuffle(random ?? Random());
    var size = 1;
    while (size < shuffled.length) {
      size *= 2;
    }
    final byes = size - shuffled.length;

    final first = <BracketMatch>[];
    var next = 0;
    for (var m = 0; m < size ~/ 2; m++) {
      if (m < byes) {
        final player = shuffled[next++];
        first.add(BracketMatch(a: player, winner: player, isBye: true));
      } else {
        first.add(BracketMatch(a: shuffled[next++], b: shuffled[next++]));
      }
    }

    final rounds = <List<BracketMatch>>[first];
    for (var count = size ~/ 4; count >= 1; count ~/= 2) {
      rounds.add(List.generate(count, (_) => BracketMatch()));
    }

    final bracket = Bracket._(rounds);
    for (final (m, match) in first.indexed) {
      if (match.isBye) bracket._propagate(0, m);
    }
    return bracket;
  }

  String? get champion => rounds.last.single.winner;

  String roundName(int round) {
    final fromEnd = rounds.length - 1 - round;
    return switch (fromEnd) {
      0 => 'Final',
      1 => 'Semifinales',
      2 => 'Cuartos de final',
      3 => 'Octavos de final',
      _ => 'Ronda ${round + 1}',
    };
  }

  /// Marca a [winner] como ganador y lo pasa a la ronda siguiente. Si cambia
  /// un resultado ya jugado, se borran los que dependían de él.
  void setWinner(int round, int match, String winner) {
    final m = rounds[round][match];
    if (!m.isPlayable || (winner != m.a && winner != m.b)) return;
    m.winner = winner;
    _propagate(round, match);
  }

  void _propagate(int round, int match) {
    if (round + 1 >= rounds.length) return;
    final winner = rounds[round][match].winner;
    final target = rounds[round + 1][match ~/ 2];
    final previous = match.isEven ? target.a : target.b;
    if (previous == winner) return;
    if (match.isEven) {
      target.a = winner;
    } else {
      target.b = winner;
    }
    if (target.winner != null) {
      target.winner = null;
      _propagate(round + 1, match ~/ 2);
    }
  }
}

// ════════════════════════════════════════════════════════════════════
//  Bingo 3×3
// ════════════════════════════════════════════════════════════════════

const _bingoLines = [
  [0, 1, 2], [3, 4, 5], [6, 7, 8], // filas
  [0, 3, 6], [1, 4, 7], [2, 5, 8], // columnas
  [0, 4, 8], [2, 4, 6], // diagonales
];

/// Cuántas líneas completas hay entre las casillas [marked] (0–8).
int completedBingoLines(Set<int> marked) =>
    _bingoLines.where((line) => line.every(marked.contains)).length;

List<String> pickBingoCard(List<String> items, Random random) {
  final pool = [...items]..shuffle(random);
  return pool.take(9).toList();
}

// ════════════════════════════════════════════════════════════════════
//  Trivia
// ════════════════════════════════════════════════════════════════════

/// [count] preguntas al azar con las opciones barajadas.
List<TriviaQuestion> pickTrivia(
    List<TriviaQuestion> questions, int count, Random random) {
  final pool = [...questions]..shuffle(random);
  return [
    for (final q in pool.take(count)) shuffleOptions(q, random),
  ];
}

TriviaQuestion shuffleOptions(TriviaQuestion q, Random random) {
  final order = List.generate(q.options.length, (i) => i)..shuffle(random);
  return TriviaQuestion(
    q.question,
    [for (final i in order) q.options[i]],
    order.indexOf(q.answer),
    fact: q.fact,
  );
}

/// Elige [count] elementos distintos de [items] sin repetir los de [recent]
/// mientras queden otros.
List<T> drawFresh<T>(List<T> items, List<T> recent, Random random,
    {int count = 1}) {
  final fresh = items.where((i) => !recent.contains(i)).toList();
  final pool = fresh.length >= count ? fresh : [...items];
  pool.shuffle(random);
  return pool.take(count).toList();
}
