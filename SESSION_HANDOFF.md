# SESSION_HANDOFF — RPG Mapping

## Última sesión: 2026-11-24 (3.ª)
**Fase actual:** **F0 – Base completada** (tests verdes en escritorio y en web). Siguiente: F1.

### Hecho en esta sesión
- PowerShell actualizado a 7.6.7. Git Bash sigue fallando al hacer fork: **trabajar siempre con PowerShell** (los subagentes que solo tienen Bash no pueden ejecutar tests).
- Decisiones pendientes resueltas con Víctor una a una (ver abajo y PROYECTO.md §17, ADR 009 y 011-016; §19 queda sin preguntas abiertas).
- **Licencias** (ADR 011): leídos los textos oficiales ORC final (TX 9-307-067) y DPCGL 2.0 (5-8-2026). **Daggerheart descartado** (`daggerheart.json` borrado, `DPCGL` fuera del esquema, clave i18n eliminada). PF2e se queda: aviso ORC completo en `pf2e.json` (`attribution_verified: true`) y en `NOTICE.md` (nuevo); `pf2e.json` se distribuye bajo ORC, no GPL. Modo `bands` conservado como genérico (test con perfil sintético). README actualizado con aviso de no afiliación.
- **PARAMS posicional** (subagente `cartografo`, ADR 009 revisado, PROYECTO §5.3): `core/seed/param_schema.gd`, `param_schema_registry.gd` (MAZ G1 **provisional**, se congela con la primera seed dorada), `SeedCode` adaptado, 5 claves `SEED_ERR_*` nuevas. Ejemplo con 4 parámetros: `RPGM1-DND5-MAZ-G1-FA8-0000000000016-<CRC>` (37 car.).
- **Exportación**: plantillas 4.7.2 instaladas en `%APPDATA%\Godot\export_templates\4.7.2.stable` (SHA-512 verificado contra el oficial). `project/export_presets.cfg` con Windows, Linux, macOS, Web y **Web Tests**; iconos copiados en `project/export_icons/`; `include_filter="*.json"` para los perfiles. Las 5 exportaciones salen sin errores.
- **Tests en web**: `tests/web/web_runner.tscn` (escena principal del preset "Web Tests" vía `run/main_scene.web_tests`) ejecuta GUT y deja el resultado en `document.title` y en consola (`WEB_TESTS_RESULT ...`). Ejecutado en Chrome: **53/53, 7456 asserts**, idéntico a escritorio. El preset exporta scripts como texto y los `*.txt` de GUT.
- Tests de escritorio: **53/53** (`pwsh tools/run_tests.ps1`).

### Decisiones de esta sesión (Víctor)
- PARAMS posicional (ADR 009). Commit tras exportaciones. Remoto: **GitHub público `letzzar/rpg-mapping`, rama `main`**, + **espejo pull en Gitea** (lo configura Víctor en la web de Gitea: Nuevo repositorio → Migración → GitHub → marcar "Espejo").
- Licencias: Daggerheart fuera (ADR 011). Hex opcional en todas las escalas (012). Universal VTT en F3, Foundry tras v1 (013). Impresión a escala antes de v1, no en F1 (014). Estilos humano/enano/élfico en v1 como datos (015). Cliente web servido por la app del DM + imagen Docker alternativa (016).

### Para validar con Víctor (propuestas del `cartografo`)
1. Al analizar un código se comprueba el control antes que el contenido (una errata da `SEED_ERR_CHECK`).
2. Enumerados con `capacity` (huecos reservados para añadir estilos/tipos sin cambiar códigos emitidos); estilos de usuario fuera de la lista no caben en el código.
3. Campos, rangos y defectos del esquema MAZ G1 provisional.
4. SEED es ahora lo más largo (13 car. fijos); se podría acortar con semillas de longitud variable.
5. El carácter de control puede salir O/I/L/U (MOD 37,36 usa 0-9A-Z) y confundirse al dictar: mostrarlo inequívoco en la UI o cambiar de alfabeto.

### Siguiente paso
1. ~~Commit F0 y GitHub~~ **hecho**: commit `b9cd515` en `main`, repo público https://github.com/letzzar/rpg-mapping, CI de Linux **53/53 y 7456 asserts** (igual que Windows y web). Falta que Víctor cree el espejo en Gitea. Aviso menor en CI: `actions/checkout@v4` usa Node 20 (deprecado); subir a la versión que use Node 24 cuando toque.
2. F1: interfaz de rejilla (cuadrada/hex, ADR 012), `MapDocument` (core/model), generadores `MAZ`/`EST`, vista 2D, exportación PNG. Consultar al `cartografo`.

### Pendiente / riesgos
- Uso nominativo de "Pathfinder" en el selector (ORC no cubre marcas); con aviso de no afiliación.
- Pantalla de créditos (futura) debe mostrar `content.attribution` de cada perfil (ORC III, CC-BY).
- Las builds normales aún no tienen escena principal (no hay UI todavía).
- macOS: build sin firmar ni notarizar.

### Comandos para retomar
```powershell
pwsh tools/run_tests.ps1        # importa + tests; debe dar 53/53
$g = "$env:LOCALAPPDATA\Programs\Godot\Godot_v4.7.2-stable_win64_console.exe"
& $g --path project -e          # abrir editor
# Tests en web: exportar, servir y abrir http://127.0.0.1:8765 (el título muestra WEB_TESTS_RESULT)
& $g --headless --path project --export-release "Web Tests" ../build/web-tests/index.html
python -m http.server 8765 --bind 127.0.0.1 --directory build/web-tests
```

### Notas
- Tras crear un script con `class_name` nuevo hay que reimportar (`--import`); `run_tests` ya lo hace.
- Godot no admite el carácter NUL dentro de `String`.
- Godot portable 4.7.2 en `%LOCALAPPDATA%\Programs\Godot\` (fuera del repo, no está en el PATH).
- En `web_runner.gd`, `int(Variant)` dispara un aviso de tipado tratado como error: asignar a variable tipada.
- Icono: el fiel pierde algo de brillo difuso al vectorizar; para tamaños grandes, `icon-raster-1024.png`.
