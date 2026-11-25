import 'dart:math';
import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;

/// La frase de recuperación de 12 palabras.
///
/// No es una copia de la clave guardada en algún sitio: **es** la clave. De
/// estos 16 bytes de entropía sale, siempre igual, el par de claves del
/// usuario ([JoinIdentity]). Por eso apuntarla basta para recuperar el
/// historial en otro móvil, y por eso nadie más puede hacerlo — el servidor
/// no la ve nunca.
class RecoveryPhrase {
  const RecoveryPhrase._();

  /// 128 bits → 12 palabras. Suficiente margen frente a fuerza bruta y
  /// bastante más corto de copiar a mano que 24.
  static const int entropyBytes = 16;

  /// Entropía nueva a partir del generador seguro del sistema.
  static Uint8List newEntropy() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(entropyBytes, (_) => random.nextInt(256)),
    );
  }

  /// Las 12 palabras que representan [entropy].
  static String fromEntropy(Uint8List entropy) {
    if (entropy.length != entropyBytes) {
      throw ArgumentError('La entropía debe ser de $entropyBytes bytes.');
    }
    return bip39.entropyToMnemonic(_hex(entropy));
  }

  /// La entropía que hay detrás de [phrase].
  ///
  /// Lanza [FormatException] si la frase no es válida: BIP39 lleva checksum,
  /// así que una palabra mal copiada se detecta aquí y no más tarde con una
  /// clave silenciosamente equivocada que descifraría basura.
  static Uint8List toEntropy(String phrase) {
    final normalized = normalize(phrase);
    if (!bip39.validateMnemonic(normalized)) {
      throw const FormatException(
        'La frase de recuperación no es válida. Revisa que sean las 12 '
        'palabras, en el mismo orden y sin errores de escritura.',
      );
    }
    return _unhex(bip39.mnemonicToEntropy(normalized));
  }

  /// `true` si la frase está completa y el checksum cuadra.
  static bool isValid(String phrase) {
    try {
      toEntropy(phrase);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Deja la frase como la espera BIP39: minúsculas y un solo espacio entre
  /// palabras. El usuario la teclea a mano, así que llegará con mayúsculas
  /// del teclado, saltos de línea al pegarla y espacios de más.
  static String normalize(String phrase) =>
      phrase.trim().toLowerCase().split(RegExp(r'\s+')).join(' ');

  /// Los 64 bytes de semilla de los que cuelga la identidad.
  static Uint8List seedOf(String phrase) =>
      Uint8List.fromList(bip39.mnemonicToSeed(normalize(phrase)));

  static String _hex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List _unhex(String hex) => Uint8List.fromList([
        for (var i = 0; i < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ]);
}
