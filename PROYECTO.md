# RPG Mapping — Especificaciones del proyecto

> Documento vivo. Fuente de verdad del **qué** y el **por qué**. El **cómo trabajar** está en `CLAUDE.md`; el **estado actual** en `SESSION_HANDOFF.md`.
> Versión del documento: 0.1 · Fecha: 2026-11-24 · Licencia del código: GPL-3.0-or-later

---

## 1. Visión

Aplicación de escritorio y web para **generar y usar en mesa** mapas de rol: mundos, regiones, asentamientos, edificios, estancias con su mobiliario y mazmorras. Todo lo generado es **reproducible a partir de una semilla (seed)** más los parámetros iniciales y el sistema de juego. El DM prepara y dirige desde escritorio; los jugadores se conectan desde el navegador y mueven su ficha.

Sistemas soportados de serie: **D&D 5e (reglas 2024, SRD 5.2)**, **Pathfinder 2e (Remaster, ORC)** y **Daggerheart (SRD 1.0)**.

## 2. Objetivos y no-objetivos

### 2.1 Objetivos
| # | Objetivo | Criterio medible |
|---|----------|------------------|
| O1 | Generación procedural en 6 escalas (mundo → región → asentamiento → edificio → estancia, más mazmorra) | Cada escala genera en < 2 s (mundo < 10 s) en un equipo de gama media |
| O2 | Reproducibilidad total por seed | Misma seed + parámetros + versión de generador ⇒ mapa idéntico bit a bit (hash SHA-256 del modelo canónico) en Windows, macOS, Linux y Web |
| O3 | Tres vistas del mismo mapa: 2D cenital, 3D cenital y 1ª persona | Cambiar de vista sin regenerar ni perder estado en < 500 ms |
| O4 | Personajes: carga, diseño con modelos tipo, velocidades y movimiento | Movimiento con coste según reglas del sistema activo y aviso al superar la velocidad |
| O5 | Sistema métrico e imperial | Conmutación en caliente; todas las distancias se muestran en la unidad elegida |
| O6 | Partida compartida DM + jugadores (LAN y online) | Hasta 8 jugadores web + DM con latencia de movimiento < 150 ms en LAN |
| O7 | Software libre | Código GPL-3.0; contenido de reglas solo de licencias abiertas |

### 2.2 No-objetivos (por ahora)
- No es un gestor completo de fichas ni un motor de combate automático (sin tiradas automáticas de ataque/daño en v1).
- No incluye contenido no abierto (bestiarios o aventuras comerciales). El usuario puede importar sus propios datos.
- Sin móvil/tablet nativo en v1 (la versión web cubre tablet de forma básica).
- Sin generación por IA generativa de imágenes: todo es procedural y determinista.

## 3. Plataformas y stack

| Elemento | Decisión |
|----------|----------|
| Motor | **Godot 4.7.x estable** (migrar a 4.8 cuando salga estable y pase los tests de determinismo) |
| Lenguaje | **GDScript** con tipado estático obligatorio. Motivo: la exportación web de Godot 4 no es fiable con C#; GDScript funciona igual en todas las plataformas |
| Plataformas | Windows x86_64, macOS (universal), Linux x86_64, **Web** (cliente de jugador y visor) |
| Renderizado | Forward+ en escritorio; **Compatibility** (WebGL 2) en web. Los shaders deben tener variante Compatibility |
| Red | `WebSocketMultiplayerPeer` (WSS) con RPC de alto nivel de Godot |
| Tests | GUT (Godot Unit Test) en modo headless + tests de "seeds doradas" |
| CI | GitHub Actions / Gitea runner: tests headless + exportación de las 4 plataformas |

## 4. Arquitectura

```
┌──────────────────────────── App Godot ────────────────────────────┐
│  UI (Control)  ─┬─ Editor DM   ─┬─ Vista 2D (TileMapLayer/Canvas) │
│                 ├─ Cliente Jug. ├─ Vista 3D cenital (Camera3D ort)│
│                 └─ Ajustes      └─ Vista 1ª persona (Camera3D)    │
│                         ▲  lee                                     │
│  ┌──────────── Modelo canónico (MapDocument) ─────────────┐       │
│  │ capas: terreno · estructuras · objetos · tokens · FoW  │       │
│  └────────▲───────────────────────────────▲───────────────┘       │
│           │ genera (puro, determinista)   │ aplica                 │
│  ┌────────┴────────┐               ┌──────┴───────┐                │
│  │  core/gen/*     │               │ Ediciones DM │ (deltas)       │
│  │  PRNG propio    │               └──────────────┘                │
│  └────────▲────────┘                                               │
│           │ consulta                                               │
│  ┌────────┴────────┐   ┌───────────────┐   ┌─────────────────┐     │
│  │ Perfiles de     │   │ Paquetes de   │   │ Red (WSS, RPC)  │     │
│  │ sistema (reglas)│   │ contenido     │   │ autoridad = DM  │     │
│  └─────────────────┘   └───────────────┘   └─────────────────┘     │
└────────────────────────────────────────────────────────────────────┘
```

Principios:
1. **Generadores puros**: `generar(params, seed) -> MapDocument`. Sin acceso a nodos, escena, reloj, `randi()` global ni orden de diccionarios no garantizado.
2. **Modelo separado de la vista**: las tres vistas leen el mismo `MapDocument`. Ninguna vista modifica el modelo directamente; lo hacen comandos (patrón Command, con deshacer/rehacer).
3. **Seed + deltas**: un mapa guardado es `seed + parámetros + versión del generador + lista de ediciones manuales`. El mapa completo se puede cachear, pero nunca es la fuente de verdad.
4. **Autoridad del DM**: en red, el DM valida todo movimiento; los clientes solo proponen.

## 5. Sistema de semillas (seeds)

### 5.1 PRNG
- Implementación propia **PCG32** (o xoshiro128**) en GDScript sobre enteros de 64 bits, en `core/rng/`. No se usa `RandomNumberGenerator` del motor para generación (puede cambiar entre versiones).
- Prohibido usar `float` en decisiones que bifurcan la generación salvo con cuantización explícita (`int(x * 1000)`). El ruido (Simplex/OpenSimplex) se implementa en el propio proyecto, con salida cuantizada a enteros, para garantizar igualdad entre plataformas y WebAssembly.

### 5.2 Jerarquía de semillas
Cada nivel deriva la semilla de sus hijos sin generar el resto del árbol:

```
seed_hijo = hash64(seed_padre, tipo_hijo, id_estable_hijo)   # hash64 = SplitMix64 sobre los bytes
```
Así se puede regenerar una sola estancia de un edificio de una aldea de un mundo sin generar todo el mundo.

### 5.3 Código de semilla compartible
Formato legible, copiable y validable:

```
RPGM1-<SIS>-<ESC>-<GEN>-<PARAMS>-<SEED>-<CRC>
ej.: RPGM1-DND5-ALD-G3-7KQ2M9-0F3XH8WZ1T4P-K
```
| Campo | Contenido |
|-------|-----------|
| `RPGM1` | Versión del formato de código |
| `SIS` | Sistema: `DND5`, `PF2E`, `DGHT`, `GEN` (genérico) |
| `ESC` | Escala: `MUN`, `REG`, `ALD` (asentamiento), `EDI`, `EST`, `MAZ` |
| `GEN` | Versión del algoritmo del generador de esa escala (`G1`, `G2`…) |
| `PARAMS` | Parámetros iniciales serializados de forma canónica, comprimidos y en **Base32 Crockford** |
| `SEED` | 64 bits en Base32 Crockford |
| `CRC` | Carácter de control (mod 37) para detectar erratas |

Reglas:
- Cambiar un algoritmo **obliga a subir `GEN`** y mantener el anterior en `core/gen/<escala>/legacy/` para que las semillas antiguas sigan funcionando.
- El sistema de juego forma parte de la semilla porque cambia escalas (tamaño de casilla, tamaños de criatura, distancias por defecto).

### 5.4 Pruebas de determinismo ("seeds doradas")
`tests/golden/` contiene pares `código de semilla → hash SHA-256 del MapDocument canónico`. CI falla si alguno cambia sin subir `GEN`. Se ejecutan en escritorio y en la exportación web (headless con navegador).

## 6. Generación procedural por escala

Cada generador declara: parámetros de entrada (con valores por defecto), salida, algoritmo y versión.

### 6.1 Mundo / continente (`MUN`)
- Parámetros: tamaño (p. ej. 2048×1024 celdas), % tierra, nº de placas, clima (latitud), nivel del mar, nº de reinos, nivel de magia/tecnología.
- Algoritmo: ruido fractal + placas simplificadas → mapa de altura; erosión hidráulica ligera; ríos por flujo descendente; humedad y temperatura → biomas (Whittaker); regiones políticas por Voronoi ponderado con fronteras naturales; caminos por A* sobre coste de terreno entre asentamientos.
- Vista 2D: estilo "pergamino" (coherente con el icono). Vista 3D: relieve con exageración vertical configurable.

### 6.2 Región (`REG`)
- Hexcrawl con hexágonos de **6 millas / 10 km** (configurable). Contiene asentamientos, puntos de interés, encuentros por bioma (solo tablas abiertas o del usuario).

### 6.3 Asentamiento (`ALD`): aldea, pueblo, ciudad
- Parámetros: tamaño (caserío, aldea, pueblo, ciudad), población, cultura/estilo arquitectónico, muralla sí/no, río/costa, prosperidad.
- Algoritmo: trazado de calles por crecimiento orgánico (o retícula para ciudades planificadas); parcelación; asignación de edificios por tipo (taberna, herrería, templo, mercado…) con pesos según tamaño y prosperidad.
- Cada edificio queda como hijo con su propia semilla derivada.

### 6.4 Edificio (`EDI`)
- Planta(s) por **BSP + grafo de adyacencias** según tipo (una taberna exige sala común ↔ cocina ↔ almacén, habitaciones arriba).
- Puertas, ventanas, escaleras entre plantas, sótano opcional.

### 6.5 Estancia (`EST`) y objetos
- Colocación de mobiliario por reglas con etiquetas: `contra_pared`, `centro`, `junto_a:hogar`, `pasillo_libre ≥ 1 casilla`.
- Cada objeto tiene propiedades de juego: **cobertura** (media/tres cuartos/total), **terreno difícil**, **bloquea visión**, **fuente de luz** (radio brillante/tenue), **interactuable** (cofre, palanca), **altura** (para 3D y línea de visión).
- Catálogo de objetos en `data/objects/*.json`, ampliable por el usuario.

### 6.6 Mazmorra (`MAZ`)
- Tipos: construida (salas + pasillos por BSP / algoritmo de habitaciones y corredores), cueva (autómatas celulares), mixta. Opción **Wave Function Collapse** para teselas.
- Garantías: todas las salas accesibles desde la entrada, nº de salidas, ratio de pasillos, trampas y puertas secretas por densidad.

### 6.7 Edición manual
El DM puede pintar terreno, mover/añadir/borrar objetos y muros, renombrar lugares. Todo se guarda como **delta** sobre lo generado (ver §5).

## 7. Vistas

| Vista | Implementación | Uso |
|-------|----------------|-----|
| **2D cenital** | `TileMapLayer` + `Node2D` para objetos/tokens; rejilla cuadrada o hexagonal | Preparación, pantalla de jugadores, impresión |
| **3D cenital** | `Camera3D` ortográfica o perspectiva con inclinación 0–60°; muros extruidos por altura; `GridMap` + mallas modulares | Ambientación, verticalidad, varios pisos |
| **1ª persona** | `Camera3D` en el token seleccionado (altura de ojos según tamaño), FOV 75° configurable | Exploración, ver lo que ve un personaje |

Requisitos comunes:
- Niebla de guerra y **línea de visión** calculadas en el modelo (no en la vista), con visión en la oscuridad y fuentes de luz.
- Varias plantas: selector de planta; en 3D, corte de techo y plantas superiores.
- Rendimiento objetivo: 60 fps en mapas de 100×100 casillas en escritorio; 30 fps en web.
- Exportación: PNG a resolución de impresión (≥ 150 ppp, 1 casilla = 1 pulgada / 2,54 cm) y PDF por páginas.

## 8. Perfiles de sistema de juego

Cada sistema es un **perfil de datos** (`data/systems/<id>.json`), no código. La lógica común lee el perfil.

| Concepto | D&D 5e (2024) | Pathfinder 2e | Daggerheart |
|----------|---------------|---------------|-------------|
| Casilla | 5 ft | 5 ft | Abstracto: bandas de alcance (se puede usar rejilla) |
| Diagonal | 5 ft por casilla (opción: alterna 5/10) | Alterna 5/10 | No aplica; se mide la banda |
| Velocidad típica | 30 ft | 25 ft | Movimiento por bandas (Cerca como parte de una acción) |
| Terreno difícil | Coste ×2 | Coste +5 ft por casilla | Narrativo; marca visual |
| Tamaños | Diminuto 2,5 ft · Pequeño/Mediano 5 · Grande 10 · Enorme 15 · Gargantuesco 20 | Igual que 5e | Sin casillas por tamaño; tamaño visual del token |

**Bandas de Daggerheart** (en rejilla, configurables por mesa): Cuerpo a cuerpo = adyacente · Muy cerca ≈ 3 casillas · Cerca ≈ 6 · Lejos ≈ 12 · Muy lejos ≥ 13 · Fuera de alcance = fuera del mapa. La regla de medir muestra la **banda** y, opcionalmente, la distancia.

Cada perfil define además: tipos de movimiento (andar, volar, nadar, trepar, excavar), sentidos (visión en la oscuridad, visión ciega…), condiciones que afectan al movimiento y plantillas de área (cono, línea, esfera, cubo, emanación/explosión).

## 9. Unidades: métrico e imperial

- Unidad interna: **casilla** (entera) y, para medidas libres, **milímetros enteros** (sin floats acumulados).
- Dos modos de conversión, elegibles en ajustes:
  - **Convención de mesa (por defecto)**: 5 ft = 1,5 m (la usada en las ediciones en español). 30 ft → 9 m.
  - **Exacta**: 1 ft = 0,3048 m. 30 ft → 9,14 m.
- La escala de región: 6 mi ↔ 10 km (convención) o 9,66 km (exacta).
- Toda cadena con distancia pasa por `core/units/format_distance()`; prohibido formatear distancias a mano.

## 10. Personajes y fichas (tokens)

### 10.1 Carga
- Formato propio `*.rpgm-char.json` (esquema en `data/schemas/character.schema.json`): nombre, sistema, tamaño, velocidades por tipo, sentidos, iniciativa opcional, retrato, modelo 3D.
- Importadores: CSV simple y JSON genérico con mapeo de campos. (Importadores de otras plataformas, fase posterior.)

### 10.2 Diseñador de personajes con modelos tipo
- **Token 2D**: retrato recortado en círculo con marco de color por bando, o silueta generada por especie.
- **Modelo 3D modular**: base por complexión/especie (humanoide pequeño, mediano, grande; cuadrúpedo; volador) con **ranuras**: cabeza, torso, piernas, mano principal, mano secundaria, capa, accesorio. Colores por material (piel, pelo, ropa, metal).
- Assets base de licencia **CC0** (candidatos: KayKit, Quaternius, Kenney; verificar licencia al importarlos y registrarla en `assets/LICENSES.md`).
- Esqueleto común para compartir animaciones (reposo, andar, correr).

### 10.3 Movimiento
- Al arrastrar un token: previsualización de ruta con **coste acumulado** según el perfil (diagonales, terreno difícil, muros, puertas cerradas).
- Indicador de velocidad restante en el turno; aviso (no bloqueo) al superar; el DM puede bloquear según ajuste.
- Seguimiento opcional de turnos/iniciativa (solo orden; sin automatizar combate).
- Medición y plantillas de área en la unidad activa.

## 11. Partida en red (DM + jugadores)

| Aspecto | Especificación |
|---------|----------------|
| Topología | El **DM aloja** la partida (servidor WSS en la app de escritorio). Jugadores conectan desde el **cliente web** |
| LAN | Conexión directa `wss://<ip-o-nombre>:<puerto>`. El cliente web lo sirve la propia infraestructura (p. ej. contenedor estático en el NAS) en el **mismo origen** que el WSS mediante proxy inverso, para evitar problemas de certificados y contenido mixto |
| Online | Opción A: túnel/proxy inverso propio del usuario. Opción B (fase posterior): **servidor de relevo** headless (export Linux de Godot en Docker) |
| Seguridad | Solo WSS (TLS). Acceso por **código de sala + token por jugador** (QR generado por el DM). Nada de HTTP plano |
| Autoridad | El DM valida movimientos; los clientes reciben solo lo que su personaje ve (la niebla se filtra en el servidor, no en el cliente) |
| Permisos | Jugador: mover sus tokens, medir, señalar (ping). DM: todo |
| Sincronización | Al unirse: se envía código de semilla + deltas (el cliente regenera localmente) + estado de tokens. Luego, solo eventos |

## 12. Datos y ficheros

| Fichero | Contenido |
|---------|-----------|
| `*.rpgm` | Campaña: ZIP con `manifest.json`, mapas (seed + params + `GEN` + deltas), personajes, recursos del usuario |
| `*.rpgm-map.json` | Un mapa suelto exportable |
| `*.rpgm-char.json` | Un personaje |
| `data/systems/*.json` | Perfiles de sistema |
| `data/packs/<pack>/` | Paquetes de contenido, cada uno con su `LICENSE` y `ATTRIBUTION.md` |

Todos los JSON tienen `schema_version` y esquema en `data/schemas/`. Migraciones de esquema en `core/migrations/`.

## 13. Licencias y contenido

- **Código**: GPL-3.0-or-later (`LICENSE`).
- **Contenido de reglas**, solo abierto y en paquetes separados del código:
  - D&D: **SRD 5.2.x** bajo **CC-BY-4.0**, con la atribución exigida.
  - Pathfinder 2e: material del Remaster bajo **ORC License**.
  - Daggerheart: **SRD 1.0** bajo **DPCGL** (Darrington Press Community Gaming License), con su texto de atribución.
- Marcas: no usar logotipos ni nombres comerciales como marca del producto; usar fórmulas tipo "compatible con 5e (SRD 5.2)". Revisar las condiciones de marca de cada licencia antes de publicar.
- **Pendiente de verificar**: compatibilidad de la DPCGL con distribuir el paquete junto a software GPL (si hay duda, el paquete Daggerheart se descarga aparte).

## 14. Interfaz y estilo

- Identidad visual: pergamino, madera oscura y latón (ver `assets/icon/`). Paleta base: madera `#2B1D14`–`#5A4030`, pergamino `#FBF0D2`–`#C9A46A`, latón `#F7DC8E`–`#8A5F1F`, azul brújula `#1D4F7C`–`#5FB4D6`.
- Idiomas: español (principal) e inglés; textos en ficheros de traducción de Godot (`.po`/CSV), nunca incrustados.
- Accesibilidad: tamaño de interfaz escalable, modo de alto contraste para la rejilla, colores de bando distinguibles con daltonismo (además de forma/icono).

## 15. Icono

| Fichero | Uso |
|---------|-----|
| `assets/icon/icon-fiel.svg` | Vector fiel al diseño (tamaños ≥ 128 px, splash, web) |
| `assets/icon/icon-simple.svg` | Vector simplificado, legible a 16–64 px; también `icon.svg` del proyecto Godot |
| `assets/icon/png/icon-<n>.png` | 16–1024 px (≤ 64 desde el simplificado, ≥ 128 desde el fiel) |
| `assets/icon/app.ico` · `app.icns` · `favicon.ico` | Windows · macOS · Web |
| `assets/icon/icon-raster-1024.png` | Original sin fondo negro (referencia) |

## 16. Fases e hitos

| Fase | Contenido | Criterio de aceptación |
|------|-----------|------------------------|
| **F0 – Base** | Proyecto Godot, estructura de carpetas, CI, PRNG + hash + código de semilla, unidades, perfiles de sistema | Tests verdes en escritorio y web; código de semilla ida y vuelta |
| **F1 – Mazmorra y estancia 2D** | Generadores `MAZ` y `EST`, vista 2D, tokens 2D, movimiento con coste, medición | 20 seeds doradas estables; movimiento correcto en los 3 sistemas |
| **F2 – Vista 3D y 1ª persona** | Renderizado 3D cenital y 1ª persona del mismo modelo; línea de visión y luces | Cambio de vista < 500 ms; FoW coherente entre vistas |
| **F3 – Edificio y asentamiento** | `EDI`, `ALD`, varias plantas, navegación jerárquica (aldea → edificio → estancia) | Regenerar una estancia aislada desde su código da el mismo resultado que dentro de la aldea |
| **F4 – Red** | Servidor WSS en DM, cliente web, permisos, FoW filtrada | 8 clientes en LAN, latencia < 150 ms |
| **F5 – Personajes** | Diseñador 2D/3D modular, importación CSV/JSON | Crear un personaje y verlo en las 3 vistas |
| **F6 – Mundo y región** | `MUN`, `REG`, hexcrawl, exportación a impresión | Mundo 2048×1024 en < 10 s |
| **F7 – Pulido y publicación** | Traducciones, accesibilidad, paquetes de contenido, empaquetado | Builds firmadas de las 4 plataformas |

## 17. Registro de decisiones (ADR)

| # | Decisión | Motivo | Alternativas descartadas |
|---|----------|--------|--------------------------|
| 001 | Godot 4 | Libre, 2D+3D nativo, exporta a escritorio y web | Unity (licencia), Tauri+Three.js (dos stacks), Bevy (UI inmadura) |
| 002 | GDScript tipado | Exportación web fiable | C# (web no fiable en Godot 4) |
| 003 | PRNG y ruido propios | Determinismo entre versiones del motor y plataformas | `RandomNumberGenerator` / `FastNoiseLite` del motor |
| 004 | Seed + deltas como formato | Mapas pequeños, compartibles y reproducibles | Guardar el mapa completo |
| 005 | DM como servidor, jugadores en web | Sin infraestructura obligatoria; jugadores sin instalar nada | Servidor central obligatorio |
| 006 | Reglas como datos | Añadir sistemas sin tocar código | Lógica por sistema en código |
| 007 | GPL-3.0 + contenido abierto separado | Software libre sin mezclar licencias de contenido | Licencia privativa |

## 18. Riesgos

| Riesgo | Impacto | Mitigación |
|--------|---------|------------|
| Divergencia de floats entre escritorio y WebAssembly | Rompe la reproducibilidad | Aritmética entera/cuantizada + seeds doradas en web |
| Rendimiento 3D en navegador | Cliente web lento | Web usa vista 2D por defecto; 3D con LOD y Compatibility |
| Certificados TLS en LAN | Jugadores no conectan | Mismo origen vía proxy inverso; guía de despliegue |
| Licencias de contenido | Problemas legales | Paquetes separados, atribuciones, revisión antes de publicar |
| Alcance excesivo | Proyecto sin terminar | Fases con criterio de aceptación; F1 ya es usable en mesa |

## 19. Preguntas abiertas

1. ¿Rejilla hexagonal también en mapas tácticos o solo en región?
2. ¿Dónde se aloja el cliente web por defecto (NAS en Docker como Surimapa, u otro)?
3. ¿Importadores concretos de otras herramientas (Foundry VTT, Universal VTT/`.dd2vtt`) y en qué fase?
4. ¿Se necesita impresión a escala real (1 pulgada por casilla) desde la F1?
5. ¿Plantillas de estilo arquitectónico por cultura (élfica, enana…) en v1 o después?
