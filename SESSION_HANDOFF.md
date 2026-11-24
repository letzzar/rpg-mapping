# SESSION_HANDOFF — RPG Mapping

## Última sesión: 2026-11-24 (3.ª)
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
1. **Víctor prueba la app** (`& $g --path project`): generar mazmorras y estancias, mover fichas, medir, abrir puertas, exportar PNG. Recoger ajustes de la vista (iconos de objetos, selector de tamaño/bando de ficha, nombres de objetos más legibles).
2. **F2 – Vista 3D y 1ª persona** (§7, §16): renderizado 3D cenital y en primera persona del mismo `MapDocument` (muros en aristas → módulos de pared, ADR 018), línea de visión y luces en el modelo; criterio: cambio de vista < 500 ms y niebla coherente entre vistas. Assets CC0 a registrar en `assets/LICENSES.md`.
### Pendiente / riesgos
- El `cartografo` no puede ejecutar tests (no tiene PowerShell en esta sesión; se añadió a su definición y debería tenerlo en la próxima). Mientras tanto, los ejecuta el coordinador.
- `find_route` no considera otras fichas y usa la casilla de anclaje de criaturas grandes.
- Uso nominativo de "Pathfinder" (ORC no cubre marcas); con aviso de no afiliación.
- Pantalla de créditos (futura) debe mostrar `content.attribution` de cada perfil.
- macOS: build sin firmar ni notarizar. CI: `actions/checkout@v4` usa Node 20 (deprecado).

### Comandos para retomar
```powershell
pwsh tools/run_tests.ps1        # importa + tests; debe dar 139/139
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
