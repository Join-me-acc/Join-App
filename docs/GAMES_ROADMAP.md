# Centro de juegos de Join

## Estado actual

Las fases 1 y 2 están implementadas y la 3 está avanzada.

- El botón **Juegos** del chat abre `/main/activity/:id/games`.
- El contenido y los juegos sugeridos dependen de la categoría del plan
  (principal y subcategoría: "Deportes,Fútbol" usa palabras de fútbol antes
  que las de deporte en general).
- **El Impostor en línea** (`/main/activity/:id/games/impostor`): cada
  participante se une desde su teléfono, ve sólo su rol y vota en secreto.
  El servidor reparte roles, cuenta votos y calcula el resultado.
- El resultado se publica en el chat como tarjeta (`game_result`), con botón
  de revancha.
- Reingreso: el centro de juegos muestra la sala activa del plan y permite
  volver a ella.
- 11 juegos locales que funcionan sin conexión (ver tabla).
- `flutter analyze` limpio y 203 pruebas en verde (49 nuevas de juegos).
- 25 pruebas de RLS y reglas en SQL contra el Supabase local en Docker.

## Juegos por categoría

| Categoría      | Sugeridos                                     |
|----------------|-----------------------------------------------|
| Deportes       | Armar equipos, Marcador rápido, Trivia        |
| Comida         | Trivia, ¿Qué prefieres?, ¿Quién es más probable? |
| Naturaleza     | Bingo de exploración, Trivia, ¿Qué prefieres? |
| Chill          | ¿Qué prefieres?, Trivia, ¿Quién es más probable? |
| Juntas         | ¿Quién es más probable?, ¿Qué prefieres?, Equipos |
| Académico      | Trivia, Debate exprés, Equipos                |
| Juegos online  | Bracket rápido, Equipos, Trivia               |
| Sin categoría  | ¿Qué prefieres?, ¿Quién es más probable?, Trivia |

Además, para cualquier plan: El Impostor en línea, El Impostor (un celular),
Dados y Reto por inicial. El resto aparece plegado en "Más juegos".

## Archivos principales

```
lib/features/activity_games/
  domain/game_catalog.dart        catálogo tipado: juegos, palabras, trivia,
                                  bingo, cartas y sugerencias por categoría
  domain/game_logic.dart          equipos, bracket, bingo y trivia (puro)
  data/activity_game_models.dart  sesión, jugador, rol propio, resultado
  data/activity_game_repository.dart  RPC + Realtime
  presentation/activity_game_controller.dart  reconexión, latido, cuenta
                                  regresiva, estado optimista, publicación
  presentation/activity_games_screen.dart     centro de juegos
  presentation/online/impostor_online_screen.dart  lobby → rol → votación
                                  → resultado
  presentation/games/             juegos locales
  presentation/widgets/game_ui.dart          kit visual compartido
  presentation/widgets/game_result_card.dart tarjeta del chat
supabase/migrations/20261124120000_activity_games.sql
supabase/tests/activity_games_test.sql
tool/preview_games.dart           arnés visual sin Supabase
```

`lib/features/activity_group/presentation/widgets/icebreaker_sheet.dart` ya no
se usa: su contenido pasó a `activity_games/`. Se puede borrar.

## Diseño de la parte sincronizada

- **Tablas**: `activity_game_sessions`, `activity_game_players`,
  `activity_game_private_state`, `activity_game_votes`,
  `activity_game_events`.
- **El rol secreto no está en `activity_game_players`**: RLS filtra filas, no
  columnas. Va en `activity_game_private_state`, donde cada usuario sólo lee
  su propia fila. Lo mismo con los votos.
- **Sólo lectura desde el cliente**: toda escritura pasa por RPC
  `SECURITY DEFINER` (`create_or_join_game_session`, `leave_game_session`,
  `set_game_ready`, `touch_game_presence`, `start_impostor_game`,
  `advance_impostor_to_voting`, `cast_impostor_vote`, `finish_impostor_game`,
  `cancel_game_session`, `rematch_game_session`,
  `get_activity_member_names`). Las funciones internas (`_impostor_finish`,
  etc.) no se pueden llamar desde la app.
- **Una sala activa por plan y juego** (índice único parcial): dos personas
  que crean sala a la vez terminan en la misma.
- **Ni el host sabe la palabra**: envía las candidatas del catálogo y el
  servidor elige una y al impostor dentro de la misma transacción.
- **Sin host no se traba**: al acabar el tiempo cualquier jugador puede abrir
  la votación; cuando votan todos la ronda se cierra sola. Si el host sale
  del lobby, la sala pasa al siguiente jugador.
- **Resultado en el chat**: lo calcula el servidor, pero lo publica el cliente
  del host porque el chat está cifrado de extremo a extremo y el servidor no
  tiene la clave del grupo. La tarjeta lleva ganador, resumen, palabra y
  número de jugadores; nunca los votos de cada persona.
- **Reconexión**: el controlador relee la sala cuando Realtime avisa, al
  volver la app a primer plano y cada 8 s como respaldo. Sin red conserva el
  último estado y muestra un aviso.

## Cómo aplicar y probar en local (Docker)

La migración ya está aplicada en `supabase_db_join` y registrada en
`supabase_migrations.schema_migrations`. Para repetir las pruebas SQL (se
ejecutan en una transacción que se deshace):

```powershell
Get-Content supabase/tests/activity_games_test.sql | docker exec -i supabase_db_join psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q
```

Vista previa de los juegos sin backend:

```powershell
flutter run -d chrome -t tool/preview_games.dart
```

## Pendiente

- Prueba con dos o más teléfonos reales o emuladores contra el Supabase
  local (requiere participantes en `activity_participants`).
- Prueba manual de pérdida de red durante una ronda en dispositivo.
- Dados y Reto por inicial sincronizados: la tabla ya admite esos
  `game_type`, faltan sus RPC.
- Registrar estadísticas no sensibles (partidas, victorias, participación) y
  logros visuales con celebraciones de la mascota.
- Mover el catálogo a una tabla administrable si se quiere editar sin
  publicar versión.
