# RPG Mapping — Especificaciones del proyecto

> Documento vivo. Fuente de verdad del **qué** y el **por qué**. El **cómo trabajar** está en `CLAUDE.md`; el **estado actual** en `SESSION_HANDOFF.md`.
> Versión del documento: 0.1 · Fecha: 2026-11-24 · Licencia del código: GPL-3.0-or-later

---

## 1. Visión

Aplicación de escritorio y web para **generar y usar en mesa** mapas de rol: mundos, regiones, asentamientos, edificios, estancias con su mobiliario y mazmorras. Todo lo generado es **reproducible a partir de una semilla (seed)** más los parámetros iniciales y el sistema de juego. El DM prepara y dirige desde escritorio; los jugadores se conectan desde el navegador y mueven su ficha.

Sistemas soportados de serie: **D&D 5e (reglas 2024, SRD 5.2)**, **Pathfinder 2e (Remaster, ORC)**. Daggerheart quedó descartado por licencia (ADR 011); el modo de medida por **bandas de alcance** se conserva para perfiles propios.

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

### 4.1 Rejilla y modelo (F1, ADR 017-019)
- **`core/grid/`**: `GridGeometry` (interfaz) con `SquareGrid` y `HexGrid` (`hex_flat` odd-q, `hex_pointy` odd-r); se crea con `GridFactory.create(kind, w, h)`. Coordenadas guardadas: `Vector2i(columna, fila)` enteras en el rectángulo `w×h` (offset en hex; cálculos internos en axiales). Vecinos en orden fijo, distancia en pasos, tipo de paso (ortogonal/diagonal/hex), radio, línea entera simétrica, aristas canónicas con id entero y huellas de tokens. La conversión casilla↔píxel usa float y es **solo para las vistas**.
- **`core/model/`**: `MapDocument` = procedencia (código RPGM1, escala, `GEN`) + rejilla + `levels: Array[MapLevel]` (todas las plantas con la misma rejilla) + sesión (tokens, niebla por nivel, deltas). Cada `MapLevel` tiene capas por casilla (`terrain`, `room_ids`), aristas dispersas (`MapEdge`: muros finos, puertas, vanos), salas (`MapRoom`), objetos (`MapObject`, propiedades de juego copiadas del catálogo), escaleras (`MapStair`) y trampas (`MapTrap`). Ids estables de un contador único del documento.
- **Serialización canónica** (`CanonicalJson`): claves ordenadas, solo enteros, listas en orden fijo; `content_hash()` = SHA-256 sin sesión (seeds doradas), `full_hash()` con sesión. Esquema en `data/schemas/map_document.schema.json`.
- **`core/gen/generator_registry.gd`**: código de semilla → perfil (por `SIS`) → generador (por `ESC`+`GEN`) → `MapDocument` sellado con su procedencia.

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
ej.: RPGM1-DND5-MAZ-G1-FA8-3QV8M2KD-P   (rooms=20, layout=cave, grid=hex_flat, corridor_pct=45; semilla de la app; 32 caracteres)
ej.: RPGM1-PF2E-ALD-G3-0-1A-K           (todo por defecto, semilla 42 tecleada a mano)
```
Detalles fijados en F0 (ADR 009):

**`SEED` de longitud variable**: uint64 en Base32 Crockford, forma canónica **sin ceros a la izquierda** (`0` = semilla 0), de 1 a 13 caracteres (13 solo si el primero es ≤ `F`). La app genera semillas de **40 bits** con entropía del sistema (`SeedCode.random_app_seed()`, nunca en `core/gen`) y el primer carácter no nulo, así que siempre ocupan **8 caracteres**; a mano se aceptan semillas cortas (42 → `1A`) y hasta 64 bits.

**`SIS`**: 3-4 caracteres del alfabeto de Crockford (sin I, L, O ni U), para que el control los cubra.

**`CRC`: un carácter del alfabeto de Crockford** (sin I, L, O ni U; al leerlo se aplican los alias O→0, I/L→1), calculado en GF(32) = GF(2)[x]/(x⁵+x²+1):
- El cuerpo `RPGM1-SIS-ESC-Gn-PARAMS-SEED` se convierte en símbolos 0..31: cada carácter por su valor Crockford; la escala como **un** símbolo (su índice en `MUN, REG, ALD, EDI, EST, MAZ`, porque MUN y ALD contienen U y L); y un **separador de valor 0** entre campos.
- `CRC = Σ sᵢ·x^(n−i)` (Horner: `c = (c ⊕ s)·x` por símbolo; multiplicar por x es un desplazamiento y un XOR con `0x25`).
- Garantías (demostradas y verificadas de forma exhaustiva en los tests): una sustitución cambia el control en `x^k·(a⊕a')`, que nunca es 0 en un cuerpo; una transposición adyacente lo cambia en `(x^k ⊕ x^(k+1))·(a⊕b)`, no nulo porque x ≠ 1. También detecta transposiciones saltadas (x tiene orden 31) y la del último símbolo con el control. El separador hace que correr un guion entre `PARAMS` y `SEED` (de longitud variable) sea una transposición con un 0 o deje un cero a la izquierda: también se detecta. Ninguna escala está a una errata de otra, así que un error en `ESC` da `SEED_ERR_SCALE`.
- Por qué no ISO 7064 con 32 símbolos: los sistemas puros requieren módulo primo (31 hace coincidir dos símbolos; 37 necesita 37 caracteres de control) y el híbrido MOD 33,32 requiere M+1 primo (33 = 3·11). GF(32) da las mismas garantías con exactamente 32 símbolos.

**`PARAMS` posicional por esquema** (`core/seed/param_schema.gd`, registro en `param_schema_registry.gd`):
- Cada generador declara, ligado a su `GEN`, una lista **ordenada** de campos: entero `[min, max]`, booleano o enumerado (lista cerrada de ids, con `capacity` opcional ≥ nº de ids), cada uno con su valor por defecto. El esquema depende de (`ESC`, `GEN`), no del sistema.
- Cada valor se convierte en un dígito relativo a su defecto: `d = (valor − defecto) mod radix` (radix: `max − min + 1`, 2 o `capacity`); el defecto es siempre 0.
- Los dígitos forman un entero de base mixta con el **primer campo como dígito menos significativo**: `N = d0 + r0·(d1 + r1·(d2 + …))`, escrito en Base32 Crockford **sin ceros a la izquierda**; `0` si todo vale su defecto. Por eso los campos del final que valen su defecto no ocupan nada: hay que ordenar los campos de más a menos usados.
- `N` puede superar 64 bits: se calcula por trozos (dígitos base 32, radix ≤ 2³¹), solo con enteros. Máximo 64 caracteres por esquema.
- Un único texto por conjunto de valores (se rechazan ceros a la izquierda). Con 4 parámetros típicos, `PARAMS` ocupa 3 caracteres y, con semilla de la app, el código entero 32 (con el texto canónico inicial, solo `PARAMS` ocupaba ~70).
- Compatibilidad: añadir un campo **al final** con su defecto, o un id de enumerado **dentro de su `capacity`**, no cambia ningún código ya emitido. Cualquier otro cambio del esquema (orden, rangos, defectos, ids existentes) exige `GEN` nuevo.
- Errores (claves i18n): `SEED_ERR_SCHEMA` (no hay esquema para ese `ESC`/`GEN`), `SEED_ERR_PARAMS` (texto mal formado o que no cabe en el esquema), `SEED_ERR_PARAM_UNKNOWN`, `SEED_ERR_PARAM_TYPE`, `SEED_ERR_PARAM_RANGE`, `SEED_ERR_PARAM_ENUM` (con `{param}`).
- Al analizar: primero la estructura necesaria para calcular el control (7 partes, versión, `SIS`, `ESC`, `G`+dígitos, caracteres Base32 válidos), luego el **control antes que el contenido**: si no cuadra, lo probable es una errata (`SEED_ERR_CHECK`); si cuadra y falla el contenido, el código es de otra versión o no canónico.

| Campo | Contenido |
|-------|-----------|
| `RPGM1` | Versión del formato de código |
| `SIS` | Sistema, 3-4 caracteres Crockford: `DND5`, `PF2E`, `GEN` (genérico) |
| `ESC` | Escala: `MUN`, `REG`, `ALD` (asentamiento), `EDI`, `EST`, `MAZ` |
| `GEN` | Versión del algoritmo del generador de esa escala (`G1`, `G2`…) |
| `PARAMS` | Parámetros iniciales con codificación **posicional por esquema del generador** (base mixta) en **Base32 Crockford**; `0` = todo por defecto |
| `SEED` | Hasta 64 bits en Base32 Crockford, sin ceros a la izquierda (8 caracteres las de la app) |
| `CRC` | Carácter de control Crockford calculado en GF(32) para detectar erratas |

Reglas:
- Cambiar un algoritmo **obliga a subir `GEN`** y mantener el anterior en `core/gen/<escala>/legacy/` para que las semillas antiguas sigan funcionando.
- El sistema de juego forma parte de la semilla porque cambia escalas (tamaño de casilla, tamaños de criatura, distancias por defecto).

### 5.4 Pruebas de determinismo ("seeds doradas")
`tests/golden/` contiene pares `código de semilla → hash SHA-256 del MapDocument canónico`. CI falla si alguno cambia sin subir `GEN`. Se ejecutan en escritorio y en la exportación web (headless con navegador).

Formato (ADR 021): `project/tests/golden/golden_seeds.txt`, una línea `<código RPGM1 canónico> <sha256>` por seed (`#` = comentario). El hash es `MapDocument.content_hash()` (sin tokens, niebla ni deltas). `test_golden_seeds.gd` genera cada código dos veces (detecta no determinismo) y compara. Para añadir seeds se escribe solo el código y se graba con `RPGM_GOLDEN_RECORD=1` (`$env:RPGM_GOLDEN_RECORD="1"; pwsh tools/run_tests.ps1 -Dir res://tests/golden`): solo se rellenan las líneas sin hash; las existentes nunca se reescriben. Sin la variable, una línea sin hash hace fallar el test.

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
- **Estilos culturales** (ADR 015): datos en `data/styles/<id>.json` (materiales, formas de planta, tejados, mobiliario y pesos de tipos de edificio). La v1 incluye **humano, enano y élfico**; añadir otro es solo añadir datos. El estilo es un parámetro del código de semilla de `ALD`, `EDI` y `EST`.

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

Implementación (F1): cada edición es un `MapCommand` (con deshacer) que, al aplicarse, añade un `MapDelta {op, data}` a `MapDocument.deltas`; `data` solo admite valores de `CanonicalJson` (enteros, textos, booleanos, listas, diccionarios). Al cargar un mapa se regenera desde el código y se reaplican los deltas en orden. Los deltas, los tokens y la niebla son **sesión**: no cambian `content_hash()`.

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
- **Rejilla hexagonal en todas las escalas** (ADR 012): opcional también en mapas tácticos (estancia, mazmorra, edificio), además de región y mundo. La geometría (vecinos, distancias, diagonales, plantillas de área, tamaños de token, línea de visión) se abstrae tras una interfaz de rejilla con implementaciones cuadrada y hexagonal; los perfiles indican el coste por paso en cada tipo de rejilla.
- Exportación: PNG con rejilla a resolución conocida (px por casilla) desde F1. **Impresión a escala real** (1 casilla = 1 pulgada / 25 mm, PDF por páginas A4/Carta con marcas de unión) antes de la v1, no en F1 (ADR 014).
- Intercambio con otras mesas virtuales (ADR 013): importar/exportar **Universal VTT** (`.uvtt` / `.dd2vtt`: imagen, rejilla, muros, puertas, luces) en F3. Foundry VTT y otros, después de la v1.

## 8. Perfiles de sistema de juego

Cada sistema es un **perfil de datos** (`data/systems/<id>.json`), no código. La lógica común lee el perfil.

| Concepto | D&D 5e (2024) | Pathfinder 2e |
|----------|---------------|---------------|
| Casilla | 5 ft | 5 ft |
| Diagonal | 5 ft por casilla (opción: alterna 5/10) | Alterna 5/10 |
| Velocidad típica | 30 ft | 25 ft |
| Terreno difícil | Coste ×2 | Coste +5 ft por casilla |
| Tamaños | Diminuto 2,5 ft · Pequeño/Mediano 5 · Grande 10 · Enorme 15 · Gargantuesco 20 | Igual que 5e |

**Medida por bandas** (`grid.measure = "bands"`): mecanismo genérico para perfiles propios o de la mesa. Cada banda tiene un máximo en casillas (la última puede ser ilimitada); la regla de medir muestra la **banda** y, opcionalmente, la distancia. El terreno difícil puede ser solo visual (`visual_only`) y los tamaños pueden no ocupar casillas (`sizes_occupy_cells = false`). No se distribuye ningún perfil de terceros con bandas (ADR 011).

**Coste por tipo de paso** (ADR 020): ortogonal = `cell_ft`; diagonal = `movement.diagonal_ft` (o una variante de mesa); hex = `movement.hex_step_ft` (5 ft en 5e y PF2e). Cada tipo lleva su propio contador del patrón cíclico. El terreno difícil se aplica al paso que **entra** en la casilla. En la cuadrada, `movement.diagonal_corner_rule` decide si un paso diagonal junto a una esquina exige uno (`any_side_free`, 5e y PF2e) o los dos rodeos ortogonales libres (`both_sides_free`). Las puertas cerradas sin llave no bloquean el movimiento; con llave, los muros y las secretas sin descubrir, sí.

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
| Cliente web (ADR 016) | **Por defecto lo sirve la app del DM** por HTTPS en el mismo puerto y origen que el WSS (sin infraestructura extra; certificado autofirmado o del usuario). **Alternativa: imagen Docker** (p. ej. en el NAS) que sirve el cliente estático y hace de proxy inverso hacia el WSS del DM, con certificado propio. En ambos casos, mismo origen para evitar problemas de certificados y contenido mixto |
| LAN | Conexión directa `wss://<ip-o-nombre>:<puerto>` |
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
| `*.uvtt` / `*.dd2vtt` | Universal VTT: importación y exportación (F3) |
| `data/systems/*.json` | Perfiles de sistema |
| `data/styles/*.json` | Estilos arquitectónicos por cultura |
| `data/packs/<pack>/` | Paquetes de contenido, cada uno con su `LICENSE` y `ATTRIBUTION.md` |
| `data/schemas/map_document.schema.json` | Forma canónica de `MapDocument` (caché, red, hash); no es el formato de guardado, que es seed + deltas |
| `tests/golden/golden_seeds.txt` | Seeds doradas: `<código> <sha256>` por línea (§5.4) |

Todos los JSON tienen `schema_version` y esquema en `data/schemas/`. Migraciones de esquema en `core/migrations/`.

## 13. Licencias y contenido

- **Código**: GPL-3.0-or-later (`LICENSE`).
- **Contenido de reglas**, solo abierto y en paquetes separados del código:
  - D&D: **SRD 5.2.x** bajo **CC-BY-4.0**, con la atribución exigida.
  - Pathfinder 2e: mecánicas de *Pathfinder Player Core* bajo **ORC License** (texto final registrado TX 9-307-067; irrevocable, cualquier medio y formato, software incluido). El **aviso ORC** completo (ORC Notice, Attribution con diseñadores y autores tal como Paizo pide, Reserved Material, Expressly Designated Licensed Material) va en `content.attribution` de `pf2e.json` y debe mostrarse en la pantalla de créditos y en `NOTICE.md`.
  - Convivencia ORC + GPL: la ORC obliga a ofrecer bajo ORC el *Adapted Licensed Material*, que se limita a las expresiones de mecánicas de juego (definición I.a y I.e.2); el código no lo es. Por eso `pf2e.json` se distribuye **bajo ORC, no bajo GPL**, y no se le puede imponer ninguna condición extra (II.b). Lo mismo aplica a cualquier perfil derivado de él.
  - Daggerheart: **descartado** (ADR 011). La DPCGL 2.0 (5-8-2026) solo permite impresión, streaming, pódcast y VTT de una lista blanca sin monetizar; excluye expresamente los videojuegos y "cualquier otro medio audiovisual no permitido expresamente", Darrington puede modificarla unilateralmente y exige indemnización y renuncia de reclamaciones. Un software GPL descargable no encaja.
- Marcas: ninguna licencia de contenido cubre marcas (ORC: Reserved Material; SRD 5.2: no licencia "Dungeons & Dragons"). No usar logotipos ni nombres comerciales como marca del producto; solo uso descriptivo tipo "compatible con 5e (SRD 5.2)" / "compatible con Pathfinder 2e", con aviso de no afiliación.

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
| **F1 – Mazmorra y estancia 2D** | Generadores `MAZ` y `EST`, vista 2D (rejilla cuadrada y hexagonal), tokens 2D, movimiento con coste, medición, exportación PNG | 20 seeds doradas estables; movimiento correcto en los 2 sistemas y en un perfil de bandas, en ambas rejillas |
| **F2 – Vista 3D y 1ª persona** | Renderizado 3D cenital y 1ª persona del mismo modelo; línea de visión y luces | Cambio de vista < 500 ms; FoW coherente entre vistas |
| **F3 – Edificio y asentamiento** | `EDI`, `ALD`, varias plantas, navegación jerárquica (aldea → edificio → estancia), estilos humano/enano/élfico, Universal VTT | Regenerar una estancia aislada desde su código da el mismo resultado que dentro de la aldea |
| **F4 – Red** | Servidor WSS en DM, cliente web, permisos, FoW filtrada | 8 clientes en LAN, latencia < 150 ms |
| **F5 – Personajes** | Diseñador 2D/3D modular, importación CSV/JSON | Crear un personaje y verlo en las 3 vistas |
| **F6 – Mundo y región** | `MUN`, `REG`, hexcrawl, impresión a escala real (PDF por páginas) | Mundo 2048×1024 en < 10 s |
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
| 008 | `tests/` y `data/` dentro de `project/` | Godot no carga ni exporta nada fuera de `res://` (`res://../tests` falla en GUT); los perfiles deben ir en la build | Mantenerlos en la raíz con enlaces simbólicos (frágil en Windows y CI) |
| 009 | Formato RPGM1 (implementado; revisado 2026-11-24): `SEED` de **longitud variable** sin ceros a la izquierda (`0` = semilla 0, hasta 13 car.; la app genera semillas de 40 bits = 8 car.); `SIS` en alfabeto Crockford; `PARAMS` **posicional por esquema del generador** (`ParamSchema` por `ESC`+`GEN`: campos ordenados entero `[min,max]` / booleano / enumerado cerrado con `capacity`, cada uno con defecto), codificado como entero de base mixta de dígitos relativos al defecto, primer campo menos significativo, en Base32 Crockford sin ceros a la izquierda (`0` = todo por defecto); control de **un carácter Crockford calculado en GF(32)** (x⁵+x²+1, Horner, escala como un símbolo y separador 0 entre campos), comprobado antes que el contenido. Ej.: `RPGM1-DND5-MAZ-G1-FA8-3QV8M2KD-P`. Detalle en §5.3 | Corto y fácil de dictar (decisiones de Víctor, 2026-11-24): 4 parámetros = 3 caracteres, código de 32; los defectos del final no ocupan nada sin necesidad de marcas; texto único por valores; añadir campos al final o ids dentro de `capacity` no rompe códigos; 40 bits bastan para semillas aleatorias de la app y se admiten cortas a mano; el control no usa I/L/O/U (confundibles al dictar) y en GF(32) detecta el 100 % de sustituciones simples y transposiciones adyacentes (verificado exhaustivamente), además de guiones corridos entre campos variables | Texto canónico `clave=<i\|b\|s><valor>` en Base32 (~70 car. solo `PARAMS`); compresión deflate; marcas de presencia por campo; `SEED` fija de 13 car.; control ISO/IEC 7064 MOD 37,36 (usaba 0-9A-Z: O/0 e I/1/L distintos); ISO 7064 sobre 32 símbolos (MOD 31 no distingue 2 símbolos; híbrido MOD 33,32 exige M+1 primo) |
| 010 | Unidades: mm enteros; convención 1 ft = 300 mm y 1 mi = 10/6 km; exacta 1 ft = 304,8 mm. Tamaños en décimas de pie (`space_ft_x10`) | Sin floats en el modelo; 2,5 ft no es entero en pies | Guardar floats en metros |
| 011 | Licencias de reglas: se **descarta Daggerheart** (DPCGL); PF2e se mantiene bajo ORC con `pf2e.json` licenciado ORC (no GPL) y aviso ORC completo; el modo `bands` queda como mecanismo genérico | DPCGL 2.0 no permite software/videojuegos fuera de VTT de lista blanca no comerciales y es revocable/modificable; ORC es irrevocable, cubre todo medio y su copyleft se limita a las mecánicas | Pedir permiso a Darrington Press; perfil Daggerheart descargable aparte (sigue sin ser un formato permitido) |
| 012 | Rejilla hexagonal opcional **en todas las escalas**, también táctica; geometría tras una interfaz de rejilla (cuadrada/hex) | Lo pide Víctor; muchas mesas juegan en hex | Hex solo en región/mundo |
| 013 | Intercambio con otras VTT: **Universal VTT** (`.uvtt`/`.dd2vtt`) en F3; Foundry y otros después de v1 | Formato abierto, sencillo y muy extendido; el de Foundry cambia entre versiones mayores | Foundry en v1; solo exportar |
| 014 | Impresión a escala real (PDF por páginas) antes de v1, no en F1; F1 exporta PNG a px/casilla conocidos | Godot no genera PDF de forma nativa; F1 debe centrarse en generadores | Impresión desde F1; solo PNG |
| 015 | Estilos arquitectónicos como datos (`data/styles/`); v1 con humano, enano y élfico | Lo pide Víctor; como datos, añadir culturas no toca código | Un único estilo genérico en v1 |
| 016 | Cliente web servido **por la app del DM** (por defecto, mismo origen que el WSS) y **imagen Docker** como alternativa (NAS) | Sin infraestructura obligatoria; Docker para quien ya tiene NAS y certificado propio | Solo NAS; web estática pública (contenido mixto y certificados autofirmados) |
| 017 | Geometría de rejilla (F1): interfaz `GridGeometry` + `SquareGrid` / `HexGrid`; coordenadas guardadas `(columna, fila)` enteras en el rectángulo `w×h` (hex: offset **odd-q** en `hex_flat`, **odd-r** en `hex_pointy`; cálculos en axiales); vecinos en orden fijo (cuadrada: N, E, S, W, NE, SE, SW, NW; hex: horario desde arriba, opuesta = d+3); línea entera por muestreo del segmento (hex: cúbicas escaladas por 8N con empujón (1, 2, −3), sin empates) y **simétrica** (se calcula desde el extremo menor); tamaño de casilla en píxeles = distancia entre centros (lado plano a lado plano en hex); conversión a píxel en float **solo para vistas** | Mismo almacenamiento rectangular en las tres rejillas (capas como arrays por filas, mismo `TileMapLayer` apilado); axiales simplifican distancia y vecinos; el orden fijo y la aritmética entera hacen deterministas generadores y LoS; la simetría evita que A vea a B y B no vea a A; "1 casilla = 1 pulgada" vale igual en hex | Guardar axiales (el rectángulo deja de ser un rectángulo en memoria); doubled coordinates; Bresenham asimétrico; línea con float y épsilon |
| 018 | Muros: modelo **híbrido**. Terreno **por casilla** (`VOID`/`WALL` macizos para roca y muros gruesos) + **aristas** para muros finos, **puertas (siempre en arista)** y vanos. Arista = (casilla dueña, lado canónico) con id entero; valor = tipo + banderas (abierta, con llave, descubierta) | Las cuevas por autómatas y la roca de una mazmorra son naturalmente por casilla; los edificios (F3), Universal VTT (segmentos de muro y puertas) y el 3D de F2 (módulos de pared y puerta colocados en el borde) son por arista; en hex las aristas existen igual (6 lados) y en la cuadrada las diagonales no tienen arista (cruzan por vértice, regla de esquina en el perfil). Una puerta en arista se abre/cierra sin ocupar casilla | Solo casillas (la puerta ocupa una casilla; muros finos imposibles; exportar a UVTT exige vectorizar); solo aristas (la roca maciza y las cuevas quedan como miles de aristas; el 3D pierde volúmenes) |
| 019 | `MapDocument` canónico: procedencia + rejilla + niveles (`MapLevel`, misma rejilla en todas las plantas) + sesión. Objetos con **propiedades de juego copiadas** del catálogo; ids de un contador único del documento. Serialización **JSON canónica propia** (`CanonicalJson`: claves ordenadas, solo enteros, escape fijo) y dos hashes: `content_hash()` (sin sesión; seeds doradas) y `full_hash()` | Las vistas y la red necesitan un único modelo; copiar las propiedades hace el documento autosuficiente y editable por instancia (y un cambio de catálogo se ve en el hash, como debe); tokens, niebla y deltas son estado de partida y no deben romper las seeds doradas; `JSON.stringify` del motor puede cambiar formato de números o escapes entre versiones | Referenciar el catálogo sin copiar; un documento por planta; `JSON.stringify(sort_keys)`; `var_to_bytes` (binario dependiente de la versión) |
| 020 | Coste de movimiento por **tipo de paso** como datos: ortogonal = `cell_ft`, diagonal = `diagonal_ft`, hex = `movement.hex_step_ft` (nuevo, requerido); contador independiente por tipo; terreno difícil por casilla de **destino**; `movement.diagonal_corner_rule` (nuevo, requerido: `any_side_free` en 5e y PF2e). Búsqueda de ruta Dijkstra con la **fase del patrón** en el estado (exacta con 5/10). Puertas cerradas sin llave no bloquean; con llave, muros y secretas sin descubrir, sí | Reglas como datos sin `if hex` en el coste; las dos SRD no prohíben cortar esquinas, pero muchas mesas sí (dato); con la fase en el estado la ruta más barata es exacta en PF2e; el aviso de velocidad (§10.3) necesita coste fiable | Distancia hex calculada aparte; "no cortar esquinas" fijo en código; A* con heurística (con patrones alternos la admisibilidad es delicada y el mapa táctico es pequeño) |
| 021 | Seeds doradas en `tests/golden/golden_seeds.txt` (`<código> <sha256>` por línea, comentarios con `#`); modo grabación por variable de entorno `RPGM_GOLDEN_RECORD=1` que **solo rellena líneas sin hash**; sin ella, una línea sin hash falla; cada código se genera dos veces | Texto plano: diff legible, añadir es añadir una línea; la variable de entorno no requiere tocar GUT ni los scripts; nunca se reescribe un hash existente (CLAUDE.md §2) | JSON (diffs ruidosos, reescritura completa); argumento de línea de comandos (GUT no los pasa de forma uniforme); regenerar todo con un flag (permitiría "arreglar" una seed rota sin subir `GEN`) |

## 18. Riesgos

| Riesgo | Impacto | Mitigación |
|--------|---------|------------|
| Divergencia de floats entre escritorio y WebAssembly | Rompe la reproducibilidad | Aritmética entera/cuantizada + seeds doradas en web |
| Rendimiento 3D en navegador | Cliente web lento | Web usa vista 2D por defecto; 3D con LOD y Compatibility |
| Certificados TLS en LAN | Jugadores no conectan | Mismo origen vía proxy inverso; guía de despliegue |
| Licencias de contenido | Problemas legales | Paquetes separados, atribuciones, revisión antes de publicar |
| Alcance excesivo | Proyecto sin terminar | Fases con criterio de aceptación; F1 ya es usable en mesa |

## 19. Preguntas abiertas

Ninguna por ahora. Resueltas el 2026-11-24: hex táctico (ADR 012), cliente web (ADR 016), importadores (ADR 013), impresión a escala (ADR 014), estilos culturales (ADR 015).
