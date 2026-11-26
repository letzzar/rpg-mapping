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
| Red | WSS propio sobre `TCPServer` + `StreamPeerTLS` (mismo puerto que el HTTPS del cliente web) y mensajes JSON comprimidos; ADR 031 (sustituye a `WebSocketMultiplayerPeer` + RPC) |
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
- **`core/model/`**: `MapDocument` = procedencia (código RPGM1, escala, `GEN`) + rejilla + `levels: Array[MapLevel]` (todas las plantas con la misma rejilla) + sesión (tokens, niebla por nivel, deltas). Cada `MapLevel` tiene capas por casilla (`terrain`, `room_ids`), aristas dispersas (`MapEdge`: muros finos, puertas, vanos y, desde F3, ventanas), salas (`MapRoom`), objetos (`MapObject`, propiedades de juego copiadas del catálogo), escaleras (`MapStair`), trampas (`MapTrap`) y, desde F3 (ALD), mapas hijos (`MapChild`: código RPGM1 de un edificio anclado en su huella, ADR 027). Ids estables de un contador único del documento.
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
| `GEN` | Versión del algoritmo del generador de esa escala (`G1`, `G2`…). Varias pueden convivir con sentidos distintos: `EST-G1` es una estancia aislada, `EST-G2` la estancia de un edificio (ADR 029) y `EST-G3` la estancia en blanco del editor (§6.5) |
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

**ALD G1** (`core/gen/ald/`, ADR 027; esquema y datos aprobados por Víctor el 2026-11-25 y congelados con 8 seeds doradas, más la de la taberna hija como EDI):

| # | Campo | Tipo / rango | Defecto | Significado |
|---|-------|--------------|---------|-------------|
| 0 | `size` | `hamlet`, `village`, `town`, `city` (capacity 8) | `village` | Caserío 72×56 (5-8 edificios), aldea 104×80 (12-18), pueblo 160×124 (28-38), ciudad 212×164 (60-80); calles, plaza y obligatorios en `data/settlements/ald_settlement_types.json` |
| 1 | `grid` | `square`, `hex_flat`, `hex_pointy` (capacity 4) | `square` | Rejilla (ADR 012); la heredan los edificios |
| 2 | `style` | `human`, `dwarf`, `elf` (capacity 16) | `human` | ADR 015: bloque `settlement` del estilo (% de peso por tipo de edificio; calles más o menos sinuosas: 180/80/350 ‰) y estilo de los edificios hijos |
| 3 | `wall` | booleano | `false` | Muralla (terreno `WALL`) en el borde de la elipse con puertas donde la cruzan las calles principales |
| 4 | `water` | `none`, `river`, `coast` (capacity 8) | `none` | Río perpendicular a la calle principal (con puente) o costa paralela a ella |
| 5 | `prosperity` | `poor`, `average`, `rich` (capacity 8) | `average` | % de peso por tipo, tamaño EDI de los edificios (70/25/5, 40/45/15, 15/45/40 ‰ small/medium/large), sótanos (100/250/450 ‰) y `clutter` de los hijos (3/5/7) |
| 6 | `layout` | `organic`, `grid` (capacity 4) | `organic` | Calles por crecimiento orgánico o retícula (ciudad planificada) |

Ejemplos: `RPGM1-DND5-ALD-G1-0-H8DJRFAE-W` (aldea por defecto, 16 edificios), `RPGM1-DND5-ALD-G1-1G1-KCP3TKJZ-3` (pueblo con muralla y río, 34), `RPGM1-PF2E-ALD-G1-28HA-NGYMWQV0-1` (ciudad enana amurallada, rica, en retícula, hex plana), `RPGM1-DND5-ALD-G1-1T27-QN75YR3H-9` (caserío élfico pobre en la costa).

- **Escala**: 1 casilla = la casilla táctica del sistema (5 ft), la de EDI: la huella de cada edificio es la de su mapa EDI 1:1 (ADR 027). Por eso una "ciudad" de G1 es un barrio o ciudad pequeña (~60-80 edificios, ~290 habitantes).
- **Población** derivada (no es parámetro en G1): suma de `residents` de cada tipo de edificio colocado (casa 5, posada 4…). Un parámetro aparte duplicaría `size` y obligaría a rechazar combinaciones incoherentes.
- **Edificios = hijos EDI** (criterio de F3): el edificio de orden k tiene parámetros EDI (`building_spec`: tipo —los `required` del tamaño primero, luego por pesos tamaño × prosperidad × estilo—, tamaño, sótano, plantas, `clutter`) sacados solo de `fork("building", k)` y semilla `hash64(semilla, "EDI", k) & (2⁴⁰ − 1)` (40 bits como las de la app: el código mide lo mismo que uno aleatorio). Su código `RPGM1-<SIS>-EDI-G1-…` se guarda en el documento (`MapChild`). La huella es `EdiGeneratorG1.footprint_size()` y la puerta principal, la trasera y las ventanas salen de `EdiGeneratorG1.plan_ground_floor()` (la misma planta baja que genera EDI, sin amueblar): regenerar el código da exactamente el edificio que describe la aldea (test `test_child_code_regenerates_same_building`, 3 rejillas, ~45 edificios). Ningún código depende de otros edificios ni de muralla/agua/retícula (que solo cambian dónde va).
- **Mapa**: zonas (`MapRoom`) `field` (fuera), `garden` (huertos dentro), `street`, `plaza`, `bridge`, `gate`, `town_wall` (terreno `WALL`), y por edificio `yard` (parcela) y `building` (huella, con muro en arista en su contorno, puertas y ventanas de EDI); río/mar como agua profunda con orilla poco profunda. **`MapLevel.children`** (`MapChild`, nuevo): tipo, código, zona, `offset` (casilla de la aldea = casilla del hijo + offset en el nivel `child_level`), huella y casilla de entrada; se serializa solo si hay alguno (los hashes de MAZ/EST/EDI no cambian). Vista 2D: colores por zona, tejado y nombre del tipo; 3D: mismos colores, rótulo sobre cada edificio, sin techo en 1ª persona al aire libre.

Algoritmo (n casillas, b edificios, f casillas de fachada):
1. Mapa del tamaño, ampliado con muralla (×1,15), costa (el mar se añade al lado) o río (+ancho+4) para que la tierra edificable no cambie (sin esto, una ciudad amurallada en la costa colocaba el 54 % de sus edificios). Río serpenteante a un lado de la plaza o costa con orilla irregular. O(n).
2. Elipse del asentamiento (tierra adentro si hay costa); muralla en su borde (abierta donde pasa el agua); zona de calles = elipse (WALL_GAP por dentro de la muralla) lejos del agua; sin muralla, las parcelas pueden salir de la elipse junto a las calles (arrabales).
3. Plaza central y calles principales (una de borde a borde, con puente y puertas; otra perpendicular con `crossroads_permille`, que se detiene ante el agua). **Orgánico**: "caminantes" que avanzan por pasos de 4 vecinos en coordenadas offset (conexos en las tres rejillas) y se desvían una casilla con `turn_permille` del estilo; ramas perpendiculares cada `branch_every` (la primera también a esa distancia: si no, quedaban tiras paralelas de 2-3 casillas sin sitio para parcelas), de `branch_length`, en `branch_levels` niveles; una rama para al salir de la zona y se une al tocar otra calle (un desvío que la dejaría pegada a otra no se hace: formaba losas de 4-6 filas). **Retícula**: principales rectas y calles cada `grid_block`. Después se quita toda calle no alcanzable desde la plaza (BFS). O(n + longitud de calles).
4. Parcelación: fachadas libres junto a una calle o la plaza, ordenadas por distancia a la plaza + desempate 0-6. Los obligatorios primero y el resto de mayor a menor huella; cada uno en la primera fachada donde cabe huella + anillo de 1 (el anillo exterior del mapa EDI) + patio detrás, alineado a la calle y con la **paridad de la rejilla** (`translation_step`: en odd-q/odd-r la traslación debe ser par en x o en y para conservar los vecinos). Una fachada que falló con w×h no se prueba con otra parcela ≥ en los dos lados (medido: mismos edificios colocados, ciudades 3× más rápidas). Los que no caben se descartan.
5. Volcado: terreno, zonas, muros/puertas/ventanas de cada huella y un `MapChild` por edificio.

Garantía: la red de calles es una sola componente con la plaza (paso 3) y cada parcela es un rectángulo transitable que rodea la huella (anillo) y toca una calle, así que la puerta de todo edificio se alcanza desde la plaza a pie y sin agua (tests: BFS propio + `Connectivity` en 4 tamaños × 3 rejillas × estilos, muralla × agua × retícula × prosperidad; la muralla solo se cruza por sus puertas).

Coste medido (escritorio, test `test_stats_and_timing`, 36 asentamientos): caserío 34-47 ms, aldea 84-115 ms, pueblo 222-300 ms, ciudad 518-726 ms; peor caso 973 ms (ciudad amurallada con agua, hex); 100 % de los edificios intentados colocados en esas 36 (≥ 80 % exigido en los tests, todos los obligatorios). Construir la vista 3D de un pueblo amurallado con río (184×150): ~440 ms. Los interiores no se generan: solo huellas y códigos hijos (≈ 4 ms de planta baja EDI por edificio).

Limitaciones de G1: los edificios no se giran (EDI no tiene parámetro de orientación: todas las huellas son apaisadas como en EDI); solo edificios de la lista de EDI (sin mercado con puestos, pozos ni muelles); un río o una costa, no ambos; la muralla queda abierta donde la cruza el agua. La navegación aldea → edificio está en la UI desde la 8.ª sesión (§7, ADR 028).

### 6.4 Edificio (`EDI`)
- Planta(s) por **BSP + grafo de adyacencias** según tipo (una taberna exige sala común ↔ cocina ↔ almacén, habitaciones arriba).
- Puertas, ventanas, escaleras entre plantas, sótano opcional.

**EDI G1** (`core/gen/edi/`, ADR 026; esquema y datos aprobados por Víctor el 2026-11-25 y congelados con 8 seeds doradas):

| # | Campo | Tipo / rango | Defecto | Significado |
|---|-------|--------------|---------|-------------|
| 0 | `building_type` | `tavern`, `house`, `smithy`, `temple`, `shop`, `inn`, `guardhouse` (capacity 32) | `tavern` | Tipo de edificio (`data/buildings/edi_building_types.json`: estancias por planta, adyacencias, huellas, plantas por defecto) |
| 1 | `grid` | `square`, `hex_flat`, `hex_pointy` (capacity 4) | `square` | Rejilla (ADR 012) |
| 2 | `style` | `human`, `dwarf`, `elf` (capacity 16) | `human` | ADR 015: bloque `building` del estilo (% de la huella 100/115/100, % de ventanas 100/40/160) y mobiliario como en EST |
| 3 | `floors` | entero 0-4 | 0 | Plantas sobre el suelo; 0 = las del tipo (casa, herrería y templo 1; el resto 2) |
| 4 | `cellar` | booleano | `false` | Sótano bajo la planta baja |
| 5 | `size` | `auto`, `small`, `medium`, `large` (capacity 8) | `auto` | Huella del tipo (p. ej. taberna 10×7, 13×9, 16×11); `auto` = la típica del tipo |
| 6 | `clutter` | entero 0-10 | 5 | Mobiliario de cada estancia, como en EST |

Ejemplo: `RPGM1-DND5-EDI-G1-0-H8DJRFAE-3` (taberna de 2 plantas, todo por defecto).

- **Tipos como datos** (`data/buildings/edi_building_types.json`, esquema `edi_building_types.schema.json`): por tipo, `auto_size`, `floors`, `footprints` (small/medium/large), `upper_shrink_permille`, `window_permille`, `back_door_permille`, estancias especiales (`entrance`, `back_door`, `stairs_up`, `stairs_down`, todas de la planta baja), `rooms` (clave, tipo de estancia EST, planta `cellar`/`ground`/`upper`, peso de área, `hub`, `windows`; en orden de prioridad) y `adjacency` (pares de la misma planta que exigen puerta). Cada planta alta repite la lista `upper`. Tipos de estancia nuevos en EST para los edificios (al final del enumerado, dentro de capacity: ningún código EST cambia): `hall`, `living`, `shop`, `barracks`, `armory`, `cell`, `guardroom`.
- **Mapa**: huella rectangular (w×h) rodeada por un anillo de 1 casilla: en la planta baja es suelo exterior (zona `outside`, más `entrance` delante de la puerta principal y `exit` delante de la trasera); en las demás plantas, vacío. Niveles de abajo arriba: [sótano] + planta baja + plantas altas. **Todos los muros en arista** (también el exterior, ADR 018): permite ventanas, segmentos de Universal VTT sin vectorizar y módulos de pared en 3D.
- **Ventanas**: `MapEdge.KIND_WINDOW` (valor 5, nuevo): bloquea el paso y la conectividad, no la visión. 2D: muro con cristal claro; 3D: muro con hueco de 0,9 a 2,0 m.

Algoritmo por planta (semilla hija `fork("level", i)`):
1. Estancias de la planta en orden de prioridad con su peso de área; pares de adyacencia de esa planta.
2. **Distribución**. Con hub (pasillo/recibidor): **espina** de 1 casilla (2 si el lado corto ≥ 10) a lo largo del eje largo, que pasa por la escalera que llega de abajo; las demás estancias son rebanadas perpendiculares a cada lado (fondo ≥ 3, largo proporcional al área): todas tocan el hub. Sin hub: **BSP por pesos** (corte del lado largo en el prefijo de la lista de peso más parecido a la mitad, ±1 casilla, grupo en lado bajo o alto al azar), hasta 12 intentos hasta que todos los pares tengan puerta; si ninguno lo consigue, se añade un hub (`hall`) y se usa la espina (los pares se cumplen directos o a través del hub). Estancias que no caben (lado < 3): se descartan las últimas de la lista.
3. **Puertas**: principal en `entrance` hacia fuera, trasera opcional en `back_door`, una por par obligatorio, una de cada estancia al hub y, hasta que toda estancia se alcance desde la raíz (entrada o escalera que llega), una a una vecina alcanzada. Ninguna casilla a distancia ≤ 1 de otra puerta si se puede; si no, sin compartir casilla (compartirla solo como último recurso de conectividad; no ocurrió en 630 edificios de prueba). Nunca en una escalera.
4. **Ventanas** en aristas exteriores (no en el sótano ni en estancias `windows: false`): ≈ aristas × `window_permille` × `window_pct`/100 / 1000, separadas de puertas y entre sí.
5. **Escaleras** (`MapStair`, la misma casilla en las dos plantas): de `stairs_up` (o del hub en plantas altas) a la planta de arriba, dentro de su huella, prefiriendo contra una pared y en una fila que deje a la espina de arriba dos lados (con la escalera pegada al borde la posada perdía 2 de 6 dormitorios: estancias descartadas 21 → 6 de 480 en 84 edificios); al sótano desde `stairs_down`. Las plantas altas pueden recortar un extremo del eje largo (`upper_shrink_permille`).
6. **Mobiliario**: cada estancia con `EstFurnisherG1.furnish` (entradas = sus casillas de puerta y escalera) y `Rng.new(hash64(semilla, "EST", nivel × 256 + orden)).fork("furnish", 0)` (`EdiGeneratorG1.room_seed`), el mismo Rng con el que EST G1 amueblaría una estancia aislada de esa semilla.

Garantía: la partición del rectángulo es conexa y el paso 3 une cada estancia a la raíz; las escaleras unen las plantas, así que toda casilla transitable se alcanza desde la entrada (`Connectivity`; tests con 7 tipos × 3 rejillas × estilos, plantas y sótano, más una prueba de 630 edificios sin fallos). Coste medido: ≈ 46 ms por edificio por defecto y ≈ 97 ms con hasta 4 plantas y sótano (domina el amueblado, O(objetos × casillas) por estancia); la distribución es O(intentos × (casillas + puertas²)).

**Estancia de un edificio frente a EST aislada**: una estancia de EDI no es exactamente una EST aislada: su forma la da la partición (cualquier w×h ≥ 3, no los tamaños 6×5/9×7/13×10), sus puertas las pone el edificio y no tiene anillo de muro ni rellanos. Lo que sí se conserva es la **fuente de azar**: con `RPGM1-<SIS>-EST-G1-<room_type, grid, style, clutter>-<room_seed>` se obtiene el mismo tipo, estilo y semilla, pero otra forma. Regenerar una estancia del edificio sin regenerar las demás sí es exacto (test `test_room_furniture_depends_only_on_child_seed`). Para el criterio de F3 ("aislada = dentro de la aldea") Víctor eligió un **código de estancia de edificio**: **EST G2** (§6.5, ADR 029), que apunta al edificio y a la estancia y la extrae exacta. EDI G1 no cambia: `generate_building()` es ahora `plan_building()` (todo menos el mobiliario) + `furnish_room()` de cada estancia, con las mismas llamadas en el mismo orden (las 37 seeds doradas siguen iguales).

### 6.5 Estancia (`EST`) y objetos
- Colocación de mobiliario por reglas con etiquetas: `contra_pared`, `centro`, `junto_a:hogar`, `pasillo_libre ≥ 1 casilla`.
- Cada objeto tiene propiedades de juego: **cobertura** (media/tres cuartos/total), **terreno difícil**, **bloquea visión**, **fuente de luz** (radio brillante/tenue), **interactuable** (cofre, palanca), **altura** (para 3D y línea de visión).
- Catálogo de objetos en `data/objects/*.json`, ampliable por el usuario.

**EST G1** (`core/gen/est/`, ADR 023; esquema aprobado y congelado con 9 seeds doradas):

| # | Campo | Tipo / rango | Defecto | Significado |
|---|-------|--------------|---------|-------------|
| 0 | `room_type` | `tavern`, `bedroom`, `storage`, `temple`, `library`, `kitchen`, `forge`, `crypt` y, añadidos al final en F3 (EDI), `hall`, `living`, `shop`, `barracks`, `armory`, `cell`, `guardroom` (capacity 32) | `tavern` | Tipo de estancia (`data/rooms/est_room_types.json`: objetos obligatorios y opcionales con peso y máximo) |
| 1 | `grid` | `square`, `hex_flat`, `hex_pointy` (capacity 4) | `square` | Rejilla (ADR 012) |
| 2 | `size` | `auto`, `small` 6×5, `medium` 9×7, `large` 13×10 (capacity 8) | `auto` | Interior; `auto` = el típico del tipo (taberna y templo large; dormitorio y almacén small; el resto medium) |
| 3 | `style` | `human`, `dwarf`, `elf` (capacity 16) | `human` | ADR 015: materiales y % de peso del mobiliario (`data/styles/<id>.json`) |
| 4 | `shape` | `rect`, `l_shape` (capacity 4) | `rect` | La L recorta un rectángulo de w/2 × h/2 en una esquina al azar |
| 5 | `doors` | entero 1-4 | 1 | Puertas (las que quepan sin juntarse; al menos una) |
| 6 | `clutter` | entero 0-10 | 5 | Objetos opcionales ≈ casillas × clutter / 40 |

- **Mapa**: interior rodeado de un anillo de muro macizo. Cada puerta es una arista entre una casilla de la estancia (la **entrada**) y una del anillo que pasa a suelo (el **rellano**; la primera es la zona `entrance`, las demás `exit`). Las otras aristas entre el rellano y la estancia llevan muro fino. La zona de la estancia tiene como tipo el `room_type`.
- **Catálogo** (`data/objects/core.json`, 32 objetos propios, esquema `object_catalog.schema.json`): tamaño, etiquetas, clase de material y propiedades de juego. Los objetos colocados copian sus propiedades (`MapObject`, ADR 019) y el material que da el estilo (`MapObject.material`).
- **Etiquetas**: `against_wall` (contra_pared: alguna casilla tiene la pared a la espalda), `center` (centro: ninguna casilla toca la pared), `near:<id>` (junto_a: a distancia 1 de un objeto `<id>` ya colocado). El **pasillo libre ≥ 1** es una regla global: un objeto que bloquea solo se acepta si todas las casillas libres siguen conectadas entre sí y con las entradas, y si todo interactuable tiene una casilla libre alcanzable en su huella o al lado. Ningún objeto se coloca en una casilla de entrada.
- **Amueblado reutilizable**: `EstFurnisherG1.furnish(doc, nivel, casillas, entradas, tipo, estilo, clutter, rng)` amuebla cualquier recinto (EDI en F3). `EstGeneratorG1.generate_room(params, rng)` genera la estancia entera a partir de un Rng: aislada, `Rng.new(semilla)`; como hija de un edificio, `Rng.new(hash64(semilla_edificio, "EST", id))` (§5.2, criterio de F3, ya probado).
- Coste: O(objetos × (casillas × orientaciones + 16 intentos × casillas)).

**EST G2 — estancia de un edificio** (`core/gen/est/est_generator_g2.gd`, ADR 029; **esquema aprobado por Víctor el 2026-11-25 y congelado con 8 seeds doradas**). No sustituye a EST G1 (estancia aislada, que sigue igual y es la que genera la app al azar): es otro generador de la misma escala, registrado a la vez. `SEED` = la semilla del edificio; `PARAMS`:

| # | Campo | Tipo / rango | Defecto | Significado |
|---|-------|--------------|---------|-------------|
| 0-6 | `building_type`, `grid`, `style`, `floors`, `cellar`, `size`, `clutter` | los de EDI G1 (mismo orden, rangos, ids, capacity y defectos) | los de EDI G1 | El edificio EDI G1: el código del edificio es el mismo `PARAMS` sin los dos últimos campos y la misma `SEED` |
| 7 | `level` | entero 0-7 | 0 | Nivel del edificio (índice del documento EDI: 0 = sótano si lo hay; si no, planta baja) |
| 8 | `room` | entero 0-63 | 0 | Orden de la estancia en la lista de su planta (el de `room_seed`: id = `level` × 256 + `room`; el hub de reserva va al final) |

Ejemplos (estancias de la taberna `RPGM1-DND5-EDI-G1-Y00-BC23VGX8-T`, hija de la aldea `RPGM1-DND5-ALD-G1-0-H8DJRFAE-W`): `RPGM1-DND5-EST-G2-1QY00-BC23VGX8-9` (sala común, nivel 1, estancia 0), `RPGM1-DND5-EST-G2-FFY00-BC23VGX8-P` (cocina, nivel 1, estancia 1), `RPGM1-DND5-EST-G2-H6Y00-BC23VGX8-5` (dormitorio, nivel 2, estancia 1). El `PARAMS` del edificio (`Y00`) queda como sufijo porque el primer campo es el dígito menos significativo.

Algoritmo (puro, determinista):
1. `EdiGeneratorG1.plan_building(params EDI, Rng.new(semilla))`: el edificio sin mobiliario, idéntico al que `generate_building()` tiene antes de amueblar.
2. `EdiGeneratorG1.furnish_room()` **solo** de la estancia pedida (misma semilla hija `room_seed`): mismos objetos que en el edificio completo, porque `EstFurnisherG1` solo lee las casillas de su estancia y las aristas entre ellas, nunca los objetos de otras (cambian solo los ids).
3. **Extracción por traslación**: ventana = rectángulo de la estancia + **anillo de 1 casilla**; el origen (`offset`) se redondea hacia abajo al paso de traslación de la rejilla (`translation_step`: x par en hex odd-q, y par en odd-r; en hex puede quedar una columna o fila más de anillo a la izquierda o arriba). Casilla del edificio = casilla de la estancia + `offset`. Se copian terreno y zona (`MapRoom` con el mismo tipo) de toda la ventana, todas las aristas con las dos casillas dentro (muros, puertas y ventanas con sus banderas), los objetos de la estancia y sus escaleras con **`to_level` relativo** (−1 baja, +1 sube: el documento tiene un nivel y la escalera "sale del mapa", como un `to_cell` fuera de él). Ids nuevos en orden: zonas, escaleras, objetos (cada grupo en el orden del edificio). No se copian objetos ni escaleras de las estancias vecinas: el anillo es contexto (qué hay tras cada puerta o ventana y suelo para salir), no zona de juego.

Garantía: las casillas, aristas, objetos (tipo, posición, orientación, material, propiedades) y escaleras de la estancia son exactamente las del edificio trasladadas por `offset` (por construcción; `test_est_g2.gd` lo comprueba casilla a casilla, arista a arista y objeto a objeto en 21 edificios de los 7 tipos × 3 rejillas con sótanos y varias plantas —168 estancias—, en las 8 seeds doradas de EDI y en la cadena ALD → código EDI hijo → código de estancia, donde además los muros, puertas y ventanas exteriores coinciden con los del mapa de la aldea: el criterio de F3).

Estancias navegables: **todas las que EDI amuebla**, también el pasillo/recibidor (`hub`; `RoomRef.hub` permite a la UI tratarlo aparte); el exterior (`outside`, `entrance`, `exit`) no. Un nivel o una estancia que el edificio no tiene (o que se descartó por no caber) da `SEED_ERR_ROOM_LEVEL` / `SEED_ERR_ROOM` (el registro admite un "explicador" opcional por generador que solo se llama si falla).

Funciones para la navegación edificio ↔ estancia (`EstGeneratorG2`; EDI G1 no guarda hijos en su documento porque está congelado: la relación se deriva al vuelo): `rooms_of(edi_code)`, `room_at(edi_code, nivel, casilla)`, `room_code(edi_code, nivel, orden)`, `building_code(est_code)`, `ref_of(est_code)`; `RoomRef` da `level`, `order`, `kind`, `hub`, `rect`, `offset`, `map_size`, `entry` (casilla junto a su primera puerta), conversiones de casillas y `to_map_child()` para `MapNavigator`.

Coste medido (escritorio): una estancia 8-13 ms de media (peor 21 ms) frente a 31-48 ms del edificio entero por defecto; posada hex de 2 plantas: 33 ms de media frente a 154 ms. `rooms_of` (distribución sin muebles) 6-9 ms por defecto, 20-35 ms en la posada hex.

**EST G3 — estancia en blanco** (`core/gen/est/est_generator_g3.gd`; base del editor de estancias E2, §6.7; **esquema propuesto, pendiente de aprobar**, con 6 seeds doradas). Tercer generador de la escala, registrado junto a G1 y G2 (no los sustituye). Una estancia hecha a mano es **código EST G3 + deltas** (lo que usará E3 para el id corto y el código para compartir). `PARAMS`:

| # | Campo | Tipo / rango | Defecto | Significado |
|---|-------|--------------|---------|-------------|
| 0 | `width` | entero 3-48 | 9 | Ancho del interior en casillas (3: una casilla a cada lado de la puerta; 48: el ancho de un MAZ medium, 50×50 con el anillo) |
| 1 | `height` | entero 3-48 | 7 | Alto del interior (9×7 = el `medium` de EST G1) |
| 2 | `grid` | `square`, `hex_flat`, `hex_pointy` (capacity 4) | `square` | Rejilla (ADR 012) |
| 3 | `room_type` | `room` y, en su orden, los ids de EST G1 (`tavern` … `guardroom`) (capacity 64) | `room` | Tipo de la zona de la estancia (nombre y color en las vistas). `room` ("Sala", el de las salas de MAZ) es el defecto neutro: una estancia en blanco no es una taberna. Capacity 64 = las 32 de EST G1 + `room` + holgura |

Por qué `room_type` está en el código y no solo en un delta: crear "una cripta de 6×5" queda descrito por el código sin ninguna edición (código para compartir más corto, id corto igual al de cualquier otra cripta en blanco de ese tamaño), y al ir al final con defecto no ocupa nada si no se usa. Con todos los campos a cualquier valor, `PARAMS` ocupa como mucho 4 caracteres (46·46·4·64 < 32⁴). Renombrar o cambiar el tipo después sigue siendo un delta (§6.7).

**La semilla no se usa**: el generador no tiene azar y la salida solo depende de `PARAMS`. El código **canónico** que emite la app lleva la semilla 0, `RPGM1-<SIS>-EST-G3-<PARAMS>-0-<CRC>` (`EstGeneratorG3.canonical_code()`); un código con otra semilla es válido y da el mismo mapa, pero no es el canónico (para E3, el mismo contenido debe dar el mismo código).

Ejemplos: `RPGM1-DND5-EST-G3-0-0-B` (9×7 cuadrada, todo por defecto), `RPGM1-DND5-EST-G3-26H-0-G` (12×10 hex plana), `RPGM1-DND5-EST-G3-48N-0-G` (12×10 hex punta), `RPGM1-PF2E-EST-G3-288V-0-N` (cripta 6×5 hex punta).

Mapa (coherente con EST G1, para que se vea igual en 2D y 3D): (`width`+2)×(`height`+2); interior de suelo desde (1, 1) con una zona de tipo `room_type`; **anillo de muro macizo** (`Terrain.WALL`); **una puerta** en el centro de la pared de abajo: arista `KIND_DOOR` entre la casilla de entrada E = (1 + ⌊(`width`−1)/2⌋, `height`) y el rellano R = (E.x, `height`+1), que pasa a suelo con zona `KIND_ENTRANCE` (como la primera puerta de G1: las fichas nuevas salen junto a ella y es la raíz de la conectividad); las demás aristas entre R y la estancia (en hex R toca 2-3 casillas) llevan muro fino. (x, y+1) es vecina de (x, y) en las tres rejillas, así que la puerta existe siempre. Sin objetos, escaleras ni hijos; ids: estancia 1, entrada 2.

```
###########
#.........#
#.........#
#.........#      RPGM1-DND5-EST-G3-0-0-B
#.........#      (# muro, . suelo, E rellano de la entrada)
#.........#
#.........#
#.........#
#####E#####
```

Garantía: todo el suelo se alcanza desde la entrada (`Connectivity`; test `test_est_g3.gd` con todos los tamaños extremos y una malla de 16×10 tamaños en las tres rejillas). Coste O(`width`×`height`), sin Rng: ≈ 4 ms la de 48×48 (escritorio).

### 6.6 Mazmorra (`MAZ`)
- Tipos: construida (salas + pasillos por BSP / algoritmo de habitaciones y corredores), cueva (autómatas celulares), mixta. Opción **Wave Function Collapse** para teselas.
- Garantías: todas las salas accesibles desde la entrada, nº de salidas, ratio de pasillos, trampas y puertas secretas por densidad.

**MAZ G1** (`core/gen/maz/maz_generator_g1.gd`, ADR 022; esquema aprobado y congelado con 11 seeds doradas):

| # | Campo | Tipo / rango | Defecto | Significado |
|---|-------|--------------|---------|-------------|
| 0 | `rooms` | entero 1-64 | 12 | Salas por nivel (máximo; si no caben, las que quepan; las de escalera cuentan) |
| 1 | `layout` | `built`, `cave`, `mixed` (capacity 4) | `built` | Salas rectangulares, cuevas (autómata celular) o mezcla según el estilo |
| 2 | `grid` | `square`, `hex_flat`, `hex_pointy` (capacity 4) | `square` | Rejilla táctica (ADR 012) |
| 3 | `corridor_pct` | entero 0-100 | 30 | Pasillos extra (bucles) sobre el árbol mínimo, en % de (salas − 1) |
| 4 | `size` | `auto`, `small` 32×24, `medium` 48×36, `large` 64×48, `huge` 96×72 (capacity 8) | `auto` | `auto`: ≤ 6 salas small, ≤ 14 medium, ≤ 28 large, más huge |
| 5 | `exits` | entero 1-4 | 1 | Salidas al borde en el nivel 0; la primera es la entrada |
| 6 | `levels` | entero 1-8 | 1 | Niveles unidos por escaleras |
| 7 | `trap_density` | entero 0-10 | 3 | Trampas por cada 10 salas del nivel |
| 8 | `secret_door_density` | entero 0-10 | 2 | Puertas secretas por cada 10 salas del nivel (nunca la de una salida) |
| 9 | `style` | `human`, `dwarf`, `elf` (capacity 16) | `human` | ADR 015: tamaño de salas (3-7, 4-9, 3-6), radio de cueva (2-4, 2-3, 2-5) y ‰ de cuevas en `mixed` (500, 250, 750) |

Los cuatro primeros campos no cambian respecto a F0 (el ejemplo `RPGM1-DND5-MAZ-G1-FA8-3QV8M2KD-P` sigue siendo válido). `wfc_tiles` sale del esquema: cuando exista se añadirá **al final** como booleano con defecto `false`, sin cambiar ningún código emitido.

Algoritmo por nivel (semilla hija `fork("level", i)`; cada sala, pasillo, salida, puertas y trampas con su propio hijo):
1. **Salas forzadas** centradas en las casillas de escalera (la misma casilla en el nivel de arriba y en el de abajo). Las escaleras alternan mitad izquierda y derecha del mapa (≥ 7 columnas entre dos seguidas), así que sus salas nunca chocan.
2. **Salas** hasta `rooms` con `rooms × 30` intentos como máximo (contador determinista): rectángulo en coordenadas de la rejilla o cueva (autómata de mayoría con 3 pasos dentro de un círculo, núcleo de radio 1 fijo y componente conexa del centro). Cada sala reserva un margen de 1: dos salas nunca se tocan y ninguna toca el borde.
3. **Conexión**: árbol de expansión mínima (Prim) + bucles entre los pares más cercanos. Cada pasillo avanza por aristas reduciendo la distancia al destino (Manhattan en la cuadrada, hexagonal en hex; ninguna condición sobre el tipo de rejilla) y tiende a seguir recto; si se atasca, BFS. En `cave` los túneles se ensanchan.
4. **Salidas** (nivel 0): pasillo hasta una casilla del borde, sin esquinas ni salidas contiguas.
5. **Aristas**: entre casillas transitables de zonas distintas, cuando una es una sala construida o una salida, hay una **puerta donde la cruza un pasillo** (25 % vano, 12 % de las demás con llave) y un **muro fino** en el resto. Cuevas y pasillos se funden sin aristas.
6. **Secretas y trampas** por densidad, sin repetir casilla y nunca sobre una escalera.

Garantía: todos los pasillos son caminos por aristas y cada cambio de zona en ellos es una puerta o un vano. Todas las salas están en el árbol y las escaleras unen los niveles, así que toda casilla transitable se alcanza desde la entrada (`Connectivity`, comprobado en los tests con muchas semillas y en las tres rejillas). Coste aproximado: O(casillas + salas² + longitud de los pasillos) por nivel.

### 6.7 Edición manual
El DM puede pintar terreno, mover/añadir/borrar objetos y muros, renombrar lugares. Todo se guarda como **delta** sobre lo generado (ver §5).

**Efectos de zona** (pedido por Víctor el 2026-11-25; pendiente, sin fase asignada aún): el DM puede pintar o colocar sobre un conjunto de casillas efectos como **fuego, niebla/humo, agua, ácido, lava**, hielo, oscuridad mágica, telarañas, etc. Ideas de diseño, a cerrar en un ADR antes de implementarlo:
- **Como datos** (p. ej. `data/effects/*.json`): por efecto, propiedades de juego como en los objetos (terreno difícil, bloquea visión total o parcial, fuente de luz, daño por entrar o por turno solo como texto o referencia al perfil de reglas, nunca con cifras de reglas en código), aspecto 2D/3D (color, animación, partículas en 3D) y si se extiende o se apaga con el tiempo.
- **Como sesión con deshacer**: un efecto colocado es un comando y un delta (§6.7); no cambia `content_hash()` ni las seeds doradas. Forma: casillas sueltas, círculo/cono/línea desde una casilla con radio en casillas (útil para plantillas de conjuros) o una zona entera.
- **Visión y movimiento**: niebla y oscuridad entran en `Visibility` (ADR 024) como casillas que tapan; lava y ácido como coste o aviso en la ruta (`movement`), sin `if` por sistema.
- **Red (F4)**: el servidor filtra los efectos que los jugadores no ven, como la niebla de guerra.
- Más adelante, los generadores podrían colocar efectos fijos (lava en una mazmorra volcánica) con un parámetro nuevo al final del esquema, subiendo `GEN` si cambia el resultado.

**Editor de estancias** (pedido por Víctor el 2026-11-26; planificado, por hacer tras F5):
- **E1 – Reaplicar ediciones** (hecho, ADR 036): `DeltaReplay` convierte cada delta en su comando y lo aplica; `MapFile` guarda y abre mapas como código + deltas (`*.rpgm-map.json`); botones "Guardar mapa" y "Abrir mapa". Regla: el delta de todo comando nuevo lleva lo necesario para rehacerlo y su `op` se añade a `DeltaReplay` con un test de ida y vuelta.
- **E2 – Editor**: "Nueva estancia" en blanco (tamaño y rejilla) o a partir de una generada. Pintar suelo y muro; muros, puertas, secretas y ventanas en aristas; objetos del catálogo con giro; luces; escaleras; nombre y tipo. Con deshacer y aviso si algo queda sin conectar con la entrada.
- **E3 – Identificación** (decidido por Víctor: **los dos**):
  - **Id corto** de contenido (mismo contenido → mismo id) con carácter de control GF(32) como RPGM1. Recrea la estancia desde la biblioteca local, el fichero de campaña o, en red, desde el DM.
  - **Código para compartir** autosuficiente: base + deltas comprimidos; sirve en cualquier equipo y en QR, y su longitud crece con las ediciones.
  - La caja del código acepta los tres tipos.
- **E4 – Integración**: usar una estancia creada en lugar de una generada dentro de un edificio o asentamiento, y en la partida en red.

Implementación (F1): cada edición es un `MapCommand` (con deshacer) que, al aplicarse, añade un `MapDelta {op, data}` a `MapDocument.deltas`; `data` solo admite valores de `CanonicalJson` (enteros, textos, booleanos, listas, diccionarios). Al cargar un mapa se regenera desde el código y se reaplican los deltas en orden. Los deltas, los tokens y la niebla son **sesión**: no cambian `content_hash()`.

## 7. Vistas

| Vista | Implementación | Uso |
|-------|----------------|-----|
| **2D cenital** | `TileMapLayer` + `Node2D` para objetos/tokens; rejilla cuadrada o hexagonal | Preparación, pantalla de jugadores, impresión |
| **3D cenital** | `Camera3D` ortográfica o perspectiva con inclinación 0–60°; muros extruidos por altura; `GridMap` + mallas modulares | Ambientación, verticalidad, varios pisos |
| **1ª persona** | `Camera3D` en el token seleccionado (altura de ojos según tamaño), FOV 75° configurable | Exploración, ver lo que ve un personaje |

Requisitos comunes:
- Niebla de guerra y **línea de visión** calculadas en el modelo (no en la vista), con visión en la oscuridad y fuentes de luz (F2: ADR 024; la vista 3D, ADR 025). Selector "Ve: DM / jugadores": el DM lo ve todo; los jugadores, solo lo explorado, oscurecido si no lo ven ahora.
- Varias plantas: selector de planta; en 3D, corte de techo y plantas superiores.
- **Navegación jerárquica** (F3, ADR 028): doble clic en un edificio de un asentamiento (2D o 3D cenital) entra en él; el botón "← Volver a: …" sale. Las fichas del grupo (jugadores y aliados) cruzan con el DM: dentro aparecen en la casilla de la puerta principal y fuera, otra vez delante de ella. Cada mapa de la ruta conserva su sesión (fichas, niebla explorada) y los edificios visitados se recuerdan mientras no se genere otro mapa. Al llegar se explora lo que ve el grupo; en 1ª persona la ficha mira a la puerta que tiene al lado. Dentro de un edificio, doble clic en una estancia la abre sola con su código EST G2 (ADR 029): es el mismo sitio a la misma escala, así que solo pasan las fichas del grupo que ya están en ella, cada una a su misma casilla, y al volver regresan a la misma casilla del edificio.
- Rendimiento objetivo: 60 fps en mapas de 100×100 casillas en escritorio; 30 fps en web.
- **Rejilla hexagonal en todas las escalas** (ADR 012): opcional también en mapas tácticos (estancia, mazmorra, edificio), además de región y mundo. La geometría (vecinos, distancias, diagonales, plantillas de área, tamaños de token, línea de visión) se abstrae tras una interfaz de rejilla con implementaciones cuadrada y hexagonal; los perfiles indican el coste por paso en cada tipo de rejilla.
- Exportación: PNG con rejilla a resolución conocida (px por casilla) desde F1. **Impresión a escala real** (1 casilla = 1 pulgada / 25 mm, PDF por páginas A4/Carta con marcas de unión) antes de la v1, no en F1 (ADR 014).
- Intercambio con otras mesas virtuales (ADR 013): importar/exportar **Universal VTT** (`.uvtt` / `.dd2vtt`: imagen, rejilla, muros, puertas, luces) en F3. Foundry VTT y otros, después de la v1.
  - **Hecho (F3, ADR 030)**, `core/io/uvtt_codec.gd`. *Exportar* el nivel mostrado: imagen sin rejilla ni fichas (100 px/casilla, menos en mapas grandes para no pasar de 8192 px), muros de arista y de casilla maciza fundidos en tramos, puertas como portales (abiertas/cerradas; las secretas sin descubrir, como muro), luces de los objetos (alcance = radio total). Las ventanas y los vanos no se exportan (UVTT no tiene ventanas: no tapan la visión). En hex se exportan muros y puertas en distancia entre centros, pero las otras mesas solo conocen la cuadrada. En web se descarga. *Importar* (solo escritorio): mapa cuadrado de una planta, todo suelo; tramos horizontales y verticales encajados en su línea de la rejilla y diagonales o curvos aproximados en escalera; puertas en la arista más cercana; luces como objetos de luz (alcance del fichero); la imagen se pinta de fondo en 2D (`MapDocument.background_image`, ni se serializa ni entra en hashes) y oculta las cajas de los objetos.

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

**Coste por tipo de paso** (ADR 020): ortogonal = `cell_ft`; diagonal = `movement.diagonal_ft` (o una variante de mesa); hex = `movement.hex_step_ft` (5 ft en 5e y PF2e). Cada tipo lleva su propio contador del patrón cíclico. El terreno difícil se aplica al paso que **entra** en la casilla. En la cuadrada, `movement.diagonal_corner_rule` decide si un paso diagonal junto a una esquina exige uno (`any_side_free`, 5e y PF2e) o los dos rodeos ortogonales libres (`both_sides_free`). En la ruta automática bloquean los muros, **cualquier puerta cerrada** (con llave o sin ella, hasta que alguien la abra) y las secretas sin descubrir; el **foso** no es transitable y el agua profunda es transitable y difícil. Para la accesibilidad de un mapa generado, en cambio, todas las puertas cuentan como franqueables (`Connectivity`).

**Huella de las criaturas** (por rejilla, como datos): en la cuadrada, bloque de `ceil(space_ft / cell_ft)` casillas de lado; en hex, `sizes[].hex_cells`: 1 (Diminuta, Pequeña, Mediana), 3 en triángulo de orientación fija (Grande), 7 = radio 1 (Enorme), 19 = radio 2 (Gargantuesca).

Cada perfil define además: tipos de movimiento (andar, volar, nadar, trepar, excavar), sentidos (visión en la oscuridad, visión ciega…), condiciones que afectan al movimiento y plantillas de área (cono, línea, esfera, cubo, emanación/explosión).

**Plantillas de área** (`area_templates[]`: `id`, `shape`, `default_ft` y los campos de su forma; casillas en `AreaTemplate.cells`). Las distancias se miden con las reglas de movimiento del perfil (como la regla de medir), así que en 5e los círculos salen cuadrados y en PF2e octógonos; una casilla está dentro si la distancia medida hasta ella es ≤ el tamaño y, en conos y líneas, su **centro** cae dentro del ángulo o de la franja (empates dentro). Solo enteros (red de centros `GridGeometry.center_lattice`), igual en escritorio y web.
- `circle` (esfera y cilindro de 5e, explosión de PF2e): `origin = "corner"`, centro en la intersección de la esquina superior izquierda de la casilla (20 ft: 8×8 = 64 casillas en 5e, 44 en PF2e).
- `cone`: vértice donde el eje sale del espacio de la criatura (mitad del borde en ortogonal, esquina en diagonal); `cone_width_pct` = anchura en % de la distancia: 100 en 5e (anchura = distancia), 200 en PF2e (cuarto de círculo). 15 ft: 5e 5 casillas en ortogonal y 7 en diagonal; PF2e 7 y 6.
- `line`: desde la casilla de origen, franja de `line_width_ft` (5 ft en ambos). 30 ft en diagonal: 6 casillas en 5e, 4 en PF2e.
- `square` (cubo de 5e): bloque de lado `ceil(size/cell_ft)` con el origen arriba a la izquierda.
- `emanation`: ≤ tamaño desde cualquier casilla de la huella; `includes_origin` decide si la huella cuenta.
- Hex (aproximación): círculos centrados en la casilla (radio r = 3r² + 3r + 1 hexágonos), cubo = hexágono de radio lado/2; conos y líneas con la geometría exacta de los centros.

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
- El personaje viaja dentro de su ficha (`MapToken.sheet`), así el mapa y la partida en red no dependen de ficheros sueltos (ADR 034).

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
| Sincronización | **Revisado (ADR 031)**: el código de semilla **no** se envía a los jugadores (con él regenerarían el mapa entero y la niebla no serviría). Al unirse reciben el mapa ya filtrado por la niebla del grupo (`PlayerView`: casillas exploradas, aristas que las tocan, puertas secretas sin descubrir como muro, objetos, escaleras y trampas visibles, fichas del grupo y las demás solo si se ven ahora) y lo visible por nivel. Luego, solo lo que cambia (nivel, visión o fichas cuyo mensaje es distinto del anterior). Mensajes `{"t": tipo, …}` en JSON canónico + gzip (`net/net_message.gd`) |
| Implementación (F4) | `net/ws_codec.gd` (tramas RFC 6455 del servidor), `net/wss_server.gd` (HTTPS de la carpeta `web/` junto al ejecutable, o `build/web` desde el proyecto, con gzip, y WSS en `/ws` con comprobación de `Origin`), `net/net_certificate.gd` (autofirmado RSA 2048 guardado en `user://net/`; sustituible por uno propio), `net/game_session.gd` (acceso, validación, envío de cambios; sin nodos), `net/player_view.gd`, `net/net_client.gd` y `net/proposal_stack.gd` (cliente). UI: panel "Partida en red" del DM (`ui/net_host_panel.gd`: puerto, abrir/cerrar, jugadores con su enlace `https://<ip>:<puerto>/?sala=…&t=…`, dar la ficha seleccionada, quitar) y modo jugador en web al abrir ese enlace (solo nivel, unidades, vista, ajustar y PNG; arrastrar la ficha propia = propuesta; doble clic = señal) |
| Movimientos de jugadores | La sesión valida: ficha suya (`character_ref` = `player:<id>`, comando `SetTokenCharacterCommand`), mismo nivel, casilla explorada, no ocupada por una ficha que el jugador vea (si no, delataría las ocultas) y con ruta (`MovementCost.find_route` con las puertas reales). Lo aprobado se ejecuta en el historial del DM (puede deshacerlo) y explora como cualquier movimiento. **Puertas**: el jugador hace clic en una puerta y propone abrirla o cerrarla (mensaje `door`); la sesión exige que el DM lo permita (casilla "Los jugadores abren y cierran puertas", activa por defecto), una ficha suya en una de las dos casillas de la arista, que sea puerta (una secreta sin descubrir se trata como muro) y sin llave para abrirla; lo aprobado va también al historial del DM (ADR 032). **Escaleras**: doble clic en la ficha propia sobre una escalera propone ir a su destino; se valida que la ficha esté en una escalera que lleve exactamente a ese nivel y casilla y que no esté ocupada por una ficha visible (ADR 033). Cada propuesta aprobada explora **su** nivel, no el que mira el DM |

## 12. Datos y ficheros

| Fichero | Contenido |
|---------|-----------|
| `*.rpgm` | Campaña: ZIP con `manifest.json`, mapas (seed + params + `GEN` + deltas), personajes, recursos del usuario |
| `*.rpgm-map.json` | Un mapa suelto exportable |
| `*.rpgm-char.json` | Un personaje |
| `*.rpgm-map.json` | Un mapa: código de semilla + deltas, contador de ids y hash del mapa generado (`MapFile`, `data/schemas/map_file.schema.json`); sin código, el documento entero |
| `*.uvtt` / `*.dd2vtt` | Universal VTT: importación y exportación (F3) |
| `data/systems/*.json` | Perfiles de sistema |
| `data/styles/*.json` | Estilos arquitectónicos por cultura (F1: materiales y pesos del mobiliario; esquema `style.schema.json`) |
| `data/objects/*.json` | Catálogo de objetos (esquema `object_catalog.schema.json`) |
| `data/rooms/est_room_types.json` | Tipos de estancia de EST (esquema `est_room_types.schema.json`) |
| `data/buildings/edi_building_types.json` | Tipos de edificio de EDI (esquema `edi_building_types.schema.json`) |
| `data/settlements/ald_settlement_types.json` | Tamaños, tipos de edificio con habitantes y prosperidad de ALD (esquema `ald_settlement_types.schema.json`) |
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
| *Pendiente de asignar* | Efectos de zona (fuego, niebla, agua, ácido, lava…; §6.7) | Colocar, ver en las 3 vistas, deshacer y que afecten a visión y movimiento según sus datos |
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
| 020 | Coste de movimiento por **tipo de paso** como datos: ortogonal = `cell_ft`, diagonal = `diagonal_ft`, hex = `movement.hex_step_ft` (nuevo, requerido); contador independiente por tipo; terreno difícil por casilla de **destino**; `movement.diagonal_corner_rule` (nuevo, requerido: `any_side_free` en 5e y PF2e). Búsqueda de ruta Dijkstra con la **fase del patrón** en el estado (exacta con 5/10). **Revisado (Víctor, F1 etapa 2): cualquier puerta cerrada bloquea la ruta automática** hasta que alguien la abra, con llave o sin ella; las secretas sin descubrir también; el foso no es transitable; el agua profunda es transitable y difícil. Huella hex como dato del perfil (`sizes[].hex_cells`: 1, 3 en triángulo fijo, 7 o 19) | Reglas como datos sin `if hex` en el coste; las dos SRD no prohíben cortar esquinas, pero muchas mesas sí (dato); con la fase en el estado la ruta más barata es exacta en PF2e; el aviso de velocidad (§10.3) necesita coste fiable | Distancia hex calculada aparte; "no cortar esquinas" fijo en código; A* con heurística (con patrones alternos la admisibilidad es delicada y el mapa táctico es pequeño) |
| 021 | Seeds doradas en `tests/golden/golden_seeds.txt` (`<código> <sha256>` por línea, comentarios con `#`); modo grabación por variable de entorno `RPGM_GOLDEN_RECORD=1` que **solo rellena líneas sin hash**; sin ella, una línea sin hash falla; cada código se genera dos veces | Texto plano: diff legible, añadir es añadir una línea; la variable de entorno no requiere tocar GUT ni los scripts; nunca se reescribe un hash existente (CLAUDE.md §2) | JSON (diffs ruidosos, reescritura completa); argumento de línea de comandos (GUT no los pasa de forma uniforme); regenerar todo con un flag (permitiría "arreglar" una seed rota sin subir `GEN`) |
| 022 | Generador **MAZ G1** (§6.6): salas forzadas en las escaleras (misma casilla en dos plantas) + salas aleatorias con margen + árbol mínimo y bucles + pasillos por aristas que reducen la distancia + puertas donde un pasillo cruza el contorno de una sala construida y muros finos en el resto; cuevas por autómata celular de mayoría acotado a un círculo y componente del centro. Esquema con `size` y `style` añadidos tras los 4 campos de F0 y sin `wfc_tiles` (se añadirá al final cuando exista). **Esquema aprobado por Víctor (F1) y congelado** con 11 seeds doradas | Accesibilidad garantizada por construcción (no hace falta un bucle de reintentos); la distancia "ortogonales + 2·diagonales + hex" da pasillos por aristas en las tres rejillas sin ramas por tipo; el autómata acotado y la componente del centro evitan cuevas partidas; escaleras en mitades alternas: sin conflictos de colocación; quitar `wfc_tiles` ahora evita un parámetro que solo daría error, y añadirlo al final más tarde no cambia códigos | BSP (rejillas hex: los cortes rectos dan salas raras); autómata en todo el mapa y luego unir componentes (número de salas sin control); reintentar la generación entera hasta que sea conexa (coste impredecible); `wfc_tiles = true` como error |
| 023 | Generador **EST G1** (§6.5). Estancia = interior rodeado de muro macizo, puertas en arista hacia un rellano. Mobiliario **por datos**: catálogo `data/objects/*.json` (32 objetos propios), tipos de estancia `data/rooms/est_room_types.json` (obligatorios y opcionales con peso y máximo) y estilos `data/styles/<id>.json` (material por clase y % de peso). Etiquetas en inglés (`against_wall`, `center`, `near:<id>`) y pasillo libre como **regla global** comprobada por inundación. `MapObject.material` nuevo (no cambia ningún hash MAZ: MAZ no coloca objetos). Amueblado separado (`EstFurnisherG1.furnish`) para EDI. **Esquema EST G1, catálogo, tipos y estilos aprobados por Víctor (F1) y congelados** con 9 seeds doradas | Añadir objetos, tipos o estilos no toca código; la inundación garantiza puertas y zonas transitables conectadas e interactuables alcanzables sin casos especiales por rejilla; probar ≤ 16 candidatos al azar acota el coste de forma determinista; con una sola fuente de azar por estancia, la misma semilla da lo mismo aislada o como hija de un edificio | Pasillo libre como etiqueta por objeto (no garantiza la conectividad global); colocación por plantillas fijas por tipo (poco variada y atada a la cuadrada); referenciar el catálogo sin copiar propiedades; materiales en el catálogo por estilo (multiplica entradas) |
| 024 | **Visión en el modelo** (F2): `core/model/visibility.gd` calcula línea de visión entera y simétrica sobre `GridGeometry.line()` (casillas intermedias que tapan, aristas que tapan —muro, puerta cerrada, secreta—, diagonal de la cuadrada visible si un rodeo ortogonal está libre), mapa de luz (oscuro/tenue/brillante con sombra desde cada fuente) y casillas visibles (alcance 24 casillas, luz o visión en la oscuridad). `PartyVision`: observadores = fichas `player`/`ally`; luces = objetos con luz + opcionalmente la que lleva cada ficha (la del objeto `torch_sconce` del catálogo); opción "ambiente iluminado". Niebla = casillas **exploradas** por observador (`party`), estado de sesión con delta (`ExploreCommand`), que se **une al paso de deshacer** del movimiento/puerta que la provoca (`CommandStack.execute_attached` + `CompositeCommand`). Lo visible ahora se deriva y no se guarda | Una sola fuente para 2D, 3D, 1ª persona y el filtrado del servidor en F4 (niebla coherente entre vistas por construcción); entera = igual en escritorio y web; deshacer un paso debe volver a tapar lo que descubrió; luces como datos del catálogo, sin cifras de reglas en código | Visión calculada en cada vista (divergen); shadowcasting por octantes (no vale para hex sin otra versión); niebla fuera del historial (deshacer dejaría casillas descubiertas); antorcha con radios fijos en código |
| 025 | **Vista 3D** (F2) sin assets: geometría generada por `views/view3d/map_mesh_builder.gd` (suelo con junta de rejilla, caras de pared donde lo transitable linda con roca/vacío, tapas, cajas en aristas con muro, marcos y hojas de puerta, cajas de objetos con su `height_mm`, peldaños, aspas de trampa) en 3 mallas por nivel. **Material propio sin luces** (`map_vertex_color.gdshader`): color por vértice en sRGB con la niebla y la luz del modelo horneadas y oscurecimiento por distancia en 1ª persona. Cenital: cámara orbital inclinable 0–60°, perspectiva u ortográfica; 1ª persona en la ficha seleccionada (ojos según tamaño, FOV 75°), avance casilla a casilla con `MoveTokenCommand` y giro por lados de la rejilla. Se reconstruye entera al cambiar el documento (≈10–20 ms en los mapas de F1) y solo cuando está activa | Funciona igual en Forward+ y Compatibility (WebGL 2), sin límites de luces dinámicas; la niebla 3D es exactamente la de 2D; cambiar de vista tarda muy por debajo de 500 ms; los módulos CC0 (KayKit, Quaternius…) pueden sustituir a las cajas más adelante sin tocar el modelo | `GridMap` + MeshLibrary (no sirve para hex ni para muros en arista); luces `OmniLight3D` por fuente (límite por objeto en Compatibility y niebla no idéntica a 2D); reconstrucción incremental por casilla (más compleja; innecesaria a este tamaño) |
| 026 | Generador **EDI G1** (§6.4, F3). Tipos de edificio **como datos** (`data/buildings/edi_building_types.json`: estancias por planta con peso, hub, adyacencias obligatorias, huellas, plantas por defecto, entrada/trasera/escaleras) y bloque `building` opcional en los estilos (`footprint_pct`, `window_pct`). Distribución por planta: **espina** (hub a lo largo del eje largo con rebanadas a los lados) si la planta tiene pasillo/recibidor; si no, **BSP por pesos** con hasta 12 intentos hasta cumplir las adyacencias y, si no, hub de reserva. **Todos los muros en arista**, también el exterior, con anillo exterior de suelo en la planta baja y vacío en las demás; **`MapEdge.KIND_WINDOW` = 5** (bloquea paso y conectividad, no visión). Escaleras en la misma casilla en las dos plantas; mobiliario con `EstFurnisherG1` y semilla `hash64(semilla, "EST", nivel × 256 + orden)`. Tipos de estancia EST nuevos al final del enumerado. Esquema `building_type, grid, style, floors (0 = auto), cellar, size, clutter`. **Aprobado por Víctor (2026-11-25)** junto con los 7 tipos de edificio, los tipos de estancia nuevos, el bloque `building` de los estilos y `KIND_WINDOW`; congelado con 8 seeds doradas | La espina garantiza que todas las habitaciones de una planta alta tocan el pasillo y deja pasar la escalera por él; el BSP de prefijos conserva el orden de los datos y cumple las cadenas de adyacencia (0 hubs de reserva en 132 plantas de prueba; la estrella forzada sí lo usa); la conectividad sale por construcción sin reintentar el edificio; muros en arista: ventanas reales (se ve a través), UVTT y 3D por módulos sin vectorizar casillas; la ventana como tipo de arista nuevo no cambia ningún hash existente; una semilla por estancia permite regenerar una sola sin tocar las demás | Muro exterior macizo por casilla (la ventana no dejaría ver: la casilla de muro tapa la visión; UVTT tendría que vectorizar); BSP puro con cortes al azar (adyacencias por suerte); grafo de adyacencias resuelto por búsqueda exhaustiva (coste impredecible); ventana como bandera de `KIND_WALL` (cambiaría `is_valid` de valores existentes y mezcla semánticas); pasillo siempre (casas y tiendas pequeñas quedarían con un tercio de pasillo); huellas en forma de L en G1 (se añadirán con un campo al final) |
| 027 | Generador **ALD G1** (§6.3, F3; **aprobado por Víctor el 2026-11-25 y congelado** con 8 seeds doradas). **Escala: 1 casilla = la casilla táctica del sistema (5 ft)**, la misma que EDI. **Cada edificio es un hijo EDI G1**: parámetros sacados solo de `fork("building", k)` y semilla `hash64(semilla, "EDI", k)` recortada a 40 bits; su código RPGM1 se guarda en el documento (**`MapChild`** en `MapLevel.children`, nuevo, serializado solo si hay hijos) con la traslación `offset` entre casillas; la huella es la de EDI y la puerta principal, la trasera y las ventanas salen de `EdiGeneratorG1.plan_ground_floor()` (nuevo; misma planta baja que EDI, sin amueblar). La traslación respeta la paridad offset de la rejilla hex (`translation_step`). Calles por caminantes (orgánico) o retícula, poda de calles no conexas, parcelas = huella + anillo + patio apoyadas en una fachada. Población derivada de los edificios. Tamaños, tipos, prosperidad como datos (`data/settlements/`) y bloque `settlement` en los estilos. Zonas nuevas de `MapRoom` (`street`, `plaza`, `yard`, `building`…) sin tipos de terreno nuevos. Esquema `size, grid, style, wall, water, prosperity, layout` | Con la misma escala, la huella del edificio en la aldea es exactamente su mapa EDI y la ficha pasa de la calle al edificio por la misma puerta sin convertir; regenerar el código hijo da el mismo edificio (criterio de F3) y los interiores no se generan (< 1 s por ciudad); la semilla por orden y los parámetros por `fork` hacen cada edificio independiente de los demás y de la parcelación; 40 bits: códigos de 8 caracteres como los de la app; el anillo de la parcela es el anillo exterior del mapa EDI, así que la puerta, esté donde esté, da a suelo transitable unido a la calle; zonas en vez de terrenos nuevos: no cambia `Terrain` ni ningún hash | Escala propia mayor (10-25 ft/casilla: la huella dejaría de coincidir con EDI y habría que redondear puertas); generar el edificio entero para conocer su puerta (≈ 50-100 ms × 80 edificios = varios segundos); elegir la puerta desde ALD con un campo nuevo de EDI (cambia EDI, congelado); girar los edificios (EDI no tiene orientación: el giro no regeneraría el mismo mapa); población como parámetro (duplica `size`); terreno `ROAD` nuevo (cambia `Terrain` sin necesidad: las zonas ya colorean) |
| 028 | **Navegación jerárquica** (F3): `MapNavigator` (`core/model/`, sin nodos) guarda la ruta de mapas abiertos; cada uno con su documento y su historial; los hijos visitados se guardan en el padre por `MapChild.id`. Entrar: doble clic en la huella (señal `cell_activated` de las vistas 2D y 3D cenital) → se genera el hijo desde `MapChild.seed_code` la primera vez. Las fichas del grupo (`SIDES_IN_PARTY`) del nivel pasan con `RemoveTokenCommand` (nuevo) / `AddTokenCommand` a la casilla de la puerta (`MapChild.entrance` trasladada) y las libres más cercanas; al salir, delante de la puerta en el padre. **Cambiar de mapa vacía el historial de deshacer de los dos mapas**. La vista 2D calcula la casilla con la posición del **evento** y no con `get_local_mouse_position()`. Segundo modo de paso (`keep_positions`, edificio → estancia): solo las fichas del grupo dentro de la huella, a su casilla equivalente, y de vuelta a la misma casilla y nivel | Un mapa por nivel de la jerarquía con su sesión intacta: volver a la taberna la encuentra como se dejó y la aldea no se regenera; el navegador sin nodos se prueba sin UI; deshacer a través de mapas (devolver una ficha a un documento que no se ve) daría estados raros, así que el cruce es una frontera; los enemigos y neutrales se quedan donde están (los mueve el DM). La posición del evento funciona igual con ratón, pantalla táctil, web y eventos inyectados (con `get_local_mouse_position()` el doble clic inyectado caía fuera del mapa) | Regenerar el padre al volver (perdería fichas y niebla); un único documento con todos los hijos dentro (aldea + 80 edificios amueblados: segundos de generación y memoria); entrar automáticamente al pisar la puerta (molesto al pasar por delante); deshacer que cruce mapas |
| 029 | **Código de estancia de edificio = EST G2** (§6.5, F3; decisión de Víctor 2026-11-25 entre esto y un EST G2 con forma/puertas como parámetros; ****aprobado por Víctor el 2026-11-25 y congelado** con 8 seeds doradas). `PARAMS` = los 7 campos de EDI G1 (copiados, mismo orden y defectos) + `level` (0-7) + `room` (0-63, el orden de `room_seed`); `SEED` = la del edificio. Genera el edificio **sin muebles** (`EdiGeneratorG1.plan_building`, nuevo), amuebla **solo** esa estancia (`furnish_room`, nuevo) y la **extrae por traslación** con un anillo de 1 casilla copiado del edificio (terreno, zonas y aristas; sin objetos ni escaleras de las vecinas); origen redondeado al paso de traslación de la rejilla (paridad hex); documento de **un nivel** con escaleras de `to_level` relativo (−1/+1, fuera del documento). EST G1 sigue igual y convive (otra clave en los registros). La relación edificio → estancias se **deriva al vuelo** (`EstGeneratorG2.rooms_of/room_at/ref_of/room_code/building_code`, `RoomRef.to_map_child()`), no se guarda en el documento EDI. Errores `SEED_ERR_ROOM_LEVEL` / `SEED_ERR_ROOM` mediante un "explicador" opcional por generador en `GeneratorRegistry` (solo se llama si devuelve null). Pasillo/recibidor (hub) navegable; exterior no | Exacto por construcción (es literalmente la estancia del edificio, no una imitación con los mismos datos), sin tocar EDI G1 ni ALD G1 (37 seeds doradas iguales; guardar `MapChild` de estancias en EDI habría cambiado su hash); la escala EST dice qué mapa sale (una estancia) y la escala entra en el control; el código del edificio se recupera quitando dos campos, sin tablas; amueblar una sola estancia cuesta ~¼ del edificio (8-13 ms frente a 31-48 ms); con la paridad respetada los vecinos hex no cambian; el anillo muestra qué hay tras cada puerta y ventana y deja salir por ellas; un nivel abre directamente la estancia al pegar su código (con los niveles del edificio, la app abriría uno vacío) y el `to_level` relativo dibuja bien la flecha; ningún campo nuevo en `MapDocument` | EST G2 con forma y puertas como parámetros (código largo y no garantiza el mismo resultado: otro algoritmo con los mismos datos); `level`/`room` añadidos al final de EDI G1 (un código "EDI" que da una estancia; EDI está congelado); `MapChild` de estancias en el documento EDI (cambia su hash y las seeds doradas); generar el edificio entero y recortar (exacto también, pero 3-4× más lento); documento con todos los niveles del edificio (niveles vacíos en la UI) o `to_level` absoluto en un documento de un nivel (flecha de escalera al revés); anillo de muro macizo como EST G1 (taparía ventanas y puertas: no se vería ni se podría salir) |
| 030 | **Universal VTT** (F3): códec puro `UvttCodec` (sin nodos; la imagen la renderiza la UI con `PngExporter`, que gana `show_tokens`). Exporta el nivel mostrado con lo que ven los jugadores (secretas sin descubrir = muro) y sin rejilla ni fichas en la imagen; píxeles por casilla = 100 o menos hasta 8192 px. Importa a un mapa **cuadrado** de una planta: tramos rectos encajados en la rejilla, diagonales en **escalera**, puertas a la arista más cercana, luces como `torch_sconce` con el alcance del fichero, imagen como fondo solo de vista (`MapDocument.background_image`, fuera de la serialización y los hashes). La vista 2D calcula la casilla del ratón con el evento (ADR 028), así que el mapa importado se juega igual | Formato abierto y extendido (Dungeondraft, Foundry, Arkenforge…); las coordenadas en casillas coinciden con nuestro modelo de aristas; la escalera conserva que el muro diagonal tape visión y paso (encajar cada muestra en la línea más cercana dejaba trocitos sueltos); el fondo como dato de vista no toca ningún hash ni el formato de guardado; un códec sin nodos se prueba sin UI (ida y vuelta casilla a casilla en mazmorra y edificio) | Exportar también rejilla y fichas en la imagen (la otra mesa pone las suyas); muros diagonales como "no encaja, se omite" (deja huecos en la visión); guardar la imagen en el documento (archivos enormes, hash dependiente de la imagen); importar hex (UVTT no tiene rejilla hex) |
| 031 | **Partida en red** (F4): servidor propio en GDScript sobre `TCPServer` + `StreamPeerTLS`: en **un solo puerto** sirve el cliente web por HTTPS y acepta el WebSocket en `/ws` (tramas RFC 6455 propias, `WsCodec`). Protocolo propio de mensajes JSON + gzip, no RPC. **A los jugadores no se les envía la semilla** sino el mapa filtrado por la niebla del grupo (`PlayerView`) y solo los cambios; la visión es la del **grupo** (la misma que la vista "Jugadores" del DM), calculada una vez por cambio para todos. Los jugadores proponen; `GameSession` valida y el DM ejecuta en su historial. Acceso: sala de 6 caracteres nueva en cada apertura + código de jugador de 10 (Crockford, `Crypto`); enlace en vez de QR por ahora. Certificado autofirmado persistente (o el del DM). Escrituras TLS de 4 KB repetidas idénticas cuando no salen | Mismo origen (ADR 016): el `WebSocketPeer` de Godot no admite una conexión cuya petición HTTP ya se leyó, y `WebSocketMultiplayerPeer` no sirve páginas; la sesión sin nodos se prueba con un transporte en memoria y la regla de oro 6 (niebla filtrada en el servidor) se cumple también ante quien lea el tráfico; con el mapa filtrado, 8 clientes en LAN se actualizan en < 80 ms (criterio < 150 ms); Godot encadena varias `mbedtls_ssl_write` en `put_partial_data` y, con trozos de más de un registro, un registro guardado y no contado hacía perder ~16 KB en mitad del `.wasm` con Chrome (ERR_CONTENT_DECODING_FAILED), así que cada escritura cabe en un registro | `WebSocketMultiplayerPeer` + RPC en otro puerto (dos orígenes: certificado aceptado dos veces, contenido mixto); enviar semilla + deltas y filtrar en el cliente (un jugador vería el mapa entero); visión por personaje (un cálculo por cliente y cambio; se puede añadir con un observador por jugador); escrituras TLS bloqueantes (un navegador lento congelaría la app del DM) |
| 032 | **Puertas por los jugadores e invitación por QR** (F4): abrir o cerrar una puerta se propone como un movimiento (mensaje `door`) y lo valida `GameSession.validate_door`: opción del DM activa, ficha propia en una de las dos casillas, puerta de verdad (secreta sin descubrir = muro) y sin llave para abrirla; se ejecuta en el historial del DM. En 2D, un clic a menos de 0,12 casillas de una puerta la acciona aunque haya ficha en la casilla. **QR propio** (`net/qr_code.gd`: modo byte, versiones 1-10, corrección M) en el panel de cada jugador. La dirección de enlaces y QR se elige en el panel, ordenada con las interfaces reales primero y las virtuales y de VPN al final | Probado con Chrome real: el jugador no podía cruzar una puerta cerrada sin pedírselo al DM, y en un pasillo de una casilla con fichas a ambos lados la puerta no se podía pulsar (ganaba la ficha). Godot no trae generador de QR y una biblioteca nativa exigiría GDExtension (rompe la web, §4); el QR se verifica con valores publicados (Reed-Solomon, formato, versión, alineación, capacidades) y leyendo el símbolo de vuelta. En un equipo con WSL la primera IP privada era la del conmutador virtual (172.26.x), inalcanzable para un móvil | Puertas solo del DM (frena la partida); abrir sin validar en el servidor (permitiría abrir cerradas con llave o delatar secretas); QR por servicio web externo (envía el código de la sala a terceros); elegir la dirección solo por el rango privado |
| 033 | **Escaleras, señal del DM y 3D del jugador** (F4): doble clic en una ficha sobre una escalera (`MapView2D.take_stairs`, señal `stairs_taken`) la lleva al nivel y casilla de destino con un `MoveTokenCommand` (vale para el DM y, como propuesta validada por `GameSession._validate_stairs`, para el jugador, que sigue a su ficha al nuevo nivel cuando el servidor la mueve). Con la partida abierta, el doble clic del DM en una casilla sin edificio la señala a todos ("DM"). Lo aprobado explora el nivel del comando (`main._explore_level`). En modo jugador, la vista 3D encuadra lo explorado (`MapView3D.fit_region`) y la 1.ª persona usa la ficha propia | Hasta ahora nadie podía cambiar de nivel con una ficha (ni el DM: solo el selector de nivel). Probado en Chrome real: con el DM mirando otro nivel, la visión del jugador no se guardaba (se exploraba el nivel mostrado), y la 3D del jugador encuadraba el mapa entero, casi todo vacío | Botón "usar escalera" (otro control más en la barra); que el jugador cambie de nivel sin escalera (rompe la autoridad del DM); explorar siempre todos los niveles (coste innecesario) |
| 034 | **Personajes** (F5): `CharacterSheet` (`*.rpgm-char.json`, `data/schemas/character.schema.json`): nombre, sistema, tamaño, velocidades y sentidos por id del perfil (pies enteros), iniciativa opcional, retrato PNG de 128 px en base64 y aspecto (`CharacterLook`: complexión, pieza por ranura, color por material). Va **dentro de la ficha** (`MapToken.sheet`, opcional; `SetTokenSheetCommand` con deshacer le da nombre y tamaño). La velocidad del personaje manda en la ruta y el aviso; su visión en la oscuridad cuenta en la visión del grupo. Figura 3D **procedural**: `data/characters/look_catalog.json` (`LookCatalog`) describe cada complexión y pieza como primitivas, y `CharacterModelBuilder` las funde en una malla con sombreado horneado en los vértices (caché por aspecto). En 2D, retrato en círculo o silueta (`TokenPainter`). Importadores CSV (cabeceras es/en, `,` `;` o tabulador, metros con la convención de `Units`) y JSON (propio, por nombres o con mapeo de campos por rutas). A los jugadores, de criaturas ajenas solo llega el aspecto | Un mapa o una partida en red tienen que poder dibujar y mover a cada personaje sin ficheros aparte. Primitivas en datos: sin descargar assets, con licencia propia y ampliables sin tocar código | Biblioteca de personajes aparte con referencias (rompe al mover fichas entre mapas y en red); modelos CC0 (KayKit, Quaternius) ya: pendiente, necesita descargarlos y registrar licencias, y la figura procedural sirve de reserva; esqueleto y animaciones (§10.2) para más adelante |
| 035 | **Turnos y plantillas de área** (F5): `TurnTracker` en la sesión del `MapDocument` (orden, iniciativa, ronda, turno actual, pies gastados, opción del DM de bloquear al pasar de la velocidad); cambia por `SetTurnsCommand` (con deshacer) y `MoveTokenCommand` lleva el coste de la ruta y lo suma si es el turno de la ficha. Panel "Turnos" (`TurnPanel`): el DM añade fichas, tira (d20 + modificador del personaje) o escribe la iniciativa, ordena y pasa turno; los jugadores lo ven en solo lectura, filtrado por el servidor (`PlayerView.filter_turns`: solo fichas que ven; si le toca a una oculta, no hay turno a la vista). En red, con combate en marcha, una ficha del orden solo se mueve en su turno (`NET_MOVE_NOT_YOUR_TURN`) y, con el bloqueo, sin pasarse (`NET_MOVE_TOO_FAR`). Plantillas: geometría como datos del perfil (`area_templates`) y casillas cubiertas en `AreaTemplate.cells`; herramienta en la vista 2D que cuenta las fichas de dentro, local (no se comparte) | §10.3 pide solo el orden y un aviso, sin automatizar el combate: el DM sigue mandando y todo se deshace. Las plantillas dependen del sistema (el cono de 5e no es el de PF2e), así que van en el perfil | Tiradas automáticas de ataque o daño (fuera de alcance); iniciativa fuera del mapa (se perdería al guardar y no llegaría a la red); plantillas compartidas con los jugadores y en 3D (más adelante) |
| 036 | **Reaplicar ediciones y mapas guardados** (E1 del editor de estancias): cada delta lleva todo lo necesario para rehacer su comando (`add_token` la ficha entera con su personaje, `set_token_sheet` la hoja, `set_turns` el estado entero, `move_token` el coste) y `DeltaReplay.replay` los reaplica en orden con los mismos comandos, que vuelven a escribir sus deltas: el documento abierto es idéntico (mismo `full_hash`). `MapFile` (`*.rpgm-map.json`) guarda código + deltas + `next_id` (para no reutilizar ids de fichas borradas) + `content_hash` del mapa generado: si al abrir no coincide, el generador cambió sin subir `GEN` y no se reaplica nada (`MAP_ERR_GENERATOR`). Sin código (UVTT), el documento entero, sin la imagen de fondo | ADR 004 decía "seed + deltas", pero nada reaplicaba los deltas y algunos eran solo un resumen. Es la base del editor de estancias (E2–E4) y de la campaña `*.rpgm` | Guardar el documento entero siempre (más grande y atado a la versión del modelo, no al generador); reconstruir desde los deltas sin comandos (dos caminos que se desincronizan); comprimir los deltas ahora (se hará en el código para compartir, E3) |
| 037 | **Editor de estancias** (E2): botón "Editar" (solo el DM) con panel `RoomEditorPanel` y herramientas en la vista 2D (`MapView2D.edit_tool`): pintar terreno arrastrando (`SetTerrainCommand`, una pincelada = un paso de deshacer), aristas arrastrando por los bordes (muro, puerta, secreta, vano, ventana o quitar: `SetEdgeCommand` agrupados en `CompositeCommand`), colocar objetos del catálogo con giro (R) y borrarlos (`AddObjectCommand`, `RemoveObjectCommand`), tipo y nombre de las salas (`SetRoomCommand`), y aviso de suelo sin acceso desde la entrada (`Connectivity`). "Crear estancia en blanco" genera **EST G3** (interior vacío con entrada, del tamaño y rejilla elegidos, semilla 0). Todos los comandos nuevos tienen delta reaplicable (ADR 036), así que una estancia hecha a mano es código + deltas | Lo que pidió Víctor, sobre la base de E1: nada nuevo que guardar, y el id corto y el código para compartir (E3) saldrán de código + deltas. Una base generada (EST G3) en vez de un documento sin código mantiene ese esquema también para las estancias desde cero | Editor como modo aparte con su propio documento (duplicaría vistas y guardado); estancia en blanco sin código (no tendría id reproducible); escaleras y niveles en el editor (más adelante: una estancia es de un nivel) |

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
