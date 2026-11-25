import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';

import '../crypto/chat_crypto.dart';

/// Muestra una imagen del chat, descargándola y descifrándola en el momento.
///
/// Las fotos nuevas viven cifradas en un bucket privado, así que no hay URL
/// que pasarle a `Image.network`: hay que bajarlas autenticado y abrirlas con
/// la clave de su época. Las anteriores al cifrado sí son URLs públicas y se
/// siguen mostrando como siempre — el widget distingue por la propia
/// referencia y no hay que migrar nada.
class EncryptedChatImage extends StatefulWidget {
  const EncryptedChatImage({
    super.key,
    required this.reference,
    required this.conversation,
    this.width = 200,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = 12,
  });

  /// Ruta dentro del bucket privado, o URL para las de antes del cifrado.
  final String reference;
  final ConversationRef conversation;
  final double width;
  final double? height;
  final BoxFit fit;
  final double borderRadius;

  @override
  State<EncryptedChatImage> createState() => _EncryptedChatImageState();
}

class _EncryptedChatImageState extends State<EncryptedChatImage> {
  Future<Uint8List?>? _bytes;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(EncryptedChatImage old) {
    super.didUpdateWidget(old);
    if (old.reference != widget.reference) _start();
  }

  void _start() {
    if (!ChatCrypto.isEncryptedAttachment(widget.reference)) return;
    _bytes = ChatCrypto.instance.imageBytes(
      conversation: widget.conversation,
      path: widget.reference,
    );
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.borderRadius);

    // Histórico: URL pública de antes del cifrado.
    if (!ChatCrypto.isEncryptedAttachment(widget.reference)) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.network(
          widget.reference,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          errorBuilder: (_, __, ___) => _Placeholder(
            width: widget.width,
            height: widget.height,
            radius: radius,
            icon: Icons.broken_image_outlined,
            label: 'No se pudo cargar',
          ),
        ),
      );
    }

    return FutureBuilder<Uint8List?>(
      future: _bytes,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _Placeholder(
            width: widget.width,
            height: widget.height,
            radius: radius,
            icon: Icons.lock_outline_rounded,
            label: 'Descifrando…',
          );
        }

        final bytes = snap.data;
        if (bytes == null || bytes.isEmpty) {
          // Lo habitual aquí es una foto de antes de entrar al grupo: no se
          // tiene la clave de esa época y nunca se tendrá.
          return _Placeholder(
            width: widget.width,
            height: widget.height,
            radius: radius,
            icon: Icons.lock_rounded,
            label: 'Imagen no disponible',
          );
        }

        return ClipRRect(
          borderRadius: radius,
          child: Image.memory(
            bytes,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            errorBuilder: (_, __, ___) => _Placeholder(
              width: widget.width,
              height: widget.height,
              radius: radius,
              icon: Icons.broken_image_outlined,
              label: 'Archivo dañado',
            ),
          ),
        );
      },
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.width,
    required this.height,
    required this.radius,
    required this.icon,
    required this.label,
  });

  final double width;
  final double? height;
  final BorderRadius radius;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? Colors.white54 : Colors.black38;

    return Container(
      width: width,
      height: height ?? width * 0.66,
      decoration: BoxDecoration(
        borderRadius: radius,
        color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: foreground),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: foreground),
          ),
        ],
      ),
    );
  }
}
