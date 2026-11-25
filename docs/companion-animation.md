# Personajes de Join — Eli, Drago y Halo

Implementado el 7 de octubre de 2026. Los dibujos originales se conservan.

## Qué está animado

`lib/core/widgets/companion_view.dart` dibuja a los tres compañeros mediante una malla texturizada
de Flutter. Zonas de influencia separadas articulan suavemente la cabeza, la
mano levantada y la cola. Los pies permanecen en el suelo. No es un modelo 3D
ni permite giros completos: está diseñado para gestos discretos de sus poses.

Cada personaje tiene coordenadas originales, máscaras de influencia y recorte
de retrato propios. Eli conserva su saludo con mano abierta; Drago saluda con
un pequeño movimiento del puño; Halo inclina la cabeza y mueve suavemente las
manos que sujetan la mochila. Los tres parpadean, asienten, piensan y celebran.

Los párpados usan únicamente las regiones de los ojos de los archivos `*-blink.png`,
mezcladas sobre la ilustración original. El resto de la imagen generada nunca
se muestra. Hay tres parpadeos espaciados en un ciclo de 13 segundos.

Estados: `idle`, `greet`, `thinking`, `nod`, `celebrate`. El entero `reaction`
permite repetir un gesto. Las reacciones duran 1,9 segundos; no se repiten
indefinidamente. La postura de pensamiento continúa mientras está activa.

`portrait` encuadra la cara de cada compañero para iconos pequeños. `animationsEnabled`
permite desactivar animaciones de avatares históricos. Se respetan el movimiento
reducido del sistema, `TickerMode` y el ciclo de vida de la aplicación.
Los fotogramas repintan solamente el personaje mediante `RepaintBoundary`.

El cambio de personaje libera las referencias anteriores y reinicia el saludo.
Los recursos que no pertenezcan al catálogo conservan una presentación estática.

## Integraciones

- Selección del compañero y bienvenida en onboarding: saludo.
- Tutorial: saludo, asentimientos por paso y celebración final.
- Inicio: retrato con reposo y parpadeo.
- Asistente: saludo al entrar/tocar y pensamiento durante `_isTyping`.
  Los avatares de mensajes anteriores quedan quietos.
- Crear/editar actividad: retrato de consejos, asentimiento al cambiar de tip.
- Éxito al crear/editar: celebración.
- Detalle de actividad: el compañero elegido sustituye la antigua iguana vectorial.
- Checklist: asentimiento al cambiar el progreso y celebración al completarlo.

## Prueba visual sin backend

```powershell
flutter run --no-pub -d emulator-5554 -t tool/preview_companion.dart
```

La vista permite elegir cualquiera de los tres compañeros, repetir gestos, cambiar fondo claro/oscuro y activar movimiento
reducido. No inicializa Supabase ni cambia el compañero guardado del usuario.
Usa el mismo identificador Android que Join. Para volver a la app completa:

```powershell
flutter run --no-pub -d emulator-5554
```

```powershell
flutter analyze --no-pub
flutter test --no-pub
flutter test --no-pub --dart-define=COMPANION_CAPTURE=true test/core/widgets/companion_view_test.dart
```

La última orden guarda capturas de los tres compañeros en reposo, saludo y parpadeo en
`build/companion-review/`. Las pruebas verifican el cierre de los ojos, los pies
fijos, movimiento reducido, pausa en segundo plano, rutas ocultas y sustitución
del personaje. La calidad y el rendimiento en teléfonos físicos aún deben
validarse antes de publicar; las comprobaciones visuales locales usan el emulador.

## Compilación de la app completa

```powershell
flutter build apk --debug --no-pub -t lib/main.dart
```

El APK de prueba queda en `build/app/outputs/flutter-apk/app-debug.apk`.
Este comando compila Join con su inicio de sesión, navegación y backend habituales;
la vista independiente de `tool/preview_companion.dart` no es el punto de entrada.
Se verificó que el APK contiene los tres personajes y sus tres texturas de párpados.
Suite completa: 154 pruebas aprobadas; análisis de Flutter sin incidencias.

El APK completo se instaló con `adb install -r` en el emulador Pixel 9a y se
verificó el arranque hasta inicio de sesión. No se verificaron las pantallas
autenticadas con datos reales en esta sesión. Posteriormente, por solicitud del usuario, se detuvieron los contenedores de full-led y se arrancó Supabase de Join conservando los volúmenes existentes de ambos proyectos. Se verificaron los servicios de Join, PostgreSQL disponible y Studio con HTTP 200 en localhost:54323; se volvió a abrir la app en el emulador. Para arrancar se utilizó `npx --yes supabase@2.115.0 start`: la versión 2.120.0 descargada carecía del paquete ejecutable para Windows.

## Recurso artístico y procedencia

- Originales: `assets/images/mascota/ELI.png`, `DRAGO.png` y `HALO.png`, sin modificar.
- Párpados: `assets/images/mascota/ELI-blink.png`, `DRAGO-blink.png` y `HALO-blink.png`.
- Herramienta: ImageGen integrada, con cada PNG original como referencia.
- No se añadieron dependencias ni servicios de animación externos.

Prompt utilizado para Eli:

> Use case: precise-object-edit. Edit target: the attached Eli PNG mascot. Create a blink animation keyframe: change ONLY the two eyes to gently fully CLOSED cyan eyelids with delicate curved dark eyelashes. Eyes closed peacefully mid-blink, not squeezed, with the same face and smile. Preserve the exact character identity, head outline, pose, waving arm, clothes, textures, lighting, colors, proportions and framing of the original. Keep the same 1024x1536 canvas and exact registration of every body part; no repositioning, no zoom, no added margins. Eye areas should remain in precisely their original locations. This image will be overlaid on the original in a Flutter animation. Preserve a genuinely transparent background, no solid background, no checkerboard, no text. Output one PNG.

La salida generada de Eli no conservó el fondo transparente solicitado. Se utiliza
exclusivamente dentro de máscaras locales de los ojos; el cuerpo y la silueta
siguen procediendo del PNG original transparente.


Prompts utilizados para los otros compañeros (una generación por recurso):

### DRAGO

> Use case: precise-object-edit. Edit target: the attached DRAGO PNG mascot. Create one blink animation keyframe: change ONLY both eyes to gently fully CLOSED mint green eyelids, with subtle curved dark lash lines. Peaceful natural blink, not squeezing or frowning. Preserve the exact original head outline, facial features, smile, clothes, hands, body pose, textures, shading, lighting and color. No redesign. Preserve the original 1268x1977 framing and aspect ratio, no zoom, crop, padding or repositioning: the closed eyelids must register exactly over the original eyes when the two images are overlaid. Preserve the genuinely transparent background. No scenery, text, checkerboard, watermark, glow, or extra objects. Output one PNG for use as an eyelid texture in a Flutter character animation.

### HALO

> Use case: precise-object-edit. Edit target: the attached HALO PNG mascot. Create one blink animation keyframe: change ONLY both eyes to gently fully CLOSED lavender purple eyelids, with subtle curved dark lash lines. Peaceful natural blink, not squeezing or frowning. Preserve the exact original head outline, facial features, smile, clothes, hands, body pose, textures, shading, lighting and color. No redesign. Preserve the original 1268x2167 framing and aspect ratio, no zoom, crop, padding or repositioning: the closed eyelids must register exactly over the original eyes when the two images are overlaid. Preserve the genuinely transparent background. No scenery, text, checkerboard, watermark, glow, or extra objects. Output one PNG for use as an eyelid texture in a Flutter character animation.

## Drago sin GIF — 24 de noviembre de 2026

Se retiró el GIF de Drago (`assets/images/mascota/animado/DRAGO`, ~18 MB): pesaba casi tanto como el resto de la app, no reaccionaba a `CompanionMotion` y hacía que Drago se moviera distinto de ELI y HALO. Los tres usan ahora el mismo sistema articulado (malla con párpados y gestos), con el arte original y `DRAGO-blink.png`; `CompanionMotion` y el modo de movimiento reducido funcionan igual para los tres.

La compilación debug incluye `/preview-drago` para revisarlo sin iniciar sesión, con botón para volver a Join. No está disponible en release. Los contenedores existentes de Join se arrancaron sin modificar los volúmenes.

Validación: seis pruebas de personajes aprobadas, análisis sin incidencias, APK debug compilado e instalado en emulator-5554. Vista previa comprobada visualmente con Drago mostrando un teléfono. Captura local: build/companion-review/drago-android.png.
