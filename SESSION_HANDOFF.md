# SESSION_HANDOFF — RPG Mapping

## Última sesión: 2026-11-24
**Fase actual:** antes de F0 (solo especificación e identidad visual).

### Hecho
- Especificaciones iniciales en `PROYECTO.md` (visión, objetivos, stack, arquitectura, sistema de seeds, generadores, vistas, perfiles de sistema, unidades, personajes, red, licencias, fases, ADR, riesgos).
- Instrucciones de trabajo en `CLAUDE.md`.
- Subagente `cartografo` en `.claude/agents/cartografo.md`.
- Icono: eliminado el fondo negro de `Icono.jpg` y vectorizado:
  - `assets/icon/icon-fiel.svg` (trazado multicolor, ~2,5 MB; ~0,95 MB con gzip).
  - `assets/icon/icon-simple.svg` (redibujo plano, ~4 KB, legible a 16 px).
  - PNG 16–1024, `app.ico`, `app.icns`, `favicon.ico`, `icon-raster-1024.png`.
- `LICENSE` con el texto GPL-3.0.

### Decisiones tomadas con Víctor
- Motor Godot 4 (GDScript). Plataformas: Windows/macOS/Linux + Web.
- Partida DM + jugadores en LAN/online; jugadores por navegador.
- Nombre "RPG Mapping", licencia GPL-3.0.
- Solo contenido de reglas abierto (SRD 5.2 CC-BY-4.0, ORC, DPCGL).
- Personajes: token 2D + modelo 3D modular.
- Icono: versión fiel + versión simplificada.

### Siguiente paso (F0)
1. Crear `project/` con Godot 4.7.x, `icon.svg` = `assets/icon/icon-simple.svg`, iconos de exportación (`app.ico`, `app.icns`, PNG 192/512 para la web).
2. Instalar GUT y configurar CI headless.
3. Implementar `core/rng` (PCG32 + SplitMix64) y `core/seed` (código RPGM1) con tests.
4. Implementar `core/units` y los tres perfiles de `data/systems/`.

### Pendiente de decidir
Ver `PROYECTO.md` §19 (hex táctico, alojamiento del cliente web, importadores, impresión a escala, estilos culturales) y la verificación de la DPCGL (§13).

### Notas
- El icono fiel pierde algo del brillo difuso del original al vectorizar; se añadió un degradado de luz central y viñeta para compensar. Si se quiere más fidelidad a tamaños grandes, usar `icon-raster-1024.png`.
- Claude Code no admite imagen propia para un subagente; el `cartografo` usa el color ámbar del latón del icono.
