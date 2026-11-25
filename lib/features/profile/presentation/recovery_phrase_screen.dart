import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:join_app/core/crypto/chat_crypto.dart';
import 'package:join_app/core/crypto/recovery_phrase.dart';
import 'package:join_app/core/providers/app_state.dart';
import 'package:join_app/core/theme/app_colors.dart';

/// La frase de recuperación: verla, copiarla y restaurarla en otro móvil.
///
/// Es el único sitio de la app donde aparecen las 12 palabras. No se envían a
/// ningún servidor —ni al de Join—, así que si el usuario las pierde y cambia
/// de dispositivo, sus conversaciones anteriores no las recupera nadie. La
/// pantalla lo dice con esas palabras: es la contrapartida honesta de que el
/// cifrado sea real.
class RecoveryPhraseScreen extends StatefulWidget {
  const RecoveryPhraseScreen({super.key});

  @override
  State<RecoveryPhraseScreen> createState() => _RecoveryPhraseScreenState();
}

class _RecoveryPhraseScreenState extends State<RecoveryPhraseScreen> {
  final TextEditingController _restoreController = TextEditingController();

  String? _phrase;
  bool _revealed = false;
  bool _loading = true;
  bool _restoring = false;
  String? _restoreError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _restoreController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final userId = context.read<AppState>().currentUser?.id;
    if (userId == null) {
      setState(() => _loading = false);
      return;
    }
    final phrase =
        await ChatCrypto.instance.identities.recoveryPhraseFor(userId);
    if (!mounted) return;
    setState(() {
      _phrase = phrase;
      _loading = false;
    });
  }

  Future<void> _copy() async {
    if (_phrase == null) return;
    await Clipboard.setData(ClipboardData(text: _phrase!));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Frase copiada. Guárdala en un sitio seguro.')),
    );
  }

  Future<void> _restore() async {
    final userId = context.read<AppState>().currentUser?.id;
    if (userId == null) return;

    final typed = _restoreController.text;
    if (!RecoveryPhrase.isValid(typed)) {
      setState(() => _restoreError =
          'Esa frase no es válida. Deben ser las 12 palabras, en orden y bien escritas.');
      return;
    }

    setState(() {
      _restoring = true;
      _restoreError = null;
    });

    try {
      await ChatCrypto.instance.identities
          .restoreFrom(userId: userId, phrase: typed);
      // La identidad ha cambiado: lo cacheado con la anterior ya no sirve.
      ChatCrypto.instance.onSignOut();
      await ChatCrypto.instance.onSignIn(userId);

      if (!mounted) return;
      _restoreController.clear();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Identidad restaurada en este dispositivo.')),
      );
    } catch (e) {
      if (mounted) setState(() => _restoreError = '$e');
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0D14) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          'Frase de recuperación',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                _Explanation(isDark: isDark),
                const SizedBox(height: 20),
                _phraseCard(isDark),
                const SizedBox(height: 28),
                _restoreCard(isDark),
              ],
            ),
    );
  }

  Widget _phraseCard(bool isDark) {
    if (_phrase == null) {
      return _Card(
        isDark: isDark,
        child: Text(
          'Todavía no hay una identidad en este dispositivo. Se creará sola la '
          'primera vez que abras un chat.',
          style: TextStyle(
            fontSize: 13,
            height: 1.45,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ),
      );
    }

    final words = _phrase!.split(' ');

    return _Card(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tus 12 palabras',
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : AppColors.navyBlue,
            ),
          ),
          const SizedBox(height: 14),
          if (!_revealed)
            // No se enseñan de entrada: evita que aparezcan en una captura o a
            // la vista de quien esté al lado sin que el usuario lo decida.
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _revealed = true),
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('Mostrar la frase'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            )
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < words.length; i++)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : AppColors.navyBlue.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      '${i + 1}. ${words[i]}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : AppColors.navyBlue,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _copy,
                    icon: const Icon(Icons.copy_rounded, size: 17),
                    label: const Text('Copiar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => setState(() => _revealed = false),
                    icon: const Icon(Icons.visibility_off_outlined, size: 17),
                    label: const Text('Ocultar'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _restoreCard(bool isDark) {
    return _Card(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Restaurar en este dispositivo',
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : AppColors.navyBlue,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Si vienes de otro móvil, escribe aquí sus 12 palabras para volver a '
            'leer tus conversaciones. La identidad de este dispositivo se '
            'sustituirá por aquella.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _restoreController,
            maxLines: 3,
            enabled: !_restoring,
            decoration: InputDecoration(
              hintText: 'palabra1 palabra2 palabra3 …',
              errorText: _restoreError,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            style: const TextStyle(fontSize: 13.5),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _restoring ? null : _restore,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _restoring
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Restaurar identidad'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Explanation extends StatelessWidget {
  const _Explanation({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.amber.withValues(alpha: 0.08)
            : const Color(0xFFFEF9C3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.amber.withValues(alpha: 0.2)
              : const Color(0xFFFDE68A),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.key_rounded,
                  size: 18,
                  color: isDark ? Colors.amber[200] : const Color(0xFFB45309)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Estas palabras son tu clave',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color:
                        isDark ? Colors.amber[200] : const Color(0xFFB45309),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Tus chats se cifran en este móvil y sólo tú tienes la clave: en Join '
            'no la guardamos, así que no podemos leer tus mensajes ni '
            'devolvértelos si la pierdes.\n\n'
            'Apunta las 12 palabras en papel o en un gestor de contraseñas. Si '
            'reinstalas la app o cambias de móvil sin ellas, seguirás usando Join '
            'con normalidad, pero las conversaciones anteriores quedarán '
            'ilegibles para siempre.\n\n'
            'Quien tenga estas palabras puede leer tus chats. No las compartas '
            'con nadie.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: isDark ? Colors.amber[100] : const Color(0xFF854D0E),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.isDark, required this.child});

  final bool isDark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141824) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
        ),
      ),
      child: child,
    );
  }
}
