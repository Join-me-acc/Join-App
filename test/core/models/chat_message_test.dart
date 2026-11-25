import 'package:flutter_test/flutter_test.dart';
import 'package:join_app/core/crypto/group_cipher.dart';
import 'package:join_app/core/models/chat_message_model.dart';

void main() {
  Map<String, dynamic> fila({
    String mensaje = 'hola',
    DecryptionStatus? estado,
  }) =>
      {
        'id': 'msg-1',
        'user_id': 'u-1',
        'userName': 'Ana',
        'message': mensaje,
        'sent_at': '2026-08-07T12:00:00Z',
        if (estado != null) 'decryptionStatus': estado,
      };

  group('ChatMessage y el cifrado', () {
    test('el texto llega tal cual: descifrar ya no es cosa del modelo', () {
      // El modelo recibe el resultado; la clave depende de la conversación y
      // de la época, y buscarla es asíncrono.
      final msg = ChatMessage.fromJson(fila(mensaje: 'v2.1.abc.def'));

      expect(msg.message, 'v2.1.abc.def');
    });

    test('sin estado se asume legible', () {
      final msg = ChatMessage.fromJson(fila());

      expect(msg.decryptionStatus, DecryptionStatus.ok);
      expect(msg.isReadable, isTrue);
    });

    test('un mensaje del histórico es legible', () {
      final msg = ChatMessage.fromJson(
          fila(estado: DecryptionStatus.legacy));

      expect(msg.isReadable, isTrue);
    });

    test('sin la clave de su época no es legible', () {
      final msg = ChatMessage.fromJson(fila(estado: DecryptionStatus.noKey));

      expect(msg.isReadable, isFalse);
    });

    test('un mensaje corrupto no es legible', () {
      final msg = ChatMessage.fromJson(fila(estado: DecryptionStatus.corrupt));

      expect(msg.isReadable, isFalse);
    });

    test('copyWith conserva el estado al editar el texto', () {
      // Al editar en local tras confirmar el envío, el mensaje sigue siendo
      // tan legible como era: perder el estado lo marcaría como ilegible.
      final msg = ChatMessage.fromJson(fila(estado: DecryptionStatus.legacy));

      final editado = msg.copyWith(message: 'texto nuevo', isEdited: true);

      expect(editado.message, 'texto nuevo');
      expect(editado.decryptionStatus, DecryptionStatus.legacy);
      expect(editado.isReadable, isTrue);
    });
  });
}
