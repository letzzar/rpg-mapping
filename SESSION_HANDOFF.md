# SESSION_HANDOFF — RPG Mapping

## Última sesión: 2026-11-24 (6.ª) — F3 etapa 1: generador de edificios EDI G1 (`cartografo`)
Tests: **178/178, 22352 asserts, idénticos en escritorio y navegador**; las 20 seeds doradas MAZ/EST siguen iguales.

**Verificación del coordinador**: tests en escritorio y web (Chrome sin ventana), capturas reales 2D/3D/1ª persona de la taberna y del templo élfico hex (`render_views.gd`, carpeta `scratchpad/edi`) y `play_f2.gd` sin fallos. Retoque de vistas: el suelo exterior del edificio (zona `outside` y su entrada/salida) se pinta en otro tono (`MapMeshBuilder.COL_OUTDOOR`, `outdoor_mask()`) y en 1ª persona no lleva techo; en MAZ no cambia nada (sin zona `outside`). Detalle pendiente: en la cenital 3D los rótulos de objetos vecinos se solapan ("Mesa redonda" ×2).

### Hecho
- **EDI G1** (`core/gen/edi/edi_generator_g1.gd`, `edi_data.gd`; PROYECTO §6.4, ADR 026): espina (hub + rebanadas) o BSP por pesos con 12 intentos y hub de reserva; puertas con conectividad por construcción; ventanas; escaleras en la misma casilla; plantas altas recortables; sótano; mobiliario con `EstFurnisherG1` y semilla `hash64(semilla, "EST", nivel×256+orden)` (`EdiGeneratorG1.room_seed`).
- **Esquema EDI G1** en `ParamSchemaRegistry.edi_g1()`: `building_type, grid, style, floors (0=auto), cellar, size, clutter`. Registrado en `GeneratorRegistry`.
- **Datos**: `data/buildings/edi_building_types.json` (+ esquema) con 7 tipos (taberna, casa, herrería, templo, tienda, posada, cuartel); bloque `building` opcional en `data/styles/*.json` (`footprint_pct`, `window_pct`; EST no lo lee). Tipos de estancia EST nuevos al final (dentro de capacity): `hall, living, shop, barracks, armory, cell, guardroom` (también en el enumerado `room_type` de EST G1).
- **`MapEdge.KIND_WINDOW` = 5**: bloquea paso y conectividad, no visión. Vista 2D (muro + cristal), 3D (muro con hueco 0,9–2,0 m; las caras macizas no se dibujan donde ya hay arista: no cambia nada en MAZ/EST). `MapRoom.KIND_OUTSIDE`.
- **UI**: escala "Edificio" (`UI_SCALE_EDI`); al generar se abre el nivel con la entrada (con sótano, el nivel 0 es el sótano); la ficha nueva no atraviesa ventanas.
- Tests nuevos `tests/unit/test_edi_generator.gd` (datos, código ida y vuelta, 7 tipos × 3 rejillas × estilos/plantas/sótano/tamaños, adyacencias, escaleras, ventanas en el modelo y en vistas, mobiliario por semilla hija, hub de reserva forzado, pantalla principal, estadísticas y ASCII). Prueba de estrés aparte (no versionada): 630 edificios, 0 fallos, ~97 ms/edificio.

### Aprobado (2026-11-25)
- **Víctor aprobó** el esquema EDI G1, los 7 tipos de edificio, los tipos de estancia nuevos, el bloque `building` de los estilos y `KIND_WINDOW`. **EDI G1 queda congelado** con 8 seeds doradas grabadas (28 en total: 11 MAZ, 9 EST, 8 EDI). Cualquier cambio que altere esos hashes exige EDI G2 (y mover G1 a `legacy/`). PROYECTO §6.4-6.6 y ADR 022/023/026 actualizados (también decían "pendiente" para MAZ y EST, ya aprobados en F1).

### Pendiente de Víctor
- Decidir cómo cumplir el criterio de F3 "estancia aislada = dentro de la aldea" (una estancia de EDI tiene la forma de la partición, no los tamaños de EST): EST G2 con forma/puertas dadas o un código de estancia de edificio.

### Códigos para probar en la app
`RPGM1-DND5-EDI-G1-0-H8DJRFAE-3` (taberna) · `RPGM1-DND5-EDI-G1-A01-KCP3TKJZ-2` (casa con sótano) · `RPGM1-PF2E-EDI-G1-52-NGYMWQV0-K` (herrería enana, hex plana) · `RPGM1-DND5-EDI-G1-AA3-QN75YR3H-A` (templo élfico con cripta, hex punta) · `RPGM1-DND5-EDI-G1-1E04-SSFP0WC2-N` (tienda de 3 plantas) · `RPGM1-PF2E-EDI-G1-F015-VXG730MK-E` (posada, hex plana) · `RPGM1-DND5-EDI-G1-A46-W1RR54X4-6` (cuartel enano con celdas) · `RPGM1-PF2E-EDI-G1-2820-Y619795N-E` (taberna grande de 1 planta con sótano, hex punta).

### Limitaciones conocidas
- Huellas solo rectangulares (L o patios: campo nuevo al final más adelante). Plantas altas solo se recortan por un extremo del eje largo.
- En hex, las "rectas" de la partición son rectángulos en coordenadas offset (bordes dentados, como en EST).
- El selector de nivel dice "Nivel n" (no "Sótano"/"Planta baja"). El 3D solo muestra la planta actual; fuera de la planta baja el exterior es vacío.
- Con datos muy apretados se descartan estancias del final de la lista (6 de 480 en las estadísticas: dormitorios de la posada pequeña).

## Sesión anterior: 2026-11-24 (5.ª) — F2: vista 3D, 1ª persona, visión y niebla
**Fase actual: F2 implementada; criterios cumplidos en tests** (cambio de vista < 500 ms medido en tests y en la app real: 2–13 ms; niebla idéntica en 2D y 3D por construcción y comprobada en test). **Falta la prueba interactiva de Víctor** (la pantalla se bloqueó a mitad de sesión: las vistas se revisaron con capturas generadas por Godot, no con el ratón).

### Hecho
- **Etapa 1 – modelo** (commit propio): `core/model/visibility.gd` (línea de visión entera y simétrica, aristas que tapan, regla de esquina, mapa de luz con sombra, visibles con alcance y visión en la oscuridad), `core/model/party_vision.gd` (lo que ve el grupo: fichas player/ally, luces de objetos y antorcha opcional = luz de `torch_sconce` del catálogo), `ExploreCommand` (niebla = sesión, con delta) y `CompositeCommand` + `CommandStack.execute_attached()` (explorar se deshace con el movimiento que lo provocó). ADR 024.
- **Etapa 2 – vistas**: `views/view3d/map_mesh_builder.gd` + `map_vertex_color.gdshader` (geometría generada sin assets, color por vértice sRGB con niebla y luz horneadas, oscurecimiento por distancia en 1ª persona; igual en WebGL) y `views/view3d/map_view_3d.gd` (cenital orbital 0–60°, perspectiva/ortográfica con O; 1ª persona en la ficha seleccionada, W/S avanzar/retroceder con `MoveTokenCommand`, A/D girar, botón derecho mirar; clic en puertas y arrastre de fichas con rayo al suelo). Vista 2D con niebla (velo por casilla, fichas ajenas ocultas fuera de la vista). ADR 025.
- **UI**: selector Vista 2D / Vista 3D / 1ª persona; "Ve: DM / jugadores"; casillas "Ambiente iluminado" y "Antorchas". Tras mover, abrir puerta o añadir ficha, el grupo explora (mismo paso de deshacer).
- `tests/render/render_views.gd`: captura 2D/3D/1ª persona con y sin niebla a PNG (necesita ventana).
- Tests: **160/160, 21085 asserts, idénticos en escritorio y navegador** (nuevos `test_visibility.gd` y `test_view3d.gd`). Los tests web se pasaron con Chrome sin ventana (`--headless=new --remote-debugging-port`, leyendo el título por `/json`) porque el panel del navegador estaba oculto.

### Pruebas de F2 en la app real (misma sesión, después)
Con la pantalla bloqueada no había capturas del sistema, así que se escribió `tests/render/play_f2.gd`: abre la app con ventana real, inyecta ratón y teclado en la ventana raíz (pasan por toda la interfaz, como los del sistema) y guarda una captura por paso. **31/31 comprobaciones OK** tras estos arreglos:
- **1ª persona no podía abrir puertas** → Espacio o E abre/cierra la puerta de delante (test `test_first_person_opens_door_ahead`).
- **Tras mirar con el ratón, W/Espacio iban en la dirección anterior** → avanzar, girar y abrir usan la dirección de la rejilla más cercana a donde mira la cámara.
- El contenedor 3D ya no toma el foco de teclado (un SubViewportContainer enfocado puede quedarse eventos) y las teclas de cámara/1ª persona se las pasa `main` desde `_unhandled_key_input`; un clic en la vista 3D quita el foco a la caja del código (test de regresión `test_toolbar_still_works_after_using_3d_and_keys_reach_fp`).
- Lecciones para inyectar eventos: separar pulsar y soltar por un fotograma, y mandar siempre el "soltar" de la rueda (si no, Godot cree que hay un botón apretado y la vista 3D se queda todos los clics).
- Tests: **162/162, 21091 asserts, idénticos en escritorio y navegador**.

```powershell
& "$env:LOCALAPPDATA\Programs\Godot\Godot_v4.7.2-stable_win64_console.exe" --path project -s res://tests/render/play_f2.gd -- <carpeta>
```

### Siguiente paso
1. Si Víctor quiere, probarlo él a mano (Vista 3D, 1ª persona con W/A/S/D y Espacio, "Ve: jugadores", antorchas, deshacer).
2. Pendiente de F2 si se quiere: plantas superiores/inferiores visibles en 3D (ahora solo la actual, "corte de techo" implícito), visión en la oscuridad por ficha (llegará con los personajes de F5; hoy `darkvision_cells` = 0), FOV configurable en la UI (hoy constante 75°), modelos CC0 en lugar de cajas.
3. Después: **F3 – Edificio y asentamiento**.

### Notas
- La pantalla bloqueada impide capturas con `computer-use` (error "empty capture"); `SetForegroundWindow` devuelve False. Usar `render_views.gd` para revisar vistas.

## Sesión anterior: 2026-11-24 (4.ª) — pruebas de ejecución con uso del ordenador
Se pasó el guion de abajo en la app real (Claude Code desktop + `computer-use`) y se arreglaron los fallos encontrados.

**Resultado del guion** (OK salvo lo indicado; todo lo marcado "arreglado" tiene test):
1. Arranque: OK. *Arreglado*: "Métrico (5 ft = 1" cortado → la coma de "1,5 m" no iba entre comillas en `strings.csv` (columna partida).
2. Códigos conocidos (cuadrícula, hex plana, hex punta 3 niveles): OK; sistema, escala y rejilla se ajustan solos.
3. Errores de código: errata → "El carácter de control no coincide…" traducido; vacío → error de formato; minúsculas/espacios aceptados.
4. Aleatorias MAZ/EST × 3 rejillas: OK; regenerar desde la caja da el mismo mapa.
5. Niveles: OK. *Arreglado*: la flecha de escalera era un "▼" de la fuente diminuto y pegado a los peldaños → ahora es un triángulo dibujado.
6. Zoom/desplazamiento: *arreglado* (ver 7); el zoom de rueda ignoraba `InputEventMouseButton.factor` (Windows agrupa pasos: 20 clics ≈ ×1,3) → ahora `ZOOM_STEP^factor`. El desplazamiento con botón central no se pudo probar (la herramienta no arrastra con el central).
7. Fichas: **fallo grave arreglado** — ningún clic/arrastre/rueda llegaba a la vista: `_map_area` tenía `MOUSE_FILTER_PASS`, el evento subía hasta el `Control` raíz (STOP) y no llegaba a `_unhandled_input`. Ahora `_map_area` es STOP y reenvía `gui_input` a `MapView2D.process_input()`. Tras el arreglo: ruta + coste, "Ficha movida (4,5 m)", "Sin ruta" con puertas cerradas, rodea muebles. *Mejoras*: la ficha nueva aparece junto a la entrada (zona `entrance`/`exit`/escalera, BFS sin cruzar muros) y la barra dice "Ficha P1 añadida junto a la entrada"; soltar sin ruta dice "Sin ruta: la ficha no se mueve (…)" (antes la barra no cambiaba).
8. Puertas: OK (abrir/cerrar, la ruta pasa al abrir). Nota: un punto concreto de la pantalla no entregaba clics a Godot (ventana invisible de otro programa del PC); no es de la app.
9. Deshacer/rehacer: botones, Ctrl+Z/Ctrl+Y/Ctrl+Mayús+Z y tooltip ("Cambiar puerta"): OK.
10. Regla: no se puede arrastrar con botón derecho desde la herramienta → cubierto con test GUT (6 casillas = 9 m / 9,14 m / 30 ft).
11. Estancias (taberna, templo élfico hex): OK. *Arreglado*: nombres cortados a 10 letras y al ancho de una casilla ("Mesa re", "Chimene") → nombre completo centrado en la huella, letra reducida y en dos líneas si hace falta.
12. Exportar PNG: OK (coincide con la vista). *Arreglado*: el diálogo de Godot salía en inglés y en la carpeta del proyecto → diálogo nativo del sistema (en español) que abre en Imágenes.
13. Rendimiento: fluido con los mapas probados (no se construyó un "huge").
14. Consola/log (`%APPDATA%\Godot\app_userdata\RPG Mapping\logs\godot.log`): sin errores ni avisos.
- Rejilla: *arreglado* — al alejar desaparecían líneas verticales u horizontales (ancho 1.0 en coordenadas locales < 1 px) → ancho -1 (1 px de pantalla siempre).
- Tests: **146/146, 20076 asserts, idénticos en escritorio y navegador**. Nuevo `tests/unit/test_main_interaction.gd`: simula ratón real (`push_input`) sobre `ui/main.tscn` en un `SubViewport` (arrastre, rueda con factor, clic en todas las puertas con desplazamientos, regla, ficha en la entrada, mensaje sin ruta, textos no partidos por comas).

**Notas para la próxima sesión de pruebas con el ordenador**: la ventana es `Godot_v4.7.2-stable_win64.exe` (pedir acceso con la ruta completa); `open_application` abre el gestor de proyectos (no usarlo): traer la ventana al frente con `SetForegroundWindow` desde PowerShell. Lanzar con el exe sin `_console`; los `print` van a `godot.log`.

---

## Guion de pruebas de ejecución (2026-11-24, ya pasado; conservar para repetirlo)
Víctor cerró la sesión de terminal para reabrir en **Claude Code desktop** con **uso del ordenador** (skill `computer-use`). Al abrir, **hacer las pruebas del tirón, sin preguntar entre pasos**; al final, un único informe con capturas de los fallos y la lista de arreglos propuestos.

**Preparación**
1. Leer este fichero. Cargar el skill `computer-use` (y comprobar que hay herramientas de captura/clic). Si no las hay, decírselo a Víctor y usar el plan B (ver abajo).
2. `pwsh tools/run_tests.ps1` → debe dar **139/139** (si no, parar y arreglar antes de probar la UI).
3. Lanzar la app con ventana: `& "$env:LOCALAPPDATA\Programs\Godot\Godot_v4.7.2-stable_win64_console.exe" --path project` (en segundo plano; la consola muestra errores de script: revisarla al final).

**Guion de pruebas** (anotar por cada punto: OK / fallo + captura):
1. **Arranque**: ventana con barra superior (código, Generar, escala, Nueva aleatoria, sistema, rejilla, unidades, nivel, Añadir ficha, Deshacer, Rehacer, Ajustar, Exportar PNG) y texto de ayuda abajo. Textos en español, nada cortado ni solapado; probar a redimensionar la ventana.
2. **Código conocido**: pegar `RPGM1-DND5-MAZ-G1-0-HWX23H6N-W` → Generar → mapa centrado; comparar con `tests/render/render_samples.gd` si hay dudas. Probar también `RPGM1-PF2E-MAZ-G1-80-PK2XDSZR-5` (hex plana) y `RPGM1-DND5-MAZ-G1-WKA0G0-W7HE7S75-0` (hex punta, 3 niveles): el selector de sistema, escala y rejilla debe ajustarse solo.
3. **Errores de código**: un código con una letra cambiada → mensaje "código mal escrito" (SEED_ERR_CHECK traducido, no la clave); código vacío; minúsculas y espacios (deben aceptarse).
4. **Aleatorias**: Nueva aleatoria con cada combinación de escala (Mazmorra/Estancia) × rejilla (3); el código aparece en la caja y regenerarlo da el mismo mapa.
5. **Niveles**: con el mapa de 3 niveles, cambiar de nivel; las escaleras se ven con flecha arriba/abajo.
6. **Zoom y desplazamiento**: rueda (zoom centrado en el puntero), botón central (desplazar), Ajustar.
7. **Fichas**: Añadir ficha (varias) → aparecen en casillas libres; arrastrar una → línea de ruta + coste en la unidad activa; soltar → se mueve y la barra de estado dice "Ficha movida (…)". Arrastrar más allá de 30 ft (5e) → ruta en rojo y "(supera la velocidad)", pero se mueve igual. Arrastrar a roca o tras puerta cerrada → "Sin ruta" y no se mueve.
8. **Puertas**: clic en una puerta cerrada → se abre (hoja girada); ahora la ruta pasa por ella; volver a cerrar. Puerta secreta (azul, vista DM) igual.
9. **Deshacer/rehacer**: botones y Ctrl+Z / Ctrl+Y / Ctrl+Mayús+Z; los botones se desactivan cuando no hay nada; el tooltip dice qué se deshace.
10. **Regla**: arrastrar con botón derecho → línea y distancia; cambiar unidades (métrico convención 5 ft = 1,5 m, métrico exacto, imperial) y comprobar valores (p. ej. 6 casillas rectas = 30 ft = 9 m conv. / 9,14 m exacto). En PF2e, diagonales alternas 5/10.
11. **Estancias**: generar `RPGM1-DND5-EST-G1-0-H8DJRFAE-M` (taberna) y `RPGM1-DND5-EST-G1-223-QN75YR3H-Y` (templo élfico, hex): nombres de objetos legibles, luces, puerta funciona, fichas no atraviesan muebles que bloquean.
12. **Exportar PNG**: diálogo de guardar → guardar en el scratchpad → abrir el PNG y comprobar que coincide con la vista (sin fichas de jugador ocultas, a 100 px/casilla).
13. **Rendimiento**: mapa grande (aleatoria de mazmorra varias veces; o código con tamaño huge si se construye) → zoom/arrastre fluidos.
14. **Consola**: revisar la salida de Godot por `SCRIPT ERROR`, `ERROR` o avisos.

**Al terminar**: arreglar lo que sea claro (con tests si se puede: plan de convertir interacciones en pruebas GUT que simulan eventos de ratón sobre `ui/main.tscn`), commit + `git push` + `git push nas main`, informe a Víctor, y preguntar si se pasa a **F2**.

**Plan B (sin uso del ordenador)**: exportar el preset "Web" (`--export-release "Web" ../build/web/index.html`), servir `build/web` con `python -m http.server 8766 --bind 127.0.0.1` y hacer el mismo guion en Chrome con `claude-in-chrome` (clics/arrastres sobre el canvas y capturas). El PNG en web se descarga en lugar de abrir diálogo.

## Sesión anterior: 2026-11-24 (3.ª)
**Fase actual:** **F1 – Mazmorra y estancia 2D: criterios de aceptación cumplidos** (20 seeds doradas estables en escritorio y web; movimiento en 5e, PF2e y bandas en las tres rejillas). Falta la prueba manual de Víctor. Siguiente: F2.

### Hecho en esta sesión
- **F0 cerrada**: licencias (Daggerheart fuera, ADR 011; aviso ORC en `pf2e.json` y `NOTICE.md`), código de semilla final (PARAMS posicional, SEED variable, control GF(32) Crockford; ADR 009), exportaciones de las 4 plataformas + preset **Web Tests** (GUT en el navegador), repo público https://github.com/letzzar/rpg-mapping con CI y espejo en el NAS.
- **F1 etapa 1** (`cartografo`): `core/grid/` (cuadrada, hex_flat odd-q, hex_pointy odd-r; ADR 017), `core/model/` (`MapDocument` y compañía; muros híbridos casilla+arista, ADR 018; JSON canónico + SHA-256, ADR 019), `MovementCost` por tipo de paso con `find_route` exacto (ADR 020), seeds doradas con modo grabación (ADR 021).
- **F1 etapa 2** (`cartografo`): generador **MAZ G1** (`core/gen/maz/`, ADR 022, PROYECTO §6.6): construida/cueva/mixta, salidas, niveles con escaleras, trampas, puertas secretas, tamaños y estilos; accesibilidad garantizada por construcción (`core/model/connectivity.gd`). **Esquema MAZ G1 aprobado por Víctor y congelado**: 11 seeds doradas grabadas en `tests/golden/golden_seeds.txt` (3 rejillas, 3 tipos, 2 sistemas).
- **F1 etapa 4** (coordinador): `core/model/commands/` (`MapCommand`, `CommandStack` con deshacer/rehacer/fusión, `MoveTokenCommand`, `SetEdgeCommand`, `AddTokenCommand`; todos dejan su `MapDelta`), `views/view2d/map_view_2d.gd` (terreno, muros, puertas, escaleras, trampas, objetos, fichas con color + marca por bando; arrastre de ficha con ruta y coste y aviso si supera la velocidad; clic en puerta abre/cierra; regla con botón derecho, bandas si el perfil las usa; zoom y desplazamiento), `views/view2d/png_exporter.gd` (PNG a px/casilla; en web se descarga), `ui/main.tscn` (escena principal: código, generar, aleatoria, sistema, rejilla, unidades, nivel, añadir ficha, deshacer/rehacer, ajustar, exportar). `tests/render/render_samples.gd`: renderiza mapas a PNG para revisarlos a ojo.
- **F1 etapa 3** (`cartografo`): generador **EST G1** (`core/gen/est/`: `EstGeneratorG1`, `EstFurnisherG1.furnish()` reutilizable por EDI, `EstData`; ADR 023, PROYECTO §6.5) + catálogo `data/objects/core.json` (32 objetos, `core/model/object_catalog.gd`), tipos `data/rooms/est_room_types.json`, estilos `data/styles/{human,dwarf,elf}.json`, 3 esquemas nuevos, `MapObject.material`, claves i18n `OBJ_*`, `ROOM_KIND_<tipo>` y `STYLE_*`. **Esquema EST G1, catálogo, tipos y estilos aprobados por Víctor y congelados**: 9 seeds doradas grabadas (8 tipos, 3 rejillas, 3 estilos, 2 formas). La pantalla principal permite elegir escala (mazmorra o estancia). Comprobación de claves i18n en tests sobre la traducción compilada (el CSV fuente no viaja en la exportación web).
- Decisiones de Víctor en F1: muros híbridos; **cualquier puerta cerrada bloquea la ruta**; diagonal junto a esquina permitida si un lado está libre; huella hex 1/3/7/19 (en datos del perfil, `hex_cells`); agua profunda = difícil, foso = bloquea; esquema MAZ G1 aprobado (sin `wfc_tiles`, se añadirá al final); cuevas sin puertas interiores, 25 % vanos y 12 % puertas con llave.
- Tests: **139/139, 19923 asserts, idénticos en escritorio y en navegador** (incluidas las 20 seeds doradas).

### Siguiente paso
1. ~~Prueba de la app~~ (hecha en la 4.ª sesión, ver arriba). Ajustes pendientes de la vista si Víctor los quiere: iconos de objetos, selector de tamaño/bando de ficha.
2. **F2 – Vista 3D y 1ª persona** (§7, §16): renderizado 3D cenital y en primera persona del mismo `MapDocument` (muros en aristas → módulos de pared, ADR 018), línea de visión y luces en el modelo; criterio: cambio de vista < 500 ms y niebla coherente entre vistas. Assets CC0 a registrar en `assets/LICENSES.md`.

### Pendiente / riesgos
- El `cartografo` no puede ejecutar tests (no tiene PowerShell en esta sesión; se añadió a su definición y debería tenerlo en la próxima). Mientras tanto, los ejecuta el coordinador.
- `find_route` no considera otras fichas y usa la casilla de anclaje de criaturas grandes.
- Uso nominativo de "Pathfinder" (ORC no cubre marcas); con aviso de no afiliación.
- Pantalla de créditos (futura) debe mostrar `content.attribution` de cada perfil.
- macOS: build sin firmar ni notarizar. CI: `actions/checkout@v4` usa Node 20 (deprecado).

### Comandos para retomar
```powershell
pwsh tools/run_tests.ps1        # importa + tests; debe dar 178/178
$g = "$env:LOCALAPPDATA\Programs\Godot\Godot_v4.7.2-stable_win64_console.exe"
& $g --path project             # ejecutar la app
& $g --path project -e          # abrir editor
# Renderizar mapas de ejemplo a PNG (necesita ventana)
& $g --path project -s res://tests/render/render_samples.gd -- <carpeta> [códigos...]
# Grabar seeds doradas nuevas (solo rellena líneas sin hash)
$env:RPGM_GOLDEN_RECORD = "1"; pwsh tools/run_tests.ps1 -Dir res://tests/golden; Remove-Item Env:RPGM_GOLDEN_RECORD
# Tests en web: exportar, servir y abrir http://127.0.0.1:8765 (el título muestra WEB_TESTS_RESULT)
& $g --headless --path project --export-release "Web Tests" ../build/web-tests/index.html
python -m http.server 8765 --bind 127.0.0.1 --directory build/web-tests
# Tras cada git push: git push nas main
```

### Notas
- Git Bash falla al hacer fork en esta máquina: trabajar con PowerShell.
- Tras crear un script con `class_name` nuevo hay que reimportar (`--import`); `run_tests` ya lo hace.
- Avisos de tipado como error: `int(Variant)` o pasar un Variant de diccionario a `assert_eq` rompen la compilación; asignar antes a variable tipada.
- Godot no admite el carácter NUL dentro de `String`.
- Godot portable 4.7.2 en `%LOCALAPPDATA%\Programs\Godot\` (fuera del repo, no está en el PATH).
