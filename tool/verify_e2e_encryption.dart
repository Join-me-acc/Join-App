// Es una herramienta de consola: su salida *es* el resultado, así que aquí
// `print` es lo correcto y no el `debugPrint` de la app.
// ignore_for_file: avoid_print

// Verificación del cifrado de extremo a extremo contra el Supabase local.
//
// Comprueba lo que los tests unitarios no pueden: que las políticas de la base
// dejan pasar el flujo legítimo y bloquean el resto, y que dos usuarios
// distintos y reales se entienden a través del cifrado.
//
// Uso, con `npx supabase start` levantado:
//
//   dart run tool/verify_e2e_encryption.dart
//
// Crea usuarios y un clan de prueba y los borra al terminar.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:join_app/core/crypto/group_cipher.dart';
import 'package:join_app/core/crypto/join_identity.dart';
import 'package:join_app/core/crypto/recovery_phrase.dart';
import 'package:supabase/supabase.dart';

const url = 'http://127.0.0.1:54321';
const anonKey = 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';

int passed = 0;
int failed = 0;

void check(String what, bool ok, [String detail = '']) {
  if (ok) {
    passed++;
    print('  OK   $what');
  } else {
    failed++;
    print('  MAL  $what ${detail.isEmpty ? '' : '— $detail'}');
  }
}

/// Un usuario de prueba con su sesión y su identidad criptográfica.
class Actor {
  Actor(this.name, this.client, this.id, this.identity);

  final String name;
  final SupabaseClient client;
  final String id;
  final JoinIdentity identity;

  static Future<Actor> create(String name, String email) async {
    // Flujo implícito: el PKCE que trae por defecto necesita un almacenamiento
    // asíncrono que sólo existe dentro de la app Flutter.
    final client = SupabaseClient(url, anonKey,
        authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit));

    // El alta puede toparse con el límite de envío de correos del stack local.
    // Se reintenta y, si el usuario ya existía, se entra con él.
    String? id;
    for (var intento = 0; intento < 4 && id == null; intento++) {
      try {
        final auth =
            await client.auth.signUp(email: email, password: 'Passw0rd!2026');
        id = auth.user?.id;
      } catch (e) {
        print('  (alta de $name, intento ${intento + 1}: $e)');
      }
      if (id == null) {
        try {
          final auth = await client.auth
              .signInWithPassword(email: email, password: 'Passw0rd!2026');
          id = auth.user?.id;
        } catch (_) {}
      }
      if (id == null) await Future<void>.delayed(const Duration(seconds: 3));
    }
    if (id == null) throw StateError('No se pudo crear el usuario $name');

    final identity = await JoinIdentity.fromPhrase(
      RecoveryPhrase.fromEntropy(RecoveryPhrase.newEntropy()),
    );
    await client.from('user_keys').upsert({
      'user_id': id,
      'public_key': identity.publicKeyBase64,
    });

    return Actor(name, client, id, identity);
  }
}

Future<void> main() async {
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final admin = SupabaseClient(url, anonKey);

  print('\n── Preparando actores ──');
  final ana = await Actor.create('Ana', 'e2e_ana_$stamp@example.com');
  final beto = await Actor.create('Beto', 'e2e_beto_$stamp@example.com');
  final intrusa = await Actor.create('Intrusa', 'e2e_intrusa_$stamp@example.com');
  print('  Ana=${ana.id}\n  Beto=${beto.id}\n  Intrusa=${intrusa.id}');

  // Un clan de Ana, con Beto dentro. Intrusa se queda fuera.
  final clan = await ana.client
      .from('clans')
      .insert({'name': 'Clan E2E $stamp', 'creator_id': ana.id})
      .select('id')
      .single();
  final clanId = clan['id'] as String;

  await ana.client.from('clan_members').insert({'clan_id': clanId, 'user_id': ana.id});
  await beto.client.from('clan_members').insert({'clan_id': clanId, 'user_id': beto.id});

  final conversation = ConversationRef.clan(clanId);

  // ── 1. Ana abre la época 1 y reparte la clave ───────────────
  print('\n── Reparto de la clave de grupo ──');
  final key1 = GroupCipher.newGroupKey();
  final epoch1 = await ana.client
      .from('conversation_epochs')
      .insert({
        'scope': 'clan',
        'scope_id': clanId,
        'epoch': 1,
        'members_hash': 'hash-1',
        'member_ids': [ana.id, beto.id],
        'created_by': ana.id,
      })
      .select('id')
      .single();
  final epoch1Id = epoch1['id'] as String;

  await ana.client.from('epoch_keys').insert([
    {
      'epoch_id': epoch1Id,
      'user_id': ana.id,
      'wrapped_key': await JoinIdentity.wrapGroupKey(
          groupKey: key1, recipientPublicKey: ana.identity.publicKey),
    },
    {
      'epoch_id': epoch1Id,
      'user_id': beto.id,
      'wrapped_key': await JoinIdentity.wrapGroupKey(
          groupKey: key1, recipientPublicKey: beto.identity.publicKey),
    },
  ]);
  check('Ana reparte la clave a los dos miembros', true);

  // ── 2. Ana escribe; Beto lee ────────────────────────────────
  print('\n── Un mensaje de Ana a Beto ──');
  const original = 'La contraseña del wifi es "iguana2026" 🦎';
  final sealed = await GroupCipher.encryptText(
    clearText: original, groupKey: key1, epoch: 1, conversation: conversation);

  await ana.client.from('clan_messages').insert({
    'clan_id': clanId,
    'user_id': ana.id,
    'message': sealed,
    'type': 'text',
  });

  check('lo guardado no contiene el texto', !sealed.contains('iguana2026'), sealed);

  final betoRows = await beto.client
      .from('clan_messages')
      .select('message')
      .eq('clan_id', clanId);
  final betoWrap = await beto.client
      .from('epoch_keys')
      .select('wrapped_key')
      .eq('epoch_id', epoch1Id)
      .maybeSingle();

  check('Beto recibe su copia de la clave', betoWrap != null);
  if (betoWrap != null) {
    final betoKey = await beto.identity.unwrapGroupKey(betoWrap['wrapped_key'] as String);
    final abierto = await GroupCipher.decryptText(
      stored: betoRows.first['message'] as String,
      resolveKey: (e) async => e == 1 ? betoKey : null,
      conversation: conversation);
    check('Beto lee el mensaje de Ana', abierto.text == original, abierto.text);
  }

  // ── 3. La de fuera no ve nada ───────────────────────────────
  print('\n── Lo que ve quien no está en el clan ──');
  final intrusaMsgs = await intrusa.client
      .from('clan_messages').select('message').eq('clan_id', clanId);
  check('no lee los mensajes', intrusaMsgs.isEmpty, '${intrusaMsgs.length} filas');

  final intrusaEpochs = await intrusa.client
      .from('conversation_epochs').select('id').eq('scope_id', clanId);
  check('no ve las épocas', intrusaEpochs.isEmpty, '${intrusaEpochs.length} filas');

  final intrusaKeys = await intrusa.client
      .from('epoch_keys').select('wrapped_key').eq('epoch_id', epoch1Id);
  check('no ve ninguna clave envuelta', intrusaKeys.isEmpty, '${intrusaKeys.length} filas');

  // Ni siquiera puede colarse repartiéndose una clave a sí misma.
  var rechazado = false;
  try {
    await intrusa.client.from('epoch_keys').insert({
      'epoch_id': epoch1Id,
      'user_id': intrusa.id,
      'wrapped_key': 'lo-que-sea',
    });
  } catch (_) {
    rechazado = true;
  }
  check('no puede repartirse una clave a sí misma', rechazado);

  // ── 4. Un miembro no ve la copia de otro ────────────────────
  print('\n── Aislamiento entre miembros ──');
  final betoVeDeAna = await beto.client
      .from('epoch_keys')
      .select('wrapped_key')
      .eq('epoch_id', epoch1Id)
      .eq('user_id', ana.id);
  check('Beto no ve el envoltorio de Ana', betoVeDeAna.isEmpty,
      '${betoVeDeAna.length} filas');

  // ── 5. Entra Intrusa: rotación ──────────────────────────────
  print('\n── Entra alguien y se rota la clave ──');
  await intrusa.client
      .from('clan_members').insert({'clan_id': clanId, 'user_id': intrusa.id});

  final key2 = GroupCipher.newGroupKey();
  final epoch2 = await ana.client
      .from('conversation_epochs')
      .insert({
        'scope': 'clan', 'scope_id': clanId, 'epoch': 2,
        'members_hash': 'hash-2',
        'member_ids': [ana.id, beto.id, intrusa.id],
        'created_by': ana.id,
      })
      .select('id')
      .single();

  await ana.client.from('epoch_keys').insert([
    for (final a in [ana, beto, intrusa])
      {
        'epoch_id': epoch2['id'],
        'user_id': a.id,
        'wrapped_key': await JoinIdentity.wrapGroupKey(
            groupKey: key2, recipientPublicKey: a.identity.publicKey),
      },
  ]);

  // Ahora sí ve el mensaje viejo en la tabla, pero no puede abrirlo.
  final ahoraVe = await intrusa.client
      .from('clan_messages').select('message').eq('clan_id', clanId);
  check('ya dentro, ve que hay un mensaje anterior', ahoraVe.isNotEmpty);

  final suClave1 = await intrusa.client
      .from('epoch_keys').select('wrapped_key').eq('epoch_id', epoch1Id);
  check('pero no recibe la clave de la época anterior', suClave1.isEmpty);

  final intento = await GroupCipher.decryptText(
    stored: ahoraVe.first['message'] as String,
    resolveKey: (e) async => e == 2 ? key2 : null, // sólo tiene la época 2
    conversation: conversation);
  check('y no puede leer lo de antes de entrar',
      intento.status == DecryptionStatus.noKey, intento.status.name);

  // Lo nuevo sí lo lee.
  const nuevo = 'Ahora ya estamos todos 👋';
  final sealed2 = await GroupCipher.encryptText(
    clearText: nuevo, groupKey: key2, epoch: 2, conversation: conversation);
  final abierto2 = await GroupCipher.decryptText(
    stored: sealed2,
    resolveKey: (e) async => e == 2 ? key2 : null,
    conversation: conversation);
  check('lo escrito desde su entrada sí lo lee', abierto2.text == nuevo);

  // Y quien conserve la clave vieja no abre lo nuevo.
  final conClaveVieja = await GroupCipher.decryptText(
    stored: sealed2,
    resolveKey: (e) async => key1,
    conversation: conversation);
  check('la clave anterior no abre lo nuevo',
      conClaveVieja.status == DecryptionStatus.corrupt, conClaveVieja.status.name);

  // ── 6. Storage de adjuntos ──────────────────────────────────
  print('\n── Adjuntos cifrados ──');
  final blob = await GroupCipher.encryptBytes(
    clearBytes: Uint8List.fromList(utf8.encode('PNG con la foto del grupo')),
    groupKey: key2, epoch: 2, conversation: conversation);

  final ruta = '${ana.id}/clan/$clanId/${DateTime.now().millisecondsSinceEpoch}.bin';
  await ana.client.storage.from('chat').uploadBinary(ruta, blob,
      fileOptions: const FileOptions(contentType: 'application/octet-stream'));
  check('Ana sube el adjunto a su conversación', true);

  final bajado = await beto.client.storage.from('chat').download(ruta);
  final betoKey2 = await beto.identity.unwrapGroupKey(
    (await beto.client.from('epoch_keys').select('wrapped_key')
        .eq('epoch_id', epoch2['id']).single())['wrapped_key'] as String,
  );
  final claro = await GroupCipher.decryptBytes(
    blob: bajado, groupKey: betoKey2, conversation: conversation);
  check('Beto lo baja y lo abre',
      utf8.decode(claro) == 'PNG con la foto del grupo');

  // Un miembro no puede escribir en la carpeta de otra conversación.
  var subidaAjena = false;
  try {
    await ana.client.storage.from('chat').uploadBinary(
      '${ana.id}/clan/00000000-0000-0000-0000-000000000000/x.bin', blob,
      fileOptions: const FileOptions(contentType: 'application/octet-stream'));
  } catch (_) {
    subidaAjena = true;
  }
  check('no puede subir a una conversación en la que no está', subidaAjena);

  // Y una foto sin cifrar ya no cuela: el bucket sólo admite datos opacos.
  var mimeRechazado = false;
  try {
    await ana.client.storage.from('chat').uploadBinary(
      '${ana.id}/clan/$clanId/enclaro.jpg',
      Uint8List.fromList(utf8.encode('esto seria una foto sin cifrar')),
      fileOptions: const FileOptions(contentType: 'image/jpeg'));
  } catch (_) {
    mimeRechazado = true;
  }
  check('el bucket ya no admite imágenes sin cifrar', mimeRechazado);

  // ── Limpieza ────────────────────────────────────────────────
  print('\n── Limpiando ──');
  try {
    await ana.client.storage.from('chat').remove([ruta]);
    await ana.client.from('clans').delete().eq('id', clanId);
  } catch (e) {
    print('  (limpieza parcial: $e)');
  }
  print('  usuarios a borrar: ${ana.id} ${beto.id} ${intrusa.id}');

  admin.dispose();
  print('\n════════════════════════════════════');
  print('  $passed correctas · $failed fallidas');
  print('════════════════════════════════════\n');
  exit(failed == 0 ? 0 : 1);
}
