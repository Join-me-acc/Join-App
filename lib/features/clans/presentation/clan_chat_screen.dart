import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:join_app/core/providers/app_state.dart';
import 'package:join_app/core/models/clan_model.dart';
import 'package:join_app/core/models/user_model.dart';
import 'package:join_app/core/crypto/chat_crypto.dart';
import 'package:join_app/core/widgets/encrypted_chat_image.dart';
import 'package:join_app/core/widgets/chat_chrome.dart';
import 'package:flutter/services.dart';
import 'package:join_app/core/theme/app_colors.dart';

class ClanChatScreen extends StatefulWidget {
  final String clanId;
  final Clan clan;

  const ClanChatScreen({
    super.key,
    required this.clanId,
    required this.clan,
  });

  @override
  State<ClanChatScreen> createState() => _ClanChatScreenState();
}

class _ClanChatScreenState extends State<ClanChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _reactions = [];
  StreamSubscription<List<Map<String, dynamic>>>? _messagesSubscription;
  RealtimeChannel? _reactionsChannel;

  Map<String, UserModel> _membersMap = {};
  bool _isLoadingMembers = true;
  bool _isLoadingMessages = true;

  /// Textos ya descifrados, indexados por el **texto cifrado**.
  ///
  /// Descifrar es asíncrono —hay que ir a por la clave de la época— y `build`
  /// no lo es, así que se resuelve al llegar cada tanda. La clave del mapa es
  /// el cifrado y no el id del mensaje a propósito: al editar uno, el id no
  /// cambia pero el contenido sí, y con el id como clave se seguiría viendo
  /// el texto anterior.
  final Map<String, DecryptedText> _decrypted = {};

  ConversationRef get _conversation => ConversationRef.clan(widget.clanId);

  @override
  void initState() {
    super.initState();
    _loadClanMembers();
    
    // Suscripción al stream de mensajes del clan en tiempo real
    _messagesSubscription = Supabase.instance.client
        .from('clan_messages')
        .stream(primaryKey: ['id'])
        .eq('clan_id', widget.clanId)
        .order('sent_at', ascending: false)
        .listen((data) {
          if (mounted) {
            setState(() {
              _messages = data;
              _isLoadingMessages = false;
            });
            _decryptPending(data);
            final messageIds = data.map((m) => m['id'] as String).toList();
            _loadReactions(messageIds);
          }
        });

    // Suscripción a los cambios en tiempo real en la tabla de reacciones
    _reactionsChannel = Supabase.instance.client
        .channel('public:clan_message_reactions')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'clan_message_reactions',
          callback: (payload) {
            final messageIds = _messages.map((m) => m['id'] as String).toList();
            _loadReactions(messageIds);
          },
        )
        .subscribe();
  }

  /// Descifra lo que aún no esté resuelto y repinta.
  ///
  /// Se limita a lo pendiente: al llegar un mensaje nuevo no se vuelve a
  /// descifrar toda la conversación.
  Future<void> _decryptPending(List<Map<String, dynamic>> data) async {
    final pending = <String>[
      for (final m in data)
        if (!_decrypted.containsKey((m['message'] ?? '') as String))
          (m['message'] ?? '') as String,
    ];
    if (pending.isEmpty) return;

    final resolved =
        await ChatCrypto.instance.decryptAll(_conversation, pending);
    if (!mounted) return;

    setState(() {
      for (var i = 0; i < pending.length; i++) {
        _decrypted[pending[i]] = resolved[i];
      }
    });
  }

  Future<void> _loadReactions(List<String> messageIds) async {
    if (messageIds.isEmpty) return;
    try {
      final data = await Supabase.instance.client
          .from('clan_message_reactions')
          .select('message_id, user_id, reaction')
          .inFilter('message_id', messageIds);
      if (mounted) {
        setState(() {
          _reactions = List<Map<String, dynamic>>.from(data);
        });
      }
    } catch (e) {
      debugPrint('Error cargando reacciones del clan: $e');
    }
  }

  Future<void> _loadClanMembers() async {
    try {
      final appState = context.read<AppState>();
      final members = await appState.getClanMembers(widget.clanId);
      final Map<String, UserModel> membersMap = {};
      for (final m in members) {
        if (m.userProfile != null) {
          membersMap[m.userId] = m.userProfile!;
        }
      }
      if (mounted) {
        setState(() {
          _membersMap = membersMap;
          _isLoadingMembers = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading clan members for chat mapping: $e');
      if (mounted) {
        setState(() => _isLoadingMembers = false);
      }
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messagesSubscription?.cancel();
    if (_reactionsChannel != null) {
      Supabase.instance.client.removeChannel(_reactionsChannel!);
    }
    super.dispose();
  }

  Future<void> _sendMessage({File? image}) async {
    final text = _messageController.text.trim();
    if (text.isEmpty && image == null) return;

    _messageController.clear();
    final appState = context.read<AppState>();
    final currentUserId = appState.currentUser?.id;
    if (currentUserId == null) return;

    try {
      String type = 'text';
      String? imagePath;
      if (image != null) {
        type = 'image';
        imagePath = await ChatCrypto.instance.uploadImage(
          conversation: _conversation,
          image: image,
        );
      }

      await Supabase.instance.client.from('clan_messages').insert({
        'clan_id': widget.clanId,
        'user_id': currentUserId,
        'message': await ChatCrypto.instance.encryptText(_conversation, text),
        'type': type,
        // Es la ruta dentro del bucket privado, no una URL: la imagen está
        // cifrada y sólo se abre desde dentro de la app.
        if (imagePath != null) 'image_url': imagePath,
      });
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al enviar mensaje: $e')),
        );
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: source, imageQuality: 70);
    if (image != null) {
      await _sendMessage(image: File(image.path));
    }
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.primaryOrange.withValues(alpha: 0.1),
                  child: const Icon(Icons.photo_camera_rounded, color: AppColors.primaryOrange),
                ),
                title: const Text('Cámara'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.primaryOrange.withValues(alpha: 0.1),
                  child: const Icon(Icons.photo_library_rounded, color: AppColors.primaryOrange),
                ),
                title: const Text('Galería'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  String _formatMessageTime(String timestampStr) {
    try {
      final timestamp = DateTime.parse(timestampStr).toLocal();
      final now = DateTime.now();
      final difference = now.difference(timestamp);

      if (difference.inMinutes < 1) return 'Ahora';
      if (difference.inMinutes < 60) return 'Hace ${difference.inMinutes}m';
      if (difference.inHours < 24) return 'Hace ${difference.inHours}h';
      return 'Hace ${difference.inDays}d';
    } catch (_) {
      return '';
    }
  }

  Future<void> _reactToMessage(String messageId, String reaction) async {
    HapticFeedback.mediumImpact();
    try {
      await Supabase.instance.client.rpc('toggle_clan_message_reaction', params: {
        'p_message_id': messageId,
        'p_reaction': reaction,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al reaccionar: $e')),
        );
      }
    }
  }

  Future<void> _editMessage(String messageId, String newText) async {
    try {
      // Con la clave de ahora, no con la del mensaje original: si el clan
      // rotó, lo editado sólo debe leerlo quien está hoy.
      final encryptedText =
          await ChatCrypto.instance.encryptText(_conversation, newText);
      await Supabase.instance.client
          .from('clan_messages')
          .update({
            'message': encryptedText,
            'is_edited': true,
          })
          .eq('id', messageId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al editar mensaje: $e')),
        );
      }
    }
  }

  Future<void> _deleteMessage(String messageId) async {
    try {
      await Supabase.instance.client
          .from('clan_messages')
          .update({
            'is_deleted': true,
            'deleted_at': DateTime.now().toIso8601String(),
          })
          .eq('id', messageId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al eliminar mensaje: $e')),
        );
      }
    }
  }

  void _showMessageOptions(Map<String, dynamic> message, String decryptedText) {
    final currentUserId = context.read<AppState>().currentUser?.id;
    final senderId = message['user_id'] as String;
    final isMine = senderId == currentUserId;
    final isCreator = widget.clan.creatorId == currentUserId;
    final messageId = message['id'] as String;
    final sentAtStr = message['sent_at'] as String;
    final sentAt = DateTime.parse(sentAtStr).toLocal();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: ['👍', '❤️', '😂', '😮', '😢', '👏'].map((emoji) => 
                InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    _reactToMessage(messageId, emoji);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(emoji, style: const TextStyle(fontSize: 28)),
                  ),
                )
              ).toList(),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.copy, color: Colors.blueGrey),
              title: const Text('Copiar texto'),
              onTap: () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(text: decryptedText));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Mensaje copiado al portapapeles')),
                );
              },
            ),
            if (isMine && DateTime.now().difference(sentAt).inSeconds <= 50)
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blue),
                title: const Text('Editar (50s)'),
                onTap: () {
                  Navigator.pop(context);
                  _showEditDialog(messageId, decryptedText);
                },
              ),
            if (isMine || isCreator)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Eliminar', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _deleteMessage(messageId);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _openClanInfo() {
    context.push('/clan/${widget.clanId}/info?fromChat=true', extra: widget.clan);
  }

  void _showEditDialog(String messageId, String currentText) {
    final controller = TextEditingController(text: currentText);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar mensaje'),
        content: TextField(
          controller: controller,
          maxLines: null,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              if (controller.text.trim().isNotEmpty) {
                _editMessage(messageId, controller.text.trim());
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentUserId = context.read<AppState>().currentUser?.id;

    final members = _membersMap.length;
    final subtitle = _isLoadingMembers
        ? 'Cargando miembros…'
        : '$members ${members == 1 ? 'miembro' : 'miembros'} · chat del clan';

    return Scaffold(
      body: Column(
        children: [
          ChatHeader(
            avatar: ChatAvatar(
              imageUrl: widget.clan.avatarUrl,
              accent: AppColors.primaryOrange,
              fallbackText: widget.clan.name,
            ),
            title: widget.clan.name,
            subtitle: subtitle,
            semanticLabel: 'Ver información del clan ${widget.clan.name}',
            onTapTitle: _openClanInfo,
            trailing: ChatHeaderIconButton(
              icon: Icons.groups_rounded,
              tooltip: 'Miembros del clan',
              onTap: _openClanInfo,
            ),
          ),
          // Stream de mensajes de chat
          Expanded(
            child: Container(
              decoration: chatWallpaper(isDark),
              child: _isLoadingMessages && _messages.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.primaryOrange),
                    )
                  : _messages.where((m) => m['is_deleted'] != true).isEmpty
                      ? ChatEmptyState(
                          icon: Icons.shield_rounded,
                          title: 'Habla con tu clan',
                          message:
                              'Aquí sólo entran los miembros del clan. Rompe el hielo o propón el próximo plan juntos.',
                          actions: [
                            ChatEmptyAction(
                                'Saludar', Icons.waving_hand_outlined, () {
                              _messageController.text = '¡Hola, clan! 👋';
                              _messageController.selection =
                                  TextSelection.collapsed(
                                      offset: _messageController.text.length);
                            }),
                            ChatEmptyAction('Miembros', Icons.groups_rounded,
                                _openClanInfo),
                          ],
                          securityLabel:
                              'Chat de clan cifrado de extremo a extremo',
                          onSecurity: () => context.push('/recovery-phrase'),
                        )
                      : Builder(builder: (context) {
                          final visibleMsgs = _messages.where((m) => m['is_deleted'] != true).toList();
                          return ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          itemCount: visibleMsgs.length + 1,
                          itemBuilder: (context, index) {
                            if (index == visibleMsgs.length) {
                              // Aviso de cifrado: parte del scroll — aparece al inicio del
                              // chat y se oculta naturalmente cuando hay más mensajes.
                              return Center(
                                // Toca y lleva a la frase de recuperación: es
                                // donde se ve que la clave es del usuario y
                                // conviene apuntarla.
                                child: GestureDetector(
                                  onTap: () => context.push('/recovery-phrase'),
                                  child: Container(
                                  margin: const EdgeInsets.only(bottom: 16),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF2D2A10) : const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isDark ? Colors.amber.withValues(alpha: 0.15) : const Color(0xFFFDE68A),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.lock_rounded,
                                        size: 11,
                                        color: isDark ? Colors.amber[200] : const Color(0xFFB45309),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Chat de clan encriptado de extremo a extremo',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: isDark ? Colors.amber[200] : const Color(0xFFB45309),
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        size: 13,
                                        color: isDark ? Colors.amber[200] : const Color(0xFFB45309),
                                      ),
                                    ],
                                  ),
                                ),
                                ),
                              );
                            }
                            final msg = visibleMsgs[index];
                            final senderId = msg['user_id'] as String;
                            final isMe = senderId == currentUserId;
                            final encryptedText = msg['message'] as String;
                            final resolved = _decrypted[encryptedText];
                            // Mientras la clave de la época está en camino se
                            // deja el hueco en blanco: es cosa de un instante
                            // y un texto provisional daría un parpadeo.
                            final decryptedText = resolved == null
                                ? ''
                                : ChatCrypto.displayText(resolved);
                            final isUnreadable =
                                resolved != null && !resolved.isReadable;
                            final timestampStr = msg['sent_at'] as String;
                            final messageId = msg['id'] as String;

                            // Resolve sender profile info
                            final senderProfile = _membersMap[senderId];
                            final senderName = senderProfile?.name ?? 'Miembro';
                            final senderImageUrl = senderProfile?.profileImageUrl ?? '';

                            // Resolve message reactions
                            final msgReactions = _reactions.where((r) => r['message_id'] == messageId).toList();

                            return Align(
                              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (!isMe) ...[
                                      CircleAvatar(
                                        radius: 16,
                                        backgroundColor: Colors.grey[300],
                                        backgroundImage: senderImageUrl.isNotEmpty
                                            ? NetworkImage(senderImageUrl)
                                            : null,
                                        child: senderImageUrl.isEmpty
                                            ? Text(senderName.substring(0, 1).toUpperCase())
                                            : null,
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    Flexible(
                                      child: GestureDetector(
                                        onLongPress: () => _showMessageOptions(msg, decryptedText),
                                        child: Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            Container(
                                              margin: EdgeInsets.only(bottom: msgReactions.isNotEmpty ? 12 : 0),
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                              decoration: BoxDecoration(
                                                gradient: isMe
                                                    ? const LinearGradient(
                                                        colors: [Color(0xFFFD7C36), Color(0xFFEA4E00)],
                                                        begin: Alignment.topLeft,
                                                        end: Alignment.bottomRight,
                                                      )
                                                    : null,
                                                color: isMe
                                                    ? null
                                                    : (isDark ? const Color(0xFF1E222B) : Colors.grey[100]),
                                                border: isMe
                                                    ? null
                                                    : Border.all(
                                                        color: isDark
                                                            ? Colors.white.withValues(alpha: 0.05)
                                                            : Colors.grey[200]!,
                                                        width: 1,
                                                      ),
                                                borderRadius: BorderRadius.only(
                                                  topLeft: const Radius.circular(20),
                                                  topRight: const Radius.circular(20),
                                                  bottomLeft: Radius.circular(isMe ? 20 : 0),
                                                  bottomRight: Radius.circular(isMe ? 0 : 20),
                                                ),
                                                boxShadow: isMe
                                                    ? [
                                                        BoxShadow(
                                                          color: const Color(0xFFFD7C36).withValues(alpha: 0.3),
                                                          blurRadius: 8,
                                                          spreadRadius: 1,
                                                          offset: const Offset(0, 4),
                                                        )
                                                      ]
                                                    : [],
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (!isMe)
                                                    Padding(
                                                      padding: const EdgeInsets.only(bottom: 3),
                                                      child: Text(
                                                        senderName,
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.w900,
                                                          color: isDark ? Colors.white70 : const Color(0xFF041249),
                                                        ),
                                                      ),
                                                    ),
                                                  if (msg['image_url'] != null && (msg['image_url'] as String).isNotEmpty)
                                                    Padding(
                                                      padding: EdgeInsets.only(bottom: decryptedText.isNotEmpty ? 6 : 0),
                                                      child: EncryptedChatImage(
                                                        reference: msg['image_url'] as String,
                                                        conversation: _conversation,
                                                      ),
                                                    ),
                                                  if (decryptedText.isNotEmpty)
                                                    Text(
                                                      decryptedText,
                                                      style: TextStyle(
                                                        fontSize: 13.5,
                                                        color: isMe
                                                            ? Colors.white
                                                            : (isDark ? Colors.white : Colors.black87),
                                                        height: 1.35,
                                                        // Lo que no se puede leer se marca en cursiva
                                                        // y atenuado: es un aviso de la app, no algo
                                                        // que haya escrito nadie.
                                                        fontStyle: isUnreadable
                                                            ? FontStyle.italic
                                                            : FontStyle.normal,
                                                      ),
                                                    ),
                                                  const SizedBox(height: 3),
                                                  Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    mainAxisAlignment: MainAxisAlignment.end,
                                                    children: [
                                                      Text(
                                                        _formatMessageTime(timestampStr),
                                                        style: TextStyle(
                                                          fontSize: 9.5,
                                                          color: isMe ? Colors.white70 : Colors.grey[500],
                                                        ),
                                                      ),
                                                      if (msg['is_edited'] == true) ...[
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          '(editado)',
                                                          style: TextStyle(
                                                            fontSize: 9.5,
                                                            color: isMe ? Colors.white70 : Colors.grey[500],
                                                            fontStyle: FontStyle.italic,
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (msgReactions.isNotEmpty)
                                              Positioned(
                                                bottom: 0,
                                                right: isMe ? 10 : null,
                                                left: isMe ? null : 10,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    borderRadius: BorderRadius.circular(12),
                                                    border: Border.all(color: Colors.grey.shade300),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.black.withValues(alpha: 0.05),
                                                        blurRadius: 4,
                                                        offset: const Offset(0, 2),
                                                      ),
                                                    ],
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: () {
                                                      final map = <String, int>{};
                                                      for (var r in msgReactions) {
                                                        final emoji = r['reaction'] as String;
                                                        map[emoji] = (map[emoji] ?? 0) + 1;
                                                      }
                                                      return map.entries.map((e) => Padding(
                                                        padding: const EdgeInsets.symmetric(horizontal: 2),
                                                        child: Text('${e.key} ${e.value}', style: const TextStyle(fontSize: 10, color: Colors.black)),
                                                      )).toList();
                                                    }(),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ).animate().fadeIn(duration: 250.ms);
                          },
                          );
                        }),
            ),
          ),

          ChatComposer(
            controller: _messageController,
            onAttach: _showAttachmentOptions,
            onSend: _sendMessage,
            hintText: 'Escribe a tu clan…',
          ),
        ],
      ),
    );
  }
}
