import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat_message_model.dart';
import '../models/contribution_model.dart';
import '../crypto/chat_crypto.dart';

/// ══════════════════════════════════════════════════════════════
///  SupabaseChatRepository — Chat de grupo y aportes de actividad
///
///  Reemplaza a la antigua API PHP (chat.php / contributions.php
///  sobre XAMPP + MySQL remoto). Todo corre en Supabase local.
/// ══════════════════════════════════════════════════════════════
class SupabaseChatRepository {
  final SupabaseClient _supabase;

  SupabaseChatRepository({SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  String get _currentUserId {
    final id = _supabase.auth.currentUser?.id;
    if (id == null) throw Exception('No hay sesión activa en Supabase.');
    return id;
  }

  // ── Listar mensajes del chat ──────────────────────────────
  Future<List<ChatMessage>> getMessages(String activityId) async {
    final rows = await _supabase
        .from('chat_messages')
        .select('''
          id, user_id, message, type, sent_at, is_pinned, is_edited,
          author:profiles!chat_messages_user_id_fkey(display_name, profile_image_url),
          images:chat_message_images(image_url),
          reactions:chat_message_reactions(user_id, reaction),
          reads:chat_message_reads(user_id, read_at, reader:profiles(display_name))
        ''')
        .eq('activity_id', activityId)
        .eq('is_deleted', false)
        .order('sent_at', ascending: false)
        .limit(100);

    final conversation = ConversationRef.activity(activityId);
    // De una sola vez: así la clave de cada época se resuelve y se cachea una
    // vez para toda la tanda en lugar de por mensaje.
    final decrypted = await ChatCrypto.instance.decryptAll(
      conversation,
      [for (final row in rows as List) (row['message'] ?? '') as String],
    );

    return [
      for (final (index, row) in (rows as List).indexed)
        _toMessage(row as Map<String, dynamic>, decrypted[index]),
    ];
  }

  ChatMessage _toMessage(Map<String, dynamic> row, DecryptedText text) {
    final author = row['author'] as Map<String, dynamic>? ?? {};
    final images = (row['images'] as List? ?? [])
        .map((i) => i['image_url'] as String)
        .toList();

    // Mapear al formato que espera ChatMessage.fromJson
    return ChatMessage.fromJson({
      'id': row['id'],
      'user_id': row['user_id'],
      'userName': author['display_name'] ?? 'Usuario',
      'userImageUrl': author['profile_image_url'] ?? '',
      'message': ChatCrypto.displayText(text),
      'decryptionStatus': text.status,
      'sent_at': row['sent_at'],
      'is_pinned': row['is_pinned'],
      'is_edited': row['is_edited'],
      'type': row['type'],
      if (images.isNotEmpty) 'imageUrls': images,
      'reactions': (row['reactions'] as List? ?? [])
          .map((r) => {'userId': r['user_id'], 'reaction': r['reaction']})
          .toList(),
      'readBy': (row['reads'] as List? ?? [])
          .map((r) => {
                'userId': r['user_id'],
                'userName': (r['reader'] as Map<String, dynamic>?)?['display_name'] ?? 'Usuario',
                'readAt': r['read_at'],
              })
          .toList(),
    });
  }

  // ── Marcar todos los mensajes de la actividad como leídos ──
  Future<void> markRead(String activityId) async {
    try {
      await _supabase.rpc('mark_chat_read', params: {'p_activity_id': activityId});
    } catch (e) {
      debugPrint('Error en mark_chat_read: $e');
    }
  }

  // ── Enviar mensaje (texto y/o imagen) ─────────────────────
  /// [message] llega **en claro**: el cifrado ocurre aquí dentro.
  ///
  /// Que lo haga el repositorio y no cada pantalla es deliberado — es la única
  /// forma de que no se escape un mensaje sin cifrar por olvido en una de las
  /// llamadas.
  ///
  /// Devuelve el id del mensaje y la ruta del adjunto si lo hubo.
  Future<({String id, String? imagePath})> sendMessage({
    required String activityId,
    required String message,
    File? image,
  }) async {
    final userId = _currentUserId;
    final conversation = ConversationRef.activity(activityId);

    String type = 'text';
    String? imagePath;
    if (image != null) {
      type = 'image';
      imagePath = await ChatCrypto.instance.uploadImage(
        conversation: conversation,
        image: image,
      );
    }

    final inserted = await _supabase
        .from('chat_messages')
        .insert({
          'activity_id': activityId,
          'user_id': userId,
          'message': await ChatCrypto.instance.encryptText(conversation, message),
          'type': type,
        })
        .select('id')
        .single();

    final messageId = inserted['id'] as String;

    if (imagePath != null) {
      await _supabase.from('chat_message_images').insert({
        'message_id': messageId,
        'image_url': imagePath,
      });
    }

    return (id: messageId, imagePath: imagePath);
  }

  // ── Publicar el resultado de una partida ──────────────────
  /// Tarjeta de resultado del centro de juegos. Se cifra como cualquier
  /// mensaje: el payload es JSON en claro sólo dentro del grupo, y el tipo
  /// `game_result` es lo único que ve el servidor.
  Future<String> sendGameResult({
    required String activityId,
    required Map<String, dynamic> payload,
  }) async {
    final conversation = ConversationRef.activity(activityId);
    final inserted = await _supabase
        .from('chat_messages')
        .insert({
          'activity_id': activityId,
          'user_id': _currentUserId,
          'message': await ChatCrypto.instance
              .encryptText(conversation, jsonEncode(payload)),
          'type': 'game_result',
        })
        .select('id')
        .single();
    return inserted['id'] as String;
  }

  // ── Editar mensaje propio ─────────────────────────────────
  /// [newMessage] llega en claro y se cifra aquí, igual que al enviarlo.
  ///
  /// Se cifra con la época **vigente**, no con la del mensaje original: si el
  /// grupo rotó, el texto editado sólo debe ser legible para quienes están
  /// ahora.
  Future<void> editMessage(
    String activityId,
    String messageId,
    String newMessage,
  ) async {
    final encrypted = await ChatCrypto.instance
        .encryptText(ConversationRef.activity(activityId), newMessage);

    await _supabase
        .from('chat_messages')
        .update({'message': encrypted, 'is_edited': true})
        .eq('id', messageId)
        .eq('user_id', _currentUserId);
  }

  // ── Eliminar mensaje (borrado suave) ──────────────────────
  Future<void> deleteMessage(String messageId) async {
    await _supabase.from('chat_messages').update({
      'is_deleted': true,
      'deleted_at': DateTime.now().toIso8601String(),
    }).eq('id', messageId);
  }

  // ── Alternar reacción ─────────────────────────────────────
  /// Devuelve 'added' | 'updated' | 'removed'.
  Future<String> toggleReaction(String messageId, String reaction) async {
    final result = await _supabase.rpc('toggle_chat_reaction', params: {
      'p_message_id': messageId,
      'p_reaction': reaction,
    });
    return result as String? ?? 'added';
  }

  // ══════════════════════════════════════════════════════════
  //  Aportes / Contribuciones
  // ══════════════════════════════════════════════════════════

  Future<List<Contribution>> getContributions(String activityId) async {
    final rows = await _supabase
        .from('contributions')
        .select(
            '*, assignee:profiles!contributions_assigned_to_user_id_fkey(display_name, profile_image_url)')
        .eq('activity_id', activityId)
        .order('created_at', ascending: true);

    return (rows as List).map((r) {
      final assignee = r['assignee'] as Map<String, dynamic>?;
      return Contribution(
        id: r['id'] as String,
        activityId: r['activity_id'] as String,
        title: r['title'] as String,
        description: (r['description'] ?? '') as String,
        category: (r['category'] ?? 'other') as String,
        isRequired: (r['is_required'] ?? false) as bool,
        assignedToUserId: r['assigned_to_user_id'] as String?,
        assignedToUserName: assignee?['display_name'] as String?,
        assignedToUserImage: assignee?['profile_image_url'] as String?,
        createdAt: DateTime.parse(r['created_at'] as String),
        createdByUserId: r['created_by_user_id'] as String,
      );
    }).toList();
  }

  Future<void> createContribution({
    required String activityId,
    required String title,
    String description = '',
    String category = 'other',
  }) async {
    await _supabase.from('contributions').insert({
      'activity_id': activityId,
      'created_by_user_id': _currentUserId,
      'title': title,
      'description': description,
      'category': category,
      'is_required': false,
    });
  }

  Future<void> assignContribution(String contributionId) async {
    await _supabase.from('contributions').update({
      'assigned_to_user_id': _currentUserId,
      'assigned_at': DateTime.now().toIso8601String(),
    }).eq('id', contributionId);
  }

  Future<void> unassignContribution(String contributionId) async {
    await _supabase.from('contributions').update({
      'assigned_to_user_id': null,
      'assigned_at': null,
    }).eq('id', contributionId);
  }
}
