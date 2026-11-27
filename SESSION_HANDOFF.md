# SESSION_HANDOFF — RPG Mapping

## Última sesión: 2026-11-27 (14.ª, décima parte) — Docker y distribuible de Windows
Tests: **353/353 en escritorio y en el navegador** (1 nuevo: dirección pública en `test_net_protocol.gd`).

### Hecho (ADR 046)
- **Imagen Docker** (`docker/`: Dockerfile, Caddyfile, docker-compose.yml, README): Caddy sirve el cliente web y reenvía `/ws` a la app del DM. Construir con `pwsh tools/build_docker.ps1`. Probado de verdad: página y `.wasm` por HTTPS (certificado interno, por nombre e IP), certificado montado (sirve exactamente ese), y partida real: Chrome abrió el enlace del contenedor y el DM vio al jugador conectado a través del proxy.
- **Dirección pública** en "Partida en red" (`NetHostPanel`): si se rellena (p. ej. `https://nas.local:8443`), enlaces y QR la usan; se recuerda.
- **Distribuible** (`pwsh tools/build_dist.ps1`) en `build/dist/`:
  - `RPG Mapping/` y `RPGMapping-<ver>-windows.zip`: portable, doble clic en `RPGMapping.exe` (pck dentro, `web/` al lado, LEEME, licencias de terceros).
  - `RPGMapping-<ver>-windows-instalador.exe` (Inno Setup 6, ya instalado en este equipo): por usuario, sin administrador, menú Inicio + escritorio opcional, desinstalador que conserva mapas y ajustes.
  - Probado: instalación silenciosa (ficheros, accesos, entrada de desinstalar), la app instalada arranca sin errores, su paquete abre la partida en red y sirve la página y el `.wasm` desde la `web/` de junto al ejecutable; desinstalación limpia.
- IExpress se probó y se descartó (extraía el paquete pero no lanzaba el script).

### Siguiente paso
1. Que Víctor pruebe el instalador con doble clic y la imagen en el NAS (falta probarla en el NAS real; aquí se probó en Docker Desktop).
2. SmartScreen avisará la primera vez (programa sin firmar). Linux/macOS: sus exportaciones existen, pero sin empaquetar con `web/`.
## Última sesión: 2026-11-27 (14.ª, novena parte) — Figuras con esqueleto (KayKit)
Tests: **352/352 en escritorio y en inglés** (2 nuevos en `test_rigged_figures.gd`).

### Hecho (ADR 045)
- Víctor aprobó los esquemas de MUN/REG y autorizó descargar los packs CC0 de KayKit (Adventurers, Skeletons, Character Animations) desde itch.io: licencia CC0 comprobada, registrada en `assets/LICENSES.md`; zips en `assets/models/kaykit/` (fuera de git), modelos usados en `project/models/kaykit/`.
- 10 figuras animadas (modelos tipo "… (modelo animado)": caballero, bárbaro, mago, explorador, pícaro, pícaro encapuchado y 4 esqueletos) con reposo y andar (`RiggedFigure`), en la vista 3D y en el diseñador; luz solo para ellas.
- Al descargar, Chrome dejó los tres ficheros como `.tmp` en Descargas (completos; se copiaron con su nombre). Pueden borrarse de Descargas.

### Siguiente paso
1. Que Víctor pruebe las figuras animadas y el modo proyectado; imagen Docker al final.

## Sesión anterior: 2026-11-27 (14.ª, octava parte) — F5 cerrado y F6 (mundo, región, impresión)
Tests: **350/350 en escritorio, en inglés y en el navegador** (el de rendimiento del mundo 2048×1024 también pasa en web: < 10 s). 69 seeds doradas (51 de antes sin cambios + 18 de MUN/REG).

### Hecho
- **F5 (ADR 041 y 043)**: modelos de los 32 muebles (`data/models/objects.json`), texturas procedurales en el shader (losas, piedra, madera, hierba, agua), 16 enemigos tipo con 4 cuerpos nuevos, fichas que andan por la ruta en 3D y figuras que respiran. Solo queda, si Víctor lo autoriza, descargar modelos CC0 con esqueleto.
- **Impresión (ADR 042)**: "Imprimir (PDF)", A4 o Carta, casilla de 1 pulgada o 25 mm, orientación automática, marcas y etiqueta por hoja, roca en gris claro. PDF propio (`PdfWriter`), comprobado con pypdf.
- **F6 (ADR 044)**: generadores de `cartografo` (nota abajo) y su vista: el mundo se dibuja como imagen (un píxel por casilla: bioma, relieve, ríos, caminos, fronteras), la región por hexágonos con ríos, caminos, montañas y bosques; marcadores de asentamientos y lugares que se ven a cualquier zoom; clic = qué hay en la casilla; regla en km/mi; doble clic en el mundo = su región; en la región = asentamiento o mazmorra; lugares sin plano solo se describen. El mundo no tiene 3D ni niebla (demasiadas casillas).
- Rendimiento: abrir el mundo grande pasó de 14,5 s a unos 5 s (3,7 generar + 0,6 imagen + 0,8 primer dibujo): el panel del editor comprobaba la conectividad de 2 millones de casillas aunque estuviera cerrado.

### Siguiente paso
1. Esquemas de MUN G1, REG G1 y REG G2 **aprobados por Víctor el 2026-11-27 y congelados** (sus seeds doradas ya no se regraban: un cambio exige GEN nuevo).
2. Probar el modo proyectado con proyector; imagen Docker al final.

### Limitaciones conocidas (F6)
- En el mundo, ríos, reinos y caminos no cruzan el meridiano 0; sin puertos ni rutas marítimas. Sin 3D del mundo (sí de la región).
- Los encuentros por bioma (`RegEncounters`) tienen datos y textos pero aún no botón en la interfaz.
- Las regiones no tienen niebla ni guardado propio salvo en el recorrido (se regeneran al vuelo).

## Nota de `cartografo` (2026-11-26): F6, MUN G1 y REG G1/G2
- **Generadores nuevos** (esquemas **propuestos, pendientes de aprobar por Víctor**; detalle en PROYECTO §6.1 y §6.2): `MUN G1` (mundo = planeta entero, 4 resoluciones, defecto 2048×1024 = 12 mi/casilla), `REG G1` (hexcrawl independiente) y `REG G2` (región de un mundo; campos 0-8 = los de MUN G1, + rx, ry, grid, villages, pois).
- **Modelo**: capas opcionales `MapLevel.biome/elevation/features` (`Biome`, `GeoLayers`) y `MapChild.label`, que solo se serializan si no están vacías: las 51 seeds doradas anteriores no cambian. Ruido propio en `core/noise/lattice_noise.gd`. `MapNavigator.enter` sitúa al grupo en la zona `entrance` si la casilla de llegada no es transitable (puntos de interés con MAZ). `Units.scale_cell_mm()`.
- **Tiempos (escritorio)**: MUN large 2048×1024 ≈ 3,5 s (criterio F6 < 10 s), su `content_hash()` ≈ 2 s; small 0,3 s; REG G1 32×24 ≈ 35 ms, 64×64 ≈ 0,3 s; REG G2 ≈ 30 ms con el mundo en caché. Web: sin medir.
- **Seeds doradas nuevas (18)**: MUN `RPGM1-DND5-MUN-G1-5-H8ZJ3HXN-Z`, `RPGM1-DND5-MUN-G1-3Y2X-KG6M9RFJ-2`, `RPGM1-DND5-MUN-G1-QX06TD-M6SC7N75-J`, `RPGM1-DND5-MUN-G1-6-PZGN2RXA-G`, `RPGM1-DND5-MUN-G1-65B3ZGY-R3ZYW4HM-Q`, `RPGM1-DND5-MUN-G1-0-T5FABSVQ-B` (large), `RPGM1-PF2E-MUN-G1-JVX-H00128HK-X`; REG G1 `RPGM1-DND5-REG-G1-0-HW0DBRD2-1`, `…-77KS-KAYDXW0J-V`, `…-R04FM2-M2GA1850-K`, `…-430GVC-P6RV3CDH-9`, `…-56MXY-RB1C5GP2-0`; REG G2 `RPGM1-DND5-REG-G2-3HK8V5E005-H8ZJ3HXN-B` y 5 más (ver golden_seeds.txt). Mientras el esquema no esté aprobado se pueden regrabar; al aprobarlo quedan congeladas.
- Pendiente: vistas (colores por bioma, ríos, caminos, fronteras), textos i18n (BIOME_*, POI_*, ENC_*, ROOM_KIND_KINGDOM, SETTLEMENT_*), botón de "entrar en la región" (`RegGeneratorG2.region_child`), medir en web, ADR en §17.

## Última sesión: 2026-11-26 (14.ª, séptima parte) — Editor de estancias E4
Tests: **326/326 en escritorio, en inglés y en el navegador** (3 nuevos en `test_room_override.gd`).

### Hecho (ADR 040)
- Una estancia de la biblioteca puede ser el **interior** de un edificio de una aldea o de una estancia de edificio: "Usar aquí la estancia elegida" (y "Volver a la generada") en el panel del editor, estando dentro. `MapDocument.child_overrides` + `SetChildOverrideCommand` en el padre; `MapNavigator` la abre y el grupo entra y sale por su puerta.
- **Guardar mapa guarda el recorrido entero** (raíz + edificios y estancias visitados con sus cambios y sustituciones + en cuál se estaba); "Abrir mapa" vuelve al mismo sitio. Los ficheros de antes (sin recorrido) se siguen abriendo.
- En red no hace falta nada: los jugadores reciben el mapa en que está el DM.

### Siguiente paso
1. El editor de estancias (E1–E4) queda completo. Pendiente de Víctor: probar el modo proyectado con el proyector, y decidir qué sigue (resto de F5: modelos CC0 y animaciones, que necesitan permiso de descarga; F6 mundo y región; imagen Docker al final).

### Limitaciones conocidas (E4)
- Sustituir no se puede deshacer con "Deshacer" una vez dentro (cruzar de mapa vacía el historial, como siempre): se vuelve con "Volver a la generada".
- En una mazmorra (MAZ) no hay hijos: no se puede meter una estancia propia.

## Sesión anterior: 2026-11-26 (14.ª, sexta parte) — Modo proyectado
Tests: **323/323 en escritorio, en inglés y en el navegador** (5 nuevos en `test_projector.gd`; el de la pantalla principal queda pendiente en web: allí no hay proyector). Probado con capturas: sala revelada, puerta abierta que revela el pasillo, rectángulo del proyector en la pantalla del DM y cuadrado de calibración.

### Hecho (ADR 039)
- Botón "Proyector" (DM, escritorio) con `ProjectorPanel`: encender/apagar en la pantalla elegida, píxeles por casilla y "Calibrar con una regla" (4×4 casillas = 10 cm), giro, flechas y centrar, mostrar fichas (no por defecto).
- `ProjectorWindow`: ventana del sistema a pantalla completa, vista de jugadores a escala, fondo negro; no se mueve sola.
- Descubrir: al abrir una puerta (proyector encendido) se revelan los dos lados; "Revelar zona" (clic), pincel de revelar y de ocultar (`ConcealCommand` + `FogReveal`); o "Añadir ficha del grupo" y moverla (visión normal).
- La vista 2D ahora tiene fondo, velo de lo explorado y color de rejilla configurables, y la señal `door_toggled`.
- Decisión de Víctor: sin QR para estancias (viajan en los guardados); QR solo para que entren los jugadores.

### Siguiente paso
1. **Que Víctor lo pruebe con su proyector**: calibrar con una regla y comprobar que las miniaturas caben en las casillas; ver si revelar al abrir puertas descubre demasiado en mazmorras con pasillos largos (el pasillo es una "zona" entera).
2. E4 (estancias propias dentro de edificios y aldeas, en el guardado y en red).

### Limitaciones conocidas (modo proyectado)
- Solo 2D y escritorio; una sola ventana de proyector.
- No hay que mover el mapa del DM para nada: el proyector va aparte; pero cambiar de nivel en el DM cambia también el del proyector.

## Sesión anterior: 2026-11-26 (14.ª, quinta parte) — Editor de estancias E3: id corto y código para compartir
Tests: **318/318 en escritorio, en inglés y en el navegador** (nuevos: `test_room_code.gd` ×16, de `cartografo`, y `test_room_library.gd` ×4). Víctor aprobó el esquema de EST G3 (congelado).

### Hecho (ADR 038, formatos en PROYECTO §5.5)
- `RoomCode` (de `cartografo`): id corto `RPGU1-<12 car.>-<c>` (60 bits del SHA-256 del contenido) y código para compartir `RPGS1-<carga>-<c>` (JSON compacto + DEFLATE crudo + Base32, descompresor propio `Inflate` con límite de 2 MiB). Ejemplos: `RPGU1-NWJB9PTDPWF0-D`, `RPGS1-HDB0M2KGYWTX8XFHECRXAX8D1V8QADYP6NRX2DEG1N9RM180-K` (estancia en blanco sin cambios).
- `RoomContent` (contenido = código base + deltas de terreno, aristas, objetos y salas; huella; reconstruir) y `RoomLibrary` (`user://rooms/`).
- Panel del editor: "Guardar en mi biblioteca", id corto y código para compartir con "Copiar" (y QR si cabe), lista de la biblioteca (abrir, quitar). La caja del código acepta los tres tipos.
- Error corregido antes de subir: leer la biblioteca sin la carpeta creada daba un error del motor que rompía 20 tests.

### Siguiente paso
1. **Decidido por Víctor**: sin QR para estancias (quitado del panel); viajan en los ficheros de guardado. El QR solo para que entren los jugadores.
2. **Idea nueva de Víctor: modo proyectado** (proyector sobre la mesa con miniaturas físicas): en estudio, ver la propuesta en la conversación y pendiente de sus respuestas.
3. E4: usar una estancia propia dentro de un edificio o aldea (y que viaje en el guardado), y en red.

### Limitaciones conocidas (E3)
- El id corto solo abre estancias de la biblioteca de este equipo (en otro, el código para compartir).
- La biblioteca no avisa si dos estancias distintas comparten id (probabilidad ~4·10⁻¹¹ con 10 000 estancias).

## Sesión anterior: 2026-11-26 (14.ª, cuarta parte) — Editor de estancias E2
Tests: **298/298 en escritorio, en inglés y en el navegador** (nuevos: `test_room_editor.gd` ×4 y `test_est_g3.gd` ×7, de `cartografo`). 51 seeds doradas: las 45 de antes sin cambios + 6 de EST G3. Probado con capturas de la app: estancia en blanco 11×8 con agua, ventanas, tabique con puerta y muebles, en 2D y 3D.

### Hecho (ADR 037)
- Botón "Editar" (DM) con `RoomEditorPanel` y herramientas en `MapView2D.edit_tool`: terreno (arrastrar), aristas (arrastrar por los bordes: muro, puerta, secreta, vano, ventana, quitar), objetos del catálogo con giro (R) y borrar, tipo y nombre de sala, y aviso de suelo sin acceso desde la entrada.
- Comandos nuevos con delta reaplicable: `SetTerrainCommand`, `AddObjectCommand`, `RemoveObjectCommand`, `SetRoomCommand` (en `DeltaReplay` y en el esquema de `map_file`).
- "Crear estancia en blanco" → EST G3 (de `cartografo`, ver su nota abajo).
- Error encontrado por el test: al deshacer el borrado de un objeto, volvía al final de la lista (el orden entra en el hash). Ahora vuelve a su posición (`MapLevel.insert_object_at`).
- **Pendiente de aprobar por Víctor**: el esquema de EST G3 (al aprobarlo queda congelado, como el de G1).

### Siguiente paso
1. E3: id corto y código para compartir de una estancia (código + deltas).
2. E4: usar una estancia propia dentro de un edificio o aldea, y en red.

### Limitaciones conocidas (E2)
- Sin escaleras ni niveles en el editor; luces = objetos del catálogo que dan luz.
- Las celdas pintadas de suelo fuera de la sala no pasan a formar parte de ella.

## Sesión anterior: 2026-11-26 (14.ª, tercera parte) — Editor de estancias E1: guardar y abrir mapas
Tests: **287/287 en escritorio, en inglés y en el navegador** (4 nuevos en `test_delta_replay.gd`: ida y vuelta con los 8 tipos de delta, errores, mapa sin código, botones).

### Hecho (ADR 036)
- Deltas completos (`add_token`, `set_token_sheet`, `set_turns` y `move_token` no bastaban para rehacer). `DeltaReplay` reaplica, `MapFile` guarda y abre `*.rpgm-map.json` (código + deltas + `next_id` + hash del mapa generado), y hay botones "Guardar mapa" y "Abrir mapa" (en web, guardar descarga; abrir, solo escritorio).
- **Regla para comandos nuevos**: el delta lleva todo lo necesario para rehacerlo, y su `op` se añade a `DeltaReplay` con un test.

### Siguiente paso
1. **E2 – editor de estancias**: estancia en blanco o a partir de una generada, con herramientas de terreno, aristas, objetos, luces y escaleras. Cada herramienta será un comando nuevo con su delta reaplicable.
2. E3: id corto y código para compartir (decidido: los dos). E4: integración.

### Limitaciones conocidas (E1)
- Se guarda el mapa mostrado, no la ruta entera (aldea → edificio → estancia): eso será la campaña `*.rpgm`.
- Abrir mapas solo en escritorio. Los mapas UVTT se guardan enteros pero sin la imagen de fondo.

### Nota de `cartografo` (E2): generador nuevo EST G3 (estancia en blanco)
- `core/gen/est/est_generator_g3.gd` + esquema `ParamSchemaRegistry.est_g3()` (`width` 3-48 = 9, `height` 3-48 = 7, `grid`, `room_type` con `room` por defecto + ids de EST G1, capacity 64), registrado en `GeneratorRegistry`. Sin azar: código canónico con semilla 0 (`EstGeneratorG3.canonical_code()`). PROYECTO §6.5. Ningún generador existente cambió (las 45 seeds doradas anteriores siguen iguales).
- Seeds doradas nuevas (esquema **pendiente de aprobar**): `RPGM1-DND5-EST-G3-0-0-B`, `RPGM1-DND5-EST-G3-26H-0-G`, `RPGM1-DND5-EST-G3-48N-0-G`, `RPGM1-DND5-EST-G3-1XM-0-Y` (3×3), `RPGM1-DND5-EST-G3-1W5-0-J` (48×48), `RPGM1-PF2E-EST-G3-288V-0-N` (cripta 6×5 hex punta). Tests en `tests/unit/test_est_g3.gd`.

## Sesión anterior: 2026-11-26 (14.ª, segunda parte) — F5: turnos y plantillas de área
Tests: **283/283 en escritorio, con el idioma forzado a inglés y en el navegador**. Nuevos: `test_turns.gd` (5), `test_template_tool.gd` (2) y `test_area_template.gd` (15, de `cartografo`). CI de GitHub en verde otra vez desde `fix(ci)`.

### Hecho (ADR 035)
- **Turnos**: `TurnTracker` en la sesión del documento, `SetTurnsCommand` con deshacer, y `MoveTokenCommand` con el coste de la ruta, que se suma a lo gastado en el turno de esa ficha. Panel "Turnos" (`TurnPanel`): el DM lo maneja y los jugadores lo ven en solo lectura, filtrado (`PlayerView.filter_turns`). La vista muestra "(quedan X)" y, con el bloqueo activado, no deja pasarse. En red: `NET_MOVE_NOT_YOUR_TURN` y `NET_MOVE_TOO_FAR`.
- **Plantillas**: geometría como datos en los perfiles (`area_templates` con forma, tamaño inicial, origen, anchura de cono y de línea), `AreaTemplate.cells` en enteros y medida igual que la regla (en 5e los círculos salen cuadrados, en PF2e octógonos). Herramienta "Plantilla" en la barra (solo 2D, local) con forma y tamaño; cuenta las fichas que quedan dentro.
- Pendiente de verificar con el texto oficial: si en las emanaciones cuenta el espacio de la propia criatura (`includes_origin: true` en los dos perfiles; es un dato del JSON).

### Siguiente paso
1. Que Víctor pruebe turnos y plantillas.
2. Editor de estancias (PROYECTO §6.7, E1–E4). Lo primero es E1: reaplicar deltas y guardar y abrir mapas. Víctor quiere **los dos** identificadores: id corto y código para compartir.
3. Resto de F5: modelos CC0 y animaciones (necesitan permiso de descarga).

### Limitaciones conocidas
- Las plantillas no se comparten con los jugadores y no salen en 3D.
- El turno no cambia solo de nivel si la ficha está en otro (el DM sí salta a ella al pasar turno).

## Sesión anterior: 2026-11-26 (14.ª) — F5: personajes (primera entrega)
Tests: **259/259 en escritorio (33097 asserts) y 259/259 en el navegador** (11 nuevos en `tests/unit/test_characters.gd`, incluido el criterio de F5 por la pantalla principal). 45 seeds doradas sin cambios. Víctor decidió dejar la imagen Docker (F4) para el final y seguir con las fases.

**Criterio de F5 cumplido** ("crear un personaje y verlo en las 3 vistas"): probado con capturas de la app (9 modelos tipo en 2D, 3D y diseñador) y en el test.

### Hecho (ADR 034)
- Modelo: `CharacterSheet` (`*.rpgm-char.json`), `CharacterLook`, `MapToken.sheet` (opcional, se guarda con el mapa) y `MapToken.speed_ft()`. `SetTokenSheetCommand` con deshacer. `PartyVision` usa la visión en la oscuridad del personaje. `PlayerView` manda de las criaturas ajenas solo su aspecto.
- Catálogo `data/characters/look_catalog.json` (`LookCatalog`): 5 complexiones, 7 ranuras, 37 piezas, 7 materiales y 11 modelos tipo. Esquemas `character.schema.json` y `look_catalog.schema.json`.
- Vistas: figura 3D procedural (`CharacterModelBuilder`, una malla por aspecto con caché) sobre una peana del color del bando; en 2D, retrato o silueta (`TokenPainter`).
- UI: botón "Personaje…" (`CharacterDesigner`: edita la ficha seleccionada o crea una), "Importar personajes" en escritorio (CSV o JSON; un JSON ajeno abre `CharacterMappingDialog`). Las fichas se colocan comprobando toda su huella (`main._place_token`).

### CI de GitHub (arreglado)
Fallaban **todos** los pushes desde el 24-11 (y llegaba un correo por cada uno). Causa: 3 tests comparaban textos en español sin fijar el idioma, y el runner de Linux arranca en inglés ("9.14 m" en vez de "9,14 m", "Building" en vez de "Edificio"…). Ahora fijan `es` en `before_all` y lo restauran. `test_uvtt` ya no deja el idioma cambiado. Comprobado en local con el idioma forzado a inglés (hook temporal de GUT): 259/259. Además, el workflow ya no corre en cambios solo de `.md`, cancela las ejecuciones superadas, tiene un límite de 20 min y usa `checkout@v5`. **Regla para tests nuevos:** si comparan textos traducidos, fijar el idioma.

### Siguiente paso
1. Que Víctor pruebe el diseñador y la importación.
2. F5 pendiente: modelos CC0 (necesitan descarga con permiso y registro en `assets/LICENSES.md`), esqueleto y animaciones, turnos/iniciativa (§10.3) y plantillas de área.
3. Después, F6. La imagen Docker queda al final.

### Limitaciones conocidas (F5)
- Velocidad por turno solo del modo caminando (no hay selector de modo al arrastrar).
- Los jugadores no pueden editar su personaje (solo el DM). El retrato solo se carga en escritorio.
- En 2D la ficha con personaje no muestra el nombre (se ve en 3D y al seleccionarla).
## Sesión anterior: 2026-11-26 (13.ª) — F4: escaleras, señal del DM y 3D del jugador
Tests: **248/248 en escritorio (32745 asserts) y 248/248 en el navegador** (escaleras en `test_net_session.gd` y `test_view_commands.gd`, con eventos de ratón reales). 45 seeds doradas sin cambios.

**Probado en Chrome real** con la mazmorra de dos niveles `RPGM1-DND5-MAZ-G1-35040-M6SC7N75-W`: Ana baja y sube por la escalera (doble clic en su ficha; el DM aprueba; su vista cambia sola de nivel y lo explora); ve la señal del DM (anillos "DM"); vista 3D solo con lo explorado; 1.ª persona desde su ficha.

### Hecho (ADR 033)
- **Escaleras para todos**: antes nadie podía cambiar de nivel con una ficha. Doble clic en una ficha sobre una escalera → `MapView2D.take_stairs` (`MoveTokenCommand` con otro nivel, se deshace) y señal `stairs_taken`; el DM pasa a ver ese nivel. Jugador: propuesta validada por `GameSession._validate_stairs` (`NET_MOVE_NO_STAIRS`) y su vista sigue a la ficha (`main._follow_after_stairs`).
- **Señal del DM**: con la partida abierta, su doble clic en una casilla sin edificio la señala a todos con el nombre "DM".
- **Error corregido**: lo que aprobaba el DM explorando el nivel **que él miraba**; ahora `main._explore_level(nivel del comando)`.
- **Doble clic en una ficha** (2D y 3D, DM y jugador): si está en una escalera la toma; si no, centra las dos vistas en ella sin cambiar el zoom (`token_activated`, `center_on_cell`, `main._center_on_token`). Al cambiar de nivel por una escalera también se centra en la ficha.
- **3D del jugador**: `MapView3D.fit_region` encuadra lo que el grupo **ve ahora** y sus fichas (`main._party_focus`; antes, todo lo explorado, que con zonas lejanas quedaba enorme), mínimo 12 casillas y cámara casi cenital (15°) para que los muros no tapen las fichas. Igual en la 3D del DM con "Ve: jugadores". La 1.ª persona usa la ficha propia.
- Para pruebas: Chrome detiene el bucle de una página tapada por otra ventana (la conexión parecía tardar minutos). Lanzarlo con `--disable-backgrounding-occluded-windows --disable-renderer-backgrounding --disable-background-timer-throttling`. No es un fallo del juego.

### Siguiente paso
1. Víctor probó con el móvil: **QR y táctil funcionan**. Pidió mejorar el encuadre 3D: hecho y confirmado por Víctor ("ahora va bien").
2. Pendiente de F4: imagen Docker (ADR 016, alternativa). Después, F5.

### Limitaciones conocidas (F4)
- Visión compartida por el grupo; escaleras solo en 2D (en 3D/1.ª persona no hay doble clic de escalera).
- Las escaleras que salen del mapa (estancia EST G2 → edificio) siguen siendo del DM ("← Volver").
## Sesión anterior: 2026-11-26 (12.ª) — F4: prueba en Chrome real, puertas de los jugadores y QR
Tests: **246/246 en escritorio (32712 asserts) y 246/246 en el navegador** (7 nuevos: `test_qr_code.gd` ×5, puertas en `test_net_session.gd`, direcciones en `test_net_protocol.gd`). 45 seeds doradas sin cambios.

**Probado en Chrome real** (con ventana, perfil aislado, manejado por CDP): Ana entra con su enlace; arrastrar una ficha ajena → "Esa ficha no es tuya"; doble clic → anillos con "Ana" en el navegador y `PING Ana` en el DM; su ficha tras una puerta cerrada → "Sin ruta"; clic en la puerta → el DM la aprueba y se abre; arrastrar su ficha a la sala → el DM aprueba el movimiento, la ficha llega y lo explorado crece. La sesión anterior decía que Chrome sin ventana "no pasa los clics": era el arnés de pruebas (mandaba un campo `delay` en cada orden CDP y Chrome descartaba la orden entera), no el juego.

### Hecho (ADR 032)
- **Puertas por los jugadores**: mensaje `door {level, edge, open}`, `NetClient.propose_door`, `GameSession.validate_door` (opción `players_open_doors`, ficha propia en una de las dos casillas, puerta de verdad, secretas sin descubrir = muro, sin llave) y señal `door_approved` → el DM lo ejecuta en su historial. Casilla "Los jugadores abren y cierran puertas" en el panel (activa por defecto). `main._propose` envía las puertas.
- **Vista 2D**: un clic muy cerca de una puerta (< 0,12 casillas) la acciona aunque haya ficha en la casilla (`DOOR_OVER_TOKEN_FRAC`; antes, en un pasillo de una casilla con fichas a ambos lados, no se podía).
- **QR** (`net/qr_code.gd`, `QrCode`): modo byte, versiones 1-10, corrección L/M, elección de máscara por penalización; botón "QR" por jugador en el panel (ventana con el código y el enlace).
- **Dirección de los enlaces**: selector "Dirección" en el panel con `NetHostPanel.rank_addresses()` (interfaces reales primero; WSL/Hyper-V, VMware, VirtualBox, Docker, Tailscale… al final). En este equipo antes salía `172.26.64.1` (conmutador de Hyper-V) en vez de la de Ethernet.

### Cómo probarla (Víctor)
Como en la 11.ª, y además: en el panel, comprobar que "Dirección" muestra la IP de la red de casa; botón "QR" y escanearlo con el móvil (misma wifi; aceptar el aviso del certificado); en el móvil, tocar una puerta junto a la ficha propia.

### Siguiente paso
1. Prueba manual de Víctor con móvil y 2-3 navegadores (y de F3). **El QR no se ha escaneado con un móvil de verdad**: solo se ha verificado con valores publicados y leyéndolo de vuelta en las pruebas.
2. Pendiente de F4: vista del jugador en 3D/1.ª persona con la niebla del servidor (sin probar a fondo); señal del DM hacia los jugadores; escaleras propuestas por los jugadores; imagen Docker (ADR 016, alternativa).

### Limitaciones conocidas (F4)
- Visión compartida por el grupo; el movimiento no cambia de nivel (escaleras = DM).
- En 3D/1.ª persona la puerta se propone igual (misma pila), pero no se ha probado en el navegador.
- Táctil (móvil): arrastrar y tocar puertas usa los eventos de ratón emulados de Godot; sin probar en un móvil real.
## Sesión anterior: 2026-11-25 (11.ª) — F4: partida en red (primera entrega)
Tests: **239/239 en escritorio (32514 asserts) y 239/239 en el navegador** (18 nuevos: `test_net_protocol.gd`, `test_net_session.gd`, `test_net_wss.gd`; los 3 de sockets quedan pendientes en web porque allí no hay servidor TCP). 45 seeds doradas sin cambios. **Criterio de F4 medido**: 8 clientes WSS reales en 127.0.0.1, peor latencia de propuesta → los 8 ven la ficha movida = **76 ms** (< 150 ms).

Probado con la app y Chrome: la app del DM (script con `main.tscn`) abre la partida, sirve la exportación Web por HTTPS y Chrome entra con el enlace `https://127.0.0.1:47830/?sala=…&t=…`: "Conectado como Ana · Mazmorra", ve solo lo explorado y encuadrado. **No probado** en el navegador: arrastrar y señalar (Chrome sin ventana no pasa los clics sintéticos a Godot y el navegador integrado rechaza el certificado autofirmado); esa ruta sí la cubren las pruebas con sockets reales.

### Hecho (ADR 031; detalle en PROYECTO §11)
- `net/`: `WsCodec`, `WssServer` (HTTPS + WSS en un puerto, gzip, `Origin`), `NetCertificate` (autofirmado en `user://net/server.key|crt`, sustituible), `NetMessage`, `PlayerView` (niebla filtrada en el servidor), `GameSession` (sala + códigos, validación de movimientos, señales, solo cambios), `NetClient`, `ProposalStack`.
- Modelo: `SetTokenCharacterCommand` (dar ficha a un jugador, `character_ref = player:<id>`), `MapLevel.load_explored`.
- Vista 2D: señales (`show_ping`, anillos 2,5 s con el nombre) y `fit_region`.
- UI: botón "Partida en red" (solo escritorio) con panel lateral; modo jugador en web con `?sala=&t=`; textos `UI_NET_*`, `NET_*`, `CMD_SET_TOKEN_CHARACTER`.
- Error encontrado y corregido: con escrituras TLS de 64 KB Chrome recibía el `.wasm` con 16 379 bytes de menos (ERR_CONTENT_DECODING_FAILED); ahora 4 KB por escritura y reintento idéntico (comentado en `WssServer._flush`).

### Cómo probarla (Víctor)
1. Exportar Web (`godot --headless --path project --export-release "Web" ../build/web/index.html`); al ejecutar desde el proyecto se sirve `build/web`; en una build, copiar esa carpeta como `web/` junto al ejecutable.
2. En la app: generar mapa, añadir fichas, "Partida en red" → "Abrir partida" → nombre → "Añadir jugador" → clic en una ficha → "Darle la ficha seleccionada" → "Copiar enlace".
3. Abrir el enlace en otro equipo de la red (aceptar el aviso del certificado; Windows puede pedir permiso de cortafuegos para Godot/la app).

### Siguiente paso
1. Prueba manual de Víctor con 2-3 navegadores reales (y de F3, pendiente).
2. Pendiente de F4: QR del enlace; vista del jugador en 3D/1.ª persona con la niebla del servidor (hoy usa la misma ruta, sin probar a fondo); señal del DM; opción de que los jugadores abran puertas; imagen Docker (ADR 016, alternativa).

### Limitaciones conocidas (F4)
- Visión compartida por el grupo (no por personaje); puertas y escaleras solo las maneja el DM; el movimiento no cambia de nivel.
- Los jugadores de una partida anterior se conservan al reabrir, con enlaces nuevos (sala nueva).
- El servidor HTTP es mínimo: GET, sin keep-alive ni rangos; carga los ficheros web en memoria (~40 MB + ~10 MB comprimido).
## Sesión anterior: 2026-11-25 (10.ª) — F3: Universal VTT (último punto de F3)
Tests: **221/221, 31691 asserts, idénticos en escritorio y navegador** (10 nuevos en `tests/unit/test_uvtt.gd`); 45 seeds doradas sin cambios; `play_f2.gd` 0 fallos. Probado en la app real: exportar con imagen la mazmorra de ejemplo (48×36, 4800×3600 px, 110 tramos, 19 puertas), la sala común EST G2 (2 luces) y el pueblo amurallado (192×142 a 42 px/casilla = 8064 px, ~2 s) y reimportarlos (los muros y puertas coinciden con la imagen).

**Con esto F3 tiene todo su contenido** (EDI, ALD, plantas, navegación aldea → edificio → estancia, estilos, Universal VTT) y cumple su criterio (estancia aislada = dentro de la aldea, EST G2). Falta la prueba manual de Víctor.

### Hecho
- **`core/io/uvtt_codec.gd`** (`UvttCodec`, ADR 030; carpeta `core/io/` nueva): `export_level(doc, nivel, png, px_por_casilla, dm)`, `to_json`, `merge_segments`, `import_text(texto) -> ImportResult` (doc, image, error, walls, doors, lights, approximated_length). Detalle en PROYECTO §7.
- **`MapDocument.background_image`** (solo vista; ni se serializa ni entra en hashes). La vista 2D la pinta de fondo en el nivel 0 (en vez del color del suelo) y, con fondo, de los objetos solo dibuja el círculo de luz. `MapView2D.show_tokens` y `PngExporter.render(..., show_tokens)`.
- **UI**: botones "Exportar UVTT" (diálogo nativo; en web, descarga) e "Importar UVTT" (solo escritorio); `open_uvtt_text(texto, nombre)` abre el mapa como raíz nueva; la barra resume casillas, muros, puertas, luces y lo aproximado en escalera. Textos `UI_*UVTT*`, `UVTT_ERR_*`.

### Siguiente paso
1. Prueba manual de F3 por Víctor (aldea → edificio → estancia, exportar UVTT y abrirlo en otra mesa, p. ej. Foundry con el módulo de importación UVTT).
2. F4 – Red.

### Limitaciones conocidas (UVTT)
- Importar solo en escritorio (en web no hay diálogo para abrir ficheros locales).
- Importa siempre un mapa cuadrado de una planta; sin terreno (todo suelo), sin estancias ni entrada (la ficha nueva sale en la primera casilla libre).
- Ventanas y vanos no se exportan; las luces importadas usan el objeto `torch_sconce` (en 3D se ven como antorchas).
- En el selector de escala queda la última elegida al importar (el mapa no tiene código).
- No probado aún contra un programa real (Foundry, Dungeondraft); el formato sigue la especificación 0.3.

## Sesión anterior: 2026-11-25 (9.ª) — F3: código de estancia de edificio, EST G2 (`cartografo`)
Tests: **211/211, 28324 asserts, idénticos en escritorio y navegador** (10 nuevos en `tests/unit/test_est_g2.gd` y 2 más en `test_map_navigation.gd`); **37 seeds doradas sin cambios** (EDI G1 y ALD G1 intactos); `play_f2.gd` 0 fallos. Revisado por el coordinador y probado en la app con ventana real: aldea → doble clic en la taberna → doble clic en la sala común (`RPGM1-DND5-EST-G2-1QY00-BC23VGX8-9`, idéntica a la del edificio) → "← Volver a: Taberna" → "← Volver a: Aldea".

### Hecho
- **EST G2** (`core/gen/est/est_generator_g2.gd`; PROYECTO §6.5, **ADR 029**): código `RPGM1-<SIS>-EST-G2-<PARAMS>-<SEED>-<CRC>` con PARAMS = 7 campos de EDI G1 + `level` (0-7) + `room` (0-63) y SEED = la del edificio. Planifica el edificio sin muebles, amuebla solo esa estancia y la extrae por traslación (anillo de 1 casilla copiado del edificio; paridad hex; 1 nivel; escaleras con `to_level` relativo −1/+1). EST G1 no cambia y convive (registro con G1 y G2).
- **EDI G1 sin cambio de salida**: `generate_building()` = `plan_building()` (nuevo, público) + `furnish_room()` (nuevo, público) por estancia, mismo orden de llamadas.
- **`GeneratorRegistry`**: "explicador" opcional por (ESC, GEN) (`register(..., explain)`) que da la clave i18n cuando el generador devuelve null: `SEED_ERR_ROOM_LEVEL`, `SEED_ERR_ROOM` (nuevas en `strings.csv`).
- **`ParamSchemaRegistry.est_g2()`** (campos de EDI copiados, no leídos de `edi_g1()`; el test comprueba que coinciden).
- `MapStair.to_level` y `map_document.schema.json`: documentado que fuera de [0, niveles) la escalera sale del mapa (sin `minimum: 0`).
- **API para la UI** (sin tocar `main.gd` ni `MapNavigator`): `EstGeneratorG2.rooms_of(edi_code)`, `room_at(edi_code, nivel, casilla)`, `room_code(edi_code, nivel, orden)`, `building_code(est_code)`, `ref_of(est_code)`; `RoomRef` (`level`, `order`, `kind`, `hub`, `rect`, `offset`, `map_size`, `entry`, `contains`, `to_room_cell`, `to_building_cell`, `to_map_child`).
- **Navegación edificio → estancia en la UI** (coordinador): en un edificio EDI G1, doble clic en una estancia la abre sola con su código EST G2 (`_room_ref_at` → `RoomRef.to_map_child()`). `MapNavigator.enter(..., keep_positions = true)`: modo "misma casilla" (acercamiento 1:1): pasan solo las fichas del grupo que están dentro de la estancia, a su casilla equivalente, y al salir vuelven a la misma casilla y nivel del edificio (`Frame.keep_positions`, `Frame.parent_level`). Aldea → edificio sigue "por la puerta". Botón "← Volver a: Taberna", textos `UI_NAV_ENTERED_ROOM`, `UI_NAV_RETURNED_ROOM`, `UI_NAV_HINT_ROOM`; `_frame_name` usa `ROOM_KIND_` en estancias y el tipo de edificio en un EDI raíz.
- Detalle conocido: `content_hash()` incluye `next_id`, que avanza al añadir una ficha (sesión). No se cambia (alteraría todas las seeds doradas); para comparar contenido con fichas, comparar los niveles.
- Medido: estancia 8-13 ms de media (peor 21) frente a 31-48 ms del edificio; posada hex 33 ms frente a 154 ms; `rooms_of` 6-35 ms. PNG de revisión en el scratchpad de la sesión (`est_g2_png`).

### Aprobado (2026-11-25)
- **EST G2 aprobado por Víctor y congelado** con 8 seeds doradas (45 en total): sala común, dormitorio y sótano de la taberna de la aldea de ejemplo; forja hex plana; cripta hex punta en sótano; cocina de 3.ª planta; dormitorio de posada hex; pasillo del sótano de un cuartel. 211/211 en escritorio y navegador.

### Siguiente paso
1. Universal VTT (F3), último punto de F3.
2. Escaleras de una estancia sola (−1/+1): hoy no llevan a ningún sitio; podrían "salir al edificio" en el nivel de destino.

### Códigos EST G2 para probar (taberna `RPGM1-DND5-EDI-G1-Y00-BC23VGX8-T` de la aldea `RPGM1-DND5-ALD-G1-0-H8DJRFAE-W`)
`RPGM1-DND5-EST-G2-1QY00-BC23VGX8-9` (sala común, nivel 1) · `RPGM1-DND5-EST-G2-FFY00-BC23VGX8-P` (cocina) · `RPGM1-DND5-EST-G2-X7Y00-BC23VGX8-H` (almacén) · `RPGM1-DND5-EST-G2-Y00-BC23VGX8-E` (almacén del sótano, nivel 0) · `RPGM1-DND5-EST-G2-H6Y00-BC23VGX8-5` (dormitorio, nivel 2) · `RPGM1-DND5-EST-G2-3EY00-BC23VGX8-2` (pasillo, hub).

### Limitaciones conocidas (EST G2)
- Ligado a EDI G1: si EDI G1 pasa a `legacy/`, EST G2 debe seguir usando esa versión; un EDI G2 necesitaría EST G3 (o un campo `edi_gen` al final).
- Si EDI G1 gana un campo al final, EST G2 no puede insertarlo en medio: iría tras `room`.
- El anillo no lleva objetos ni escaleras de las vecinas (contexto mínimo). Las escaleras de la estancia apuntan fuera del documento (−1/+1): la UI debe tratarlas como "salir al edificio".
- `room_at` distribuye el edificio en cada llamada (6-35 ms): la UI puede llamar una vez a `rooms_of` y cachear.

## Sesión anterior: 2026-11-25 (8.ª) — F3 etapa 3: navegación aldea → edificio
Tests: **199/199, 24568 asserts, idénticos en escritorio y navegador** (5 nuevos en `tests/unit/test_map_navigation.gd`); 37 seeds doradas sin cambios. `play_f2.gd` sigue con 0 fallos. Probado en la app con ventana real (eventos inyectados): doble clic en la taberna de `RPGM1-DND5-ALD-G1-0-H8DJRFAE-W` → entra con las 2 fichas en la puerta, nivel 2 (tiene sótano), 1ª persona mirando a la puerta; "← Volver a: Aldea" → fichas delante de la puerta.

### Hecho
- **`MapNavigator`** (`core/model/map_navigator.gd`, ADR 028): ruta de mapas (`frames`), cada uno con documento, historial y nivel; hijos visitados cacheados en el padre. `enter(child, nivel, perfil)` / `back(perfil)` pasan las fichas del grupo por la puerta y vacían el historial de los dos mapas. `free_cells_near(..., max_count)` para en cuanto tiene casillas (recorrer una ciudad entera costaba ~0,5 s).
- **`RemoveTokenCommand`** nuevo (con delta `remove_token`, deshacer y rehacer).
- **UI** (`ui/main.gd`): señal `cell_activated` (doble clic sin ficha) en `MapView2D` y `MapView3D` (cenital) → `_on_cell_activated`; botón "← Volver a: {name}" (`_back_btn`); `_show_frame` pone código, escala, sistema y rejilla del mapa; la barra de un asentamiento añade "Doble clic en un edificio para entrar en él". `_set_document(doc, stack, nivel)` ya no crea historial ni reinicia el contador de fichas (solo al generar). Textos nuevos `UI_NAV_*`, `CMD_REMOVE_TOKEN`.
- **Vista 2D**: la casilla sale de la posición del **evento** (`_pointer_local/_pointer_global`), no de `get_local_mouse_position()` (con eventos inyectados el doble clic caía fuera del mapa; también mejor para táctil y web). El zoom con rueda usa el mismo punto.
- **1ª persona**: si la ficha tiene una puerta al lado, mira hacia ella (`_door_direction`); si no, como antes.

### Siguiente paso
1. ~~Criterio de F3 a nivel estancia~~ (EST G2 en la 9.ª sesión, pendiente de aprobar).
2. Universal VTT (F3).

### Limitaciones conocidas (navegación)
- Solo aldea → edificio; edificio → estancia llegará con la decisión anterior.
- Al generar otro mapa se olvida la ruta y los edificios visitados (no hay guardado de partida aún).
- El doble clic en 3D solo en vista cenital (en 1ª persona no hay casilla bajo el puntero).

## Sesión anterior: 2026-11-25 (7.ª) — F3 etapa 2: generador de asentamientos ALD G1 (`cartografo`)
Tests: **194/194, 24275 asserts, idénticos en escritorio y navegador** (16 nuevos en `tests/unit/test_ald_generator.gd`). Revisado por el coordinador y probado en la app: los códigos de ejemplo y la taberna hija se generan y se ven en 2D, 3D cenital y 1ª persona sin errores. **ALD G1 aprobado por Víctor (2026-11-25) y congelado**: 8 seeds doradas de ALD + la taberna hija como EDI (37 en total); las 28 anteriores no cambian.

### Hecho
- **ALD G1** (`core/gen/ald/ald_generator_g1.gd`, `ald_data.gd`; PROYECTO §6.3, **ADR 027**): escala 1 casilla = 5 ft (la de EDI); calles orgánicas (caminantes + ramas en niveles) o retícula; plaza; muralla con puertas; río con puente o costa; parcelas = huella EDI + anillo + patio; población derivada. Mapa ampliado con muralla/agua para no perder suelo edificable.
- **Cada edificio es un hijo EDI G1**: parámetros de `fork("building", k)`, semilla `hash64(semilla, "EDI", k) & (2⁴⁰−1)`, código guardado en `MapLevel.children` (**`MapChild`** nuevo: código, zona, `offset`, `child_level`, huella, entrada; se serializa solo si hay hijos). `EdiGeneratorG1.plan_ground_floor()` (nuevo, no cambia la salida de EDI) da puertas y ventanas sin amueblar. Test del criterio de F3: el código hijo regenera exactamente huella, tipo, muros, puertas, ventanas y entrada.
- **Esquema ALD G1** en `ParamSchemaRegistry.ald_g1()`: `size, grid, style, wall, water, prosperity, layout`. Registrado en `GeneratorRegistry`.
- **Datos**: `data/settlements/ald_settlement_types.json` (+ esquema); bloque `settlement` opcional en `data/styles/*.json` (EST y EDI no lo leen; `style.schema.json` actualizado). `MapRoom`: zonas `street, plaza, bridge, gate, town_wall, yard, building, garden, field` y `OUTDOOR_KINDS`.
- **Vistas**: colores por zona (`MapMeshBuilder.ZONE_COLORS`, en 2D y 3D), tejado y nombre del tipo en 2D, rótulo en 3D; `outdoor_mask` usa `OUTDOOR_KINDS` (sin techo en 1ª persona al aire libre). MAZ/EST/EDI no cambian.
- **UI**: escala "Asentamiento" (`UI_SCALE_ALD`); al generar, la barra dice tamaño, nº de edificios y habitantes; la ficha nueva sale en la plaza.
- Medido: caserío ~40 ms, aldea ~100 ms, pueblo ~250 ms, ciudad ~520-730 ms, peor caso 973 ms; 100 % de edificios colocados en 36 asentamientos de estadística. Capturas 2D en `scratchpad/ald_png` (revisadas: aldea y pueblo con muralla y río).

### Pendiente de Víctor
- Decidir EST G2 / código de estancia de edificio (criterio de F3 a nivel estancia).

### Pedido para el futuro (Víctor, 2026-11-25)
- **Efectos de zona**: fuego, niebla, agua, ácido, lava, etc. colocables en zonas. Anotado en PROYECTO §6.7 (ideas de diseño: como datos, como sesión con deshacer, efecto en visión/movimiento, filtrado en red) y en §16 como fase sin asignar. Necesita un ADR antes de implementarlo.

### Códigos ALD para probar en la app
`RPGM1-DND5-ALD-G1-0-H8DJRFAE-W` (aldea, 16 edificios) · `RPGM1-DND5-ALD-G1-1G1-KCP3TKJZ-3` (pueblo con muralla y río, 34) · `RPGM1-PF2E-ALD-G1-28HA-NGYMWQV0-1` (ciudad enana rica, amurallada, retícula, hex plana) · `RPGM1-DND5-ALD-G1-1T27-QN75YR3H-9` (caserío élfico pobre en la costa). Edificio hijo de la aldea: `RPGM1-DND5-EDI-G1-Y00-BC23VGX8-T` (taberna).

### Siguiente paso
1. ~~Navegación aldea → edificio en la UI~~ (hecho en la 8.ª sesión).
2. Universal VTT (F3).

### Limitaciones conocidas (ALD G1)
- Edificios sin girar (EDI no tiene orientación): todas las huellas apaisadas.
- Sin mercado con puestos, pozos ni muelles; río o costa, no ambos; la muralla queda abierta donde la cruza el agua.
- Una "ciudad" G1 es un barrio (60-80 edificios) por la escala táctica.
- En hex, calles y parcelas son rectángulos en coordenadas offset (bordes dentados, como EDI).
- La vista 3D de una ciudad tarda ≈ 1,3 s en construirse (pueblo ≈ 0,43 s, aldea ≈ 0,15 s); 2D es inmediata.

## Sesión anterior: 2026-11-24 (6.ª) — F3 etapa 1: generador de edificios EDI G1 (`cartografo`)
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
pwsh tools/run_tests.ps1        # importa + tests; debe dar 209/209
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
