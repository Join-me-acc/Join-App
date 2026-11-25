# Join — Estado del proyecto y continuación

> Documento de traspaso para retomar el trabajo en una sesión nueva.
> Fecha: 7 de agosto de 2026 · Rama: `migracion-supabase` · 14 commits sin mergear a `master`

---

## 1. Qué es y cómo está montado

**Join** es una app Flutter para encontrar y organizar actividades en grupo, centrada en Perú.

| Pieza | Estado |
|---|---|
| Backend | **Supabase local en Docker** (único backend; la API PHP/MySQL fue eliminada) |
| API / Kong | `http://127.0.0.1:54321` · Studio `:54323` · Postgres `:54322` |
| Emulador Android | Accede por `http://10.0.2.2:54321` (valor por defecto en `main.dart`) |
| Dispositivo físico | Requiere `adb reverse tcp:54321 tcp:54321` **y** `--dart-define=SUPABASE_URL=http://127.0.0.1:54321` |
| Estado global | `AppState` con Provider (1.002 líneas) + `LocationTracker` |
| Navegación | GoRouter; `initialLocation: '/'` → `SplashScreen` decide destino |

### Comandos habituales

```bash
npx supabase start
```

```bash
flutter run -d emulator-5554
```

### Métricas actuales

- `flutter analyze` → **0 issues**
- `flutter test` → **148 tests pasando**
- 19 migraciones SQL en `supabase/migrations/`

---

## 2. Lo que se hizo en esta sesión (14 commits)

### 🔴 Seguridad — el trabajo más importante

**`c3cf8ed` Row Level Security en todas las tablas.**
Sólo 4 de 20 tablas tenían RLS. Con la anon key —que va dentro del APK y por tanto es pública— cualquiera podía leer todos los perfiles (teléfono, fecha de nacimiento, email), leer cualquier chat y borrar actividades ajenas.

Verificado contra la base: la anon key ahora devuelve `[]` habiendo filas, y un intento de borrado responde **401**.

Dos comportamientos que se conservaron a propósito:
- La inscripción grupal crea solicitudes a nombre de otros miembros del clan → permitido **sólo entre compañeros del mismo clan**.
- El organizador puede moderar mensajes ajenos, como ya ofrecía la interfaz.

**`20260807120000_harden_storage.sql` Endurecimiento de Storage.**
Cualquier autenticado podía subir a cualquier bucket un archivo de cualquier tamaño y tipo, con el nombre que quisiera. Ahora:

| Candado | Cómo |
|---|---|
| Espacio propio | Cada objeto vive en `<uid>/…` y las políticas sólo aceptan la carpeta propia |
| Tamaño | 5 MiB en `avatars`, 10 MiB en `activities` y `chat` |
| Tipo | Sólo JPEG, PNG, WEBP, HEIC y HEIF |
| Borrar / actualizar | Siguen exigiendo `owner`, y ahora también la carpeta |

El `USING` del UPDATE era `bucket_id IN (…)` a secas: se podía apuntar a un objeto ajeno mientras el resultado quedara a nombre propio.

Verificado con dos usuarios reales contra el Supabase local: subir a la carpeta de otro y a la raíz del bucket → **403**; 6 MB en `avatars` → **413**; un `.txt` disfrazado → **415**; borrar el archivo del otro → **403**; y la lectura pública sigue en **200**, que es lo que se quiere (los tres buckets son públicos a propósito).

La lectura no se restringió: mientras el bucket sea público, las URLs se sirven sin pasar por RLS y cerrar el `SELECT` no ocultaría nada. (El bucket `chat` sí pasó a privado después, con el cifrado.)

**`20260807160000_e2e_encryption.sql` Cifrado de extremo a extremo de verdad.**
La interfaz prometía "cifrado de extremo a extremo" y `EncryptionService` usaba una clave AES escrita en el código: quien abriera el APK leía todos los chats. Ahora:

| Pieza | Cómo |
|---|---|
| Identidad | Par X25519 por usuario, derivado de una frase de 12 palabras. La privada vive en el llavero del sistema y nunca sale del móvil |
| Clave de grupo | Una AES-256-GCM por **época** de cada conversación |
| Reparto | La clave de la época se guarda una vez por miembro, envuelta con su clave pública (X25519 + HKDF + AES-GCM, con clave efímera en cada envoltorio) |
| Rotación | Época nueva al entrar o salir alguien, y también si un miembro reinstala y cambia de clave |
| Imágenes | Cifradas en el móvil antes de subir; el bucket `chat` pasa a privado y sólo admite datos opacos |
| Histórico | Los mensajes anteriores se siguen leyendo con la clave antigua — no se pierde nada |

**Verificado contra la base con tres usuarios reales** (`dart run tool/verify_e2e_encryption.dart`, 18 comprobaciones): quien no está en el clan no ve mensajes, ni épocas, ni claves, ni puede repartirse una; un miembro no ve el envoltorio de otro; quien entra después no puede leer lo anterior aunque ya vea que existe; quien conserva la clave vieja no abre lo nuevo; y el bucket rechaza subir una foto sin cifrar.

Lo que el cifrado **no** oculta, y conviene no olvidar: quién habla con quién, cuándo y cuánto. Eso son metadatos y siguen en el servidor.

### 🟠 Bugs encontrados y corregidos

Ninguno estaba en el análisis inicial; todos salieron de verificar en vez de suponer:

| # | Bug | Commit |
|---|---|---|
| 1 | **Sesión perdida injustamente**: si faltaba el token local con Supabase logueado, expulsaba al login | `60ed05a` |
| 2 | **Actividades de tu región invisibles**: el servidor las descartaba aunque el cliente las daba por cercanas | `720e6b3` |
| 3 | **Avatar roto sin foto de perfil** (ocurre con datos reales) | `720e6b3` |
| 4 | **Actividad sin portada rompía la tarjeta** (`Unable to load asset`) | `720e6b3` |
| 5 | **Ruta `/activity/:id` inexistente** en el botón de feedback | `d351de9` |
| 6 | **Likes fantasma** en la galería (resto de los mocks) | `d351de9` |
| 7 | **Spinner infinito** al editar una actividad borrada | `78badb9` |
| 8 | **Notificaciones que nunca se actualizaban** estando en pantalla | `7ed0af6` |
| 9 | **Recomendaciones de deportes en planes académicos** | `2a58510` |

### 🟡 Calidad

- `flutter analyze`: **66 → 0**
- Tests: **1 roto → 90 pasando**
- `AppState`: **1.374 → 1.002 líneas** (se extrajo `LocationTracker`)
- Eliminado `MockActivityRepository` y `lib/core/data/` completa

### 🔵 Funcionalidad

- **Ubicación en tiempo real** por stream con `distanceFilter: 100m` en vez de sondear el GPS cada 4 s
- **Notificaciones en vivo** por Realtime (antes sólo se cargaban al abrir una pantalla)
- **Chats**: adjuntar desde cámara o galería, imágenes en el chat de clan, cabecera que abre la info del grupo
- **Nueva pantalla de info del clan** (sustituye a la hoja deslizable)
- **Splash animado**: logo cayendo con rebote + "Cargando experiencia" + barra de progreso
- **App renombrada a "Join"** en Android e iOS
- **7 categorías** (nuevas: Académico y Juegos online) y **52 subcategorías**
- **Portadas por categoría** con opción de subir la propia

---

## 3. Decisiones de diseño que conviene conocer

### Una sola categoría principal por plan
La principal decide **portada, color, icono y recomendaciones** — todos de valor único. Permitir varias obligaba al código a quedarse con "la primera" en silencio. El selector funciona como radio.

**Consecuencia:** no se puede marcar "Naturaleza + Comida". Queda pendiente decidir si las subcategorías deberían poder ser de cualquier rama (ver §4).

### Una sola fuente para cada cosa
Se eliminaron duplicaciones que causaban desincronización:

| Antes | Ahora |
|---|---|
| Colores de categoría en 3 sitios | `CategoryConstants` |
| `juninKeywords` en 2 archivos | `PeruGeography` |
| Recomendaciones en 3 listas distintas | `ActivityRecommendations` |
| Imagen por defecto con su propia lista de palabras clave | Deriva de las categorías |

### Supabase es la única autoridad sobre la sesión
Se eliminó el JWT duplicado en SharedPreferences, que además nunca se leía.

### El splash decide cuándo salir
No se deja al `redirect` del router, que la expulsaría a media animación en cuanto la sesión terminara de restaurarse. Sale cuando **animación terminada Y `AppState` inicializado**.

### La frase de recuperación *es* la clave
No es una copia guardada en ningún sitio: de esos 16 bytes de entropía sale, siempre igual, el par X25519 del usuario. Por eso apuntarla basta para recuperar el historial en otro móvil y por eso nadie más puede hacerlo.

**Consecuencia que hay que asumir:** si alguien reinstala sin la frase, sus conversaciones anteriores quedan ilegibles para siempre — también para nosotros. Es inherente al cifrado real, no un fallo. La pantalla de la frase lo dice con esas palabras en vez de esconderlo.

### Épocas en vez de una clave por conversación
Una sola clave permanente obligaría a elegir entre que quien entra lea todo el pasado o que quien sale siga leyendo el futuro. Con una clave por época se resuelven los dos: al cambiar la membresía se abre una nueva y se reparte sólo a los de ahora.

La rotación la dispara **el cliente**, porque el servidor no tiene con qué envolver claves. La hace cualquier miembro que abra el chat y note el cambio; si dos coinciden, el `UNIQUE (scope, scope_id, epoch)` decide y el perdedor relee la del otro.

Para saber si hay que rotar se compara una **huella** del conjunto (miembro, clave pública), guardada en la propia época. Incluir la clave y no sólo el id es lo que hace que reinstalar dispare la rotación: el usuario es el mismo, su clave no.

### Un mensaje no se puede mover de sitio
El cifrado lleva como dato autenticado `scope:id:época`. Copiar un mensaje de un chat a otro, o reetiquetarlo a otra época, hace que la comprobación de integridad falle y no se abra. Está probado en los tests.

### Descifrar informa, nunca inventa
`decryptText` no lanza ni devuelve basura: distingue **ok**, **histórico**, **sin clave** (mensajes anteriores a la entrada al grupo — funcionamiento normal, no un error) y **corrupto**. La interfaz pinta cada caso con su propio texto, en cursiva, para que se vea que es un aviso de la app y no algo que escribiera alguien.

### Imágenes con licencia verificada
Se eliminó `activity_2_football.jpg`: era una foto de prensa de un club real con marcas visibles. Las 7 portadas nuevas son de **Pexels** (licencia libre, uso comercial, sin atribución obligatoria). Cada una fue revisada visualmente con dos criterios: que salgan **grupos** (Join va de planes en común) y que representen la **categoría entera**, no una actividad suelta.

---

## 4. Pendiente de decisión del usuario

Ninguno está empezado. Ordenados por criterio propio:

### 🌐 1. Subir las migraciones a la nube
**Todo lo de RLS, el filtro, el endurecimiento de Storage y el cifrado está aplicado sólo en el Supabase local.** Al desplegar hace falta:

```bash
npx supabase db push
```

Sin esto, el proyecto remoto seguiría con las tablas abiertas.

### 🎙️ 2. Audio en los chats
Implica: dependencia nueva (`record` + `just_audio`), permiso `RECORD_AUDIO`, migración de base de datos (ni `clan_messages` ni `chat_messages` tienen columna de audio) y UI de grabar/reproducir. Es una funcionalidad completa, no un ajuste.

### 🔤 3. Empaquetar la fuente Outfit
`pubspec.yaml` no declara fuentes, así que `google_fonts` descarga Outfit en tiempo de ejecución: **sin internet, la tipografía no carga en el primer arranque**.

### 📍 4. Cambio de ciudad automático o preguntado
Hoy muestra un diálogo al detectar otra ciudad. Se puede hacer automático.

### 🏷️ 5. Subcategorías de cualquier rama
Permitiría "Naturaleza + Parrilladas". Implica rehacer el selector para mostrar las 45 subcategorías.

---

## 5. Descartado conscientemente

No por falta de tiempo, sino por decisión razonada:

| Descartado | Motivo |
|---|---|
| **738 colores hardcodeados** → `AppColors` | Diff enorme, cero beneficio visible, riesgo real de romper la interfaz sin tests de UI |
| **Trocear pantallas gigantes** (perfil 3.190 líneas, onboarding 2.931) | Ídem |
| **Split de `AppState` en 4 providers** | 20 pantallas dependen de él. Se eligió delegar (extraer `LocationTracker`) manteniendo la API pública: 0 pantallas tocadas |
| **Optimizar el jank de arranque** | Medido en build `--profile`: 52 frames una vez, contra 275 en debug. **No es un problema real**; los números de debug son engañosos |

---

## 6. Cosas que muerden

- **`flutter run` no acepta teclas** desde estas herramientas (no hay stdin). Para hot restart hay que relanzar el proceso.
- **Nunca canalizar `flutter run` a `tail`/`head`**: el pipe bufferiza y no se ve nada hasta que el proceso termina, y `flutter run` no termina.
- **Daemons de Gradle huérfanos** provocan deadlocks silenciosos (0 % CPU esperando un lock). Si un build se queda colgado: `./gradlew --stop` y matar los `java.exe`.
- **Timeouts de Gradle** ya configurados en `android/gradle.properties`: sin ellos, una conexión colgada a Maven bloquea el build indefinidamente.
- **Presión de memoria**: Docker (~3,7 GB) + emulador (~3,4 GB) + Gradle (~1 GB) + Android Studio han tumbado a la vez los contenedores y el `system_server` del emulador. Si algo se congela, mirar RAM antes que el código.
- **El emulador Realme/Oppo** vuelve a pedir autorización USB tras cada reinicio; es normal del fabricante.
- **Desinstalar la app borra la sesión** de Supabase (se guarda en el almacenamiento de la app).
- **`flutter_secure_storage` 11 exige `compileSdk 37`**, que aún no es estable, y el build de Android falla con `Failed to find target with hash string 'android-37'`. Está fijado a **9.2.4**, que compila sin tocar nada.
- **`supabase` (el paquete puro, sólo para `tool/`) va fijado a 2.10.6**: dejarlo abierto arrastraba `supabase_flutter` de 2.12.4 a 2.17.1 sin necesidad.
- **El cliente Dart puro necesita flujo implícito**: `SupabaseClient` usa PKCE por defecto y exige un almacenamiento asíncrono que sólo existe dentro de Flutter. Sin `AuthClientOptions(authFlowType: AuthFlowType.implicit)`, `signUp` revienta con un *null check* dentro de gotrue.
- **Desinstalar sin la frase de recuperación deja el historial ilegible.** Es el precio del cifrado real, no un fallo: la clave está en el llavero del móvil y en ningún otro sitio.
- **El registro de migraciones se desincroniza** si alguna se aplica a mano: `supabase_migrations.schema_migrations` se queda corta y `migration up` reintenta las ya aplicadas hasta fallar. Se arregla sin perder datos con `npx supabase migration repair --status applied <versión> --local`; `db reset` también sirve pero borra la base local.

---

## 7. Estructura relevante

```
lib/core/
  location/
    peru_geography.dart        Regiones, distritos y cercanía (17 tests)
    location_tracker.dart      GPS por stream, geocodificación, discrepancia
  models/
    interest_model.dart        Categorías, subcategorías, portadas (28 tests)
    activity_recommendations.dart  Qué llevar a cada plan (15 tests)
    activity_model.dart        Portada por defecto incluida
  services/
    storage_paths.dart         Rutas `<uid>/…`, MIME y tamaño (16 tests)
    encryption_service.dart    El cifrado ANTERIOR — sólo para leer histórico
  crypto/                      El cifrado real (36 tests)
    recovery_phrase.dart       Entropía ↔ 12 palabras (BIP39, con checksum)
    join_identity.dart         Par X25519 y envoltorio de claves de grupo
    group_cipher.dart          AES-GCM de mensajes e imágenes, con AAD
    identity_store.dart        Llavero del sistema + publicación de la pública
    group_key_service.dart     Épocas, rotación y caché de claves
    chat_crypto.dart           Fachada única: es lo que usan pantallas y repos
  widgets/
    user_avatar.dart           Avatar con iniciales si no hay foto
    encrypted_chat_image.dart  Descarga y descifra los adjuntos del chat
  providers/app_state.dart     Estado global (delega ubicación)

lib/features/
  splash/                      Pantalla de carga animada
  clans/                       Chat e info del clan
  profile/.../recovery_phrase_screen.dart   Ver, copiar y restaurar la frase
  activity/.../widgets/
    activity_not_found.dart    Estado "no disponible"
  main/.../widgets/
    cover_picker_sheet.dart    Selector de portada

tool/
  verify_e2e_encryption.dart   Verifica el cifrado contra el Supabase local

supabase/migrations/
  20260806120000_enable_rls_on_all_tables.sql   RLS + políticas
  20260806140000_activities_near_rpc.sql        Filtro por zona sin concatenar texto
  20260807120000_harden_storage.sql             Carpeta por usuario, tamaño y MIME
  20260807160000_e2e_encryption.sql             Claves, épocas y bucket privado
```

### Comprobar el cifrado

```bash
dart run tool/verify_e2e_encryption.dart
```

---

## 8. Para llevar a master

```bash
git checkout master && git merge migracion-supabase
```
