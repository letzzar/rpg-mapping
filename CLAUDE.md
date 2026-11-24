# CLAUDE.md — RPG Mapping

Instrucciones para Claude Code en este repositorio. Léelas al empezar cada sesión.

## 1. Arranque de sesión (obligatorio)
1. Lee `SESSION_HANDOFF.md` (estado y siguiente paso).
2. Consulta en `PROYECTO.md` solo las secciones que toque la tarea (es la fuente de verdad de requisitos y decisiones).
3. Antes de tocar generación procedural, PRNG, seeds o unidades, delega o consulta con el subagente **`cartografo`** (`.claude/agents/cartografo.md`).

## 2. Cierre de sesión (obligatorio)
- Actualiza `SESSION_HANDOFF.md`: qué se hizo, qué queda, decisiones tomadas, comandos para retomar.
- Si se tomó una decisión de diseño, añádela a la tabla ADR de `PROYECTO.md` §17.
- Si cambió un algoritmo de generación: sube su `GEN`, mueve el anterior a `legacy/` y regenera las seeds doradas nuevas (nunca sobrescribas las antiguas).

## 3. Idioma y estilo
- Documentación, comentarios y mensajes de commit en **español**. Identificadores de código en **inglés**.
- Textos de interfaz siempre en ficheros de traducción (`i18n/`), nunca incrustados.
- Explica el porqué de cada cambio relevante, no solo el qué.

## 4. Stack
- **Godot 4.7.x** estable, **GDScript con tipado estático** (`var x: int`, funciones con tipo de retorno). Activa en el proyecto los avisos de tipado no seguro como error.
- Nada de C# ni GDExtension sin un ADR previo (rompe o complica la exportación web).
- Tests con **GUT** en headless.

## 5. Estructura del repositorio
```
RPG Mapping/
├─ CLAUDE.md · PROYECTO.md · SESSION_HANDOFF.md · LICENSE · README.md
├─ .claude/agents/cartografo.md
├─ assets/
│  ├─ icon/            # icono (SVG fiel/simple, PNG, ico, icns)
│  ├─ models/          # 3D modulares CC0 (registrar en assets/LICENSES.md)
│  └─ tiles/
├─ project/            # proyecto Godot (project.godot, icon.svg = icon-simple.svg)
│  ├─ core/
│  │  ├─ rng/          # PCG32, SplitMix64, hash64
│  │  ├─ noise/        # ruido propio cuantizado
│  │  ├─ seed/         # código de semilla RPGM1 (Base32 Crockford + CRC)
│  │  ├─ units/        # conversión y format_distance()
│  │  ├─ model/        # MapDocument, capas, comandos, deltas
│  │  ├─ rules/        # lector de perfiles de sistema, coste de movimiento
│  │  ├─ gen/<escala>/ # MUN, REG, ALD, EDI, EST, MAZ (+ legacy/)
│  │  └─ migrations/
│  ├─ views/           # view2d, view3d, first_person
│  ├─ net/             # servidor WSS (DM), cliente, protocolo
│  ├─ ui/
│  └─ i18n/
├─ data/
│  ├─ schemas/         # JSON Schema de todos los formatos
│  ├─ systems/         # dnd5e_2024.json, pf2e.json, daggerheart.json
│  ├─ objects/
│  └─ packs/<pack>/    # contenido con su LICENSE y ATTRIBUTION.md
├─ tests/
│  ├─ unit/
│  └─ golden/          # código de semilla → SHA-256 del modelo canónico
└─ tools/              # scripts de build, exportación e icono
```

## 6. Reglas de oro
1. **Determinismo**: en `core/gen/`, `core/rng/`, `core/noise/` está prohibido: `randi()`, `randf()`, `RandomNumberGenerator`, `FastNoiseLite`, `Time.*`, iterar diccionarios sin ordenar claves, y decidir con `float` sin cuantizar. Toda aleatoriedad entra por el `Rng` que se pasa como parámetro.
2. **Generadores puros**: no acceden a nodos ni a la escena; devuelven un `MapDocument`.
3. **Las vistas no modifican el modelo**: todo cambio va por un comando con deshacer.
4. **Distancias**: siempre en casillas o mm enteros internamente; para mostrarlas, `Units.format_distance()`.
5. **Reglas como datos**: nada de `if system == "dnd5e"` en lógica; se lee del perfil.
6. **Red**: el DM es la autoridad; la niebla de guerra se filtra en el servidor. Solo WSS.
7. **Licencias**: no añadir contenido de reglas que no sea SRD 5.2 (CC-BY-4.0), ORC o DPCGL, y siempre en `data/packs/` con atribución. Todo asset 3D/2D nuevo se registra en `assets/LICENSES.md`.
8. **Archivos del usuario**: no borrar ni sobrescribir `Icono.jpg` ni nada en `assets/` sin pedirlo.

## 7. Comandos habituales
```bash
# Tests (headless)
godot --headless --path project -s addons/gut/gut_cmdln.gd -gdir=res://../tests -gexit

# Solo seeds doradas
godot --headless --path project -s addons/gut/gut_cmdln.gd -gdir=res://../tests/golden -gexit

# Exportaciones (presets definidos en project/export_presets.cfg)
godot --headless --path project --export-release "Windows Desktop" ../build/win/RPGMapping.exe
godot --headless --path project --export-release "Linux"           ../build/linux/RPGMapping.x86_64
godot --headless --path project --export-release "macOS"           ../build/mac/RPGMapping.zip
godot --headless --path project --export-release "Web"             ../build/web/index.html

# Regenerar PNG del icono desde los SVG
rsvg-convert -w 256 assets/icon/icon-fiel.svg -o assets/icon/png/icon-256.png
```

## 8. Definición de "hecho"
- Tests unitarios y seeds doradas en verde (escritorio y web).
- Sin avisos de tipado nuevos.
- Textos traducibles, distancias formateadas por `Units`.
- `SESSION_HANDOFF.md` actualizado.

## 9. Commits
- Convención: `tipo(ámbito): descripción` en español (`feat(gen-maz): pasillos con ratio configurable`).
- Un cambio de `GEN` va siempre en su propio commit, con las seeds doradas nuevas.
