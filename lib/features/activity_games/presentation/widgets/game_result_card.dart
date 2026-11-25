import 'dart:convert';

import 'package:flutter/material.dart';

import '../../data/activity_game_models.dart';
import 'game_ui.dart';

/// Tarjeta compacta del resultado de una partida dentro del chat.
///
/// Sólo muestra lo que se puede contar al terminar la ronda. Los votos de
/// cada persona no viajan en el mensaje.
class GameResultCard extends StatelessWidget {
  final GameResultPayload payload;
  final String authorName;
  final String timeLabel;
  final VoidCallback onRematch;

  const GameResultCard({
    super.key,
    required this.payload,
    required this.authorName,
    required this.timeLabel,
    required this.onRematch,
  });

  /// Interpreta el texto descifrado de un mensaje `game_result`.
  static GameResultPayload? parse(String text) {
    try {
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic>
          ? GameResultPayload.tryParse(decoded)
          : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF8B5CF6);
    final p = GamePalette.of(context, accent);
    final won = payload.groupWon;
    final color = won ? const Color(0xFF22C55E) : const Color(0xFFEF4444);

    return Semantics(
      container: true,
      label: 'Resultado de El Impostor: ${payload.summary}. '
          '${payload.participants} jugadores.',
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: accent.withValues(alpha: 0.35)),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.14),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF4C1D95), Color(0xFF7C3AED)],
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.theater_comedy_rounded,
                          color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text('El Impostor · resultado',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 13.5)),
                      ),
                      Text(timeLabel,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 11)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                            won
                                ? Icons.groups_rounded
                                : Icons.theater_comedy_rounded,
                            color: color,
                            size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              won ? '¡Ganó el grupo!' : '¡Ganó el impostor!',
                              style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                  color: p.text),
                            ),
                            const SizedBox(height: 2),
                            Text(payload.summary,
                                style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.3,
                                    color: p.muted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      GameChip(
                          text: '${payload.participants} jugadores',
                          color: accent,
                          icon: Icons.people_alt_rounded),
                      if (payload.word != null)
                        GameChip(
                            text: 'Palabra: ${payload.word}',
                            color: accent,
                            icon: Icons.key_rounded),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Text('Compartido por $authorName',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: p.muted)),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: onRematch,
                        icon: const Icon(Icons.replay_rounded, size: 18),
                        label: const Text('Revancha'),
                        style: TextButton.styleFrom(
                          foregroundColor: p.accentText,
                          textStyle:
                              const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
