# Modelo Tabular — Subsistema de Comentarios Masivos (Hito 6)

## Plataforma del Fixture del Mundial 2030 — Ingeniería de Datos II

---

## 1. Principios del Diseño Lógico y Patrón CQRS

El modelo de datos implementado en Apache Cassandra responde rigurosamente a las consultas catalogadas en [`docs/patrones_de_acceso.md`](./patrones_de_acceso.md). En este subsistema:
1. **La clave primaria gobierna el comportamiento físico:** La **Partition Key** determina en qué nodo y partición del cluster reside el dato (a través de la función de hash criptográfico Murmur3Partitioner). Las **Clustering Columns** determinan el orden físico de las filas dentro del archivo SSTable en disco.
2. **Segregación CQRS (Hot / Cold Split):** Se implementa una separación estricta a nivel de almacenamiento:
   - **Vía Transaccional en Caliente (`comentarios_feed`):** Optimizada para la escritura a alta tasa y lectura paginada en vivo durante los partidos, con particiones de 5 minutos, TTL de 14 días y compactación TWCS.
   - **Vía Analítica e Histórica (`comentarios_historico`):** Estructura desnormalizada permanente que agrupa los comentarios de cada partido sin TTL bajo STCS, respondiendo al requerimiento RF10 de estructura secundaria para reportes y a la pregunta 12 de la rúbrica sobre analítica histórica.
3. **Mecanismo de Ingestión Dual-Write Asincrónico:** El backend emite escrituras simultáneas e idempotentes a ambas tablas utilizando el mismo identificador `comentario_id` (`timeuuid`). Al ser operaciones de inserción puras (*append-only*), se garantiza la convergencia eventual y la idempotencia exigida por RNF7 sin necesidad de jobs de migración batch propensos a estados inconsistentes.
4. **Tratamiento del Idioma:** El campo `idioma` no forma parte de la clave de partición primaria. Se almacena como una columna regular informativa. La lectura transaccional desde Cassandra entrega el feed global del bloque temporal y el filtrado por idioma preferido se resuelve en memoria de la capa de aplicación.

---

## 2. Inventario de Tablas y Especificación de Esquema

A continuación se detalla la composición tabular mediante tablas de metadatos y prosa técnica, sin incluir sentencias DDL directas de CQL.

### 2.1. Tabla `comentarios_feed` (Vía en Caliente — Feed en Vivo con TTL)
Diseñada para resolver **Q1**: la visualización paginada del feed durante el partido en tiempo real con latencia mínima, segmentada por ventanas temporales de 5 minutos.

| Nombre de Columna | Tipo de Dato Cassandra | Rol en la Clave Primaria | Descripción y Semántica |
| :--- | :--- | :--- | :--- |
| `partido_id` | `text` | **Partition Key (Componente 1)** | Identificador único del partido (ej. 'ARG-ESP-20300624'). |
| `bloque_temporal` | `timestamp` | **Partition Key (Componente 2)** | Marca temporal truncada al inicio de la ventana de 5 minutos. |
| `comentario_id` | `timeuuid` | **Clustering Column (DESC)** | Identificador único temporal; garantiza orden cronológico inverso y unicidad. |
| `idioma` | `varchar` | Columna regular | Código de idioma del mensaje (ej. 'es', 'en', 'pt', 'fr', 'ar'). |
| `usuario_id` | `text` | Columna regular | Identificador del autor en el subsistema de usuarios. |
| `nombre_usuario` | `text` | Columna regular | Nombre visible desnormalizado para evitar lookups en lectura. |
| `texto` | `text` | Columna regular | Mensaje emitido por el usuario (máx. 280 caracteres). |
| `estado_moderacion` | `text` | Columna regular | Estado de visualización: 'VISIBLE', 'OCULTO', 'PENDIENTE'. |

#### Parámetros Operativos de Almacenamiento:
- **Partition Key Compuesta:** `((partido_id, bloque_temporal))`
  - Dispersa el flujo de comentarios de un mismo encuentro deportivo a lo largo de múltiples particiones físicas del anillo en función del avance cronológico, evitando concentrar todo el partido en una única partición física.
- **Clustering Column:** `comentario_id WITH CLUSTERING ORDER BY (comentario_id DESC)`
  - Al configurarse en orden descendente (`DESC`), los comentarios nuevos quedan físicamente adyacentes al inicio del archivo de datos en disco. Esto permite que la lectura de los últimos comentarios sea una lectura secuencial rápida sin necesidad de ordenar en memoria.
- **Tiempo de Vida (TTL):** **14 días (1.209.600 segundos)**. Pasadas dos semanas de la finalización del partido, el interés de scrolleo transaccional desaparece y las filas expiran automáticamente.
- **Estrategia de Compactación:** **TimeWindowCompactionStrategy (TWCS)** con ventana de 1 día. Al expirar el TTL, Cassandra descarta SSTables enteras de forma directa (*drop file*) a nivel del sistema operativo, erradicando la sobrecarga de compactar millones de tombstones individuales.

---

### 2.2. Tabla `comentarios_historico` (Vía Analítica y Auditoría Pospartido — RF10)
Diseñada para resolver **Q5**: consolidación permanente de la totalidad de comentarios de un partido completo para auditoría reglamentaria, minería de texto y análisis pospartido (pregunta 12 de la rúbrica).

| Nombre de Columna | Tipo de Dato Cassandra | Rol en la Clave Primaria | Descripción y Semántica |
| :--- | :--- | :--- | :--- |
| `partido_id` | `text` | **Partition Key** | Identificador del partido (ej. 'ARG-ESP-20300624'). |
| `comentario_id` | `timeuuid` | **Clustering Column (ASC)** | Cronología histórica de los eventos del partido desde el inicio. |
| `bloque_temporal` | `timestamp` | Columna regular | Bloque temporal de origen para trazabilidad con el feed en vivo. |
| `idioma` | `varchar` | Columna regular | Idioma del mensaje. |
| `usuario_id` | `text` | Columna regular | Identificador del autor. |
| `nombre_usuario` | `text` | Columna regular | Nombre del autor. |
| `texto` | `text` | Columna regular | Contenido del comentario. |
| `estado_moderacion` | `text` | Columna regular | Estado final de moderación. |

#### Parámetros Operativos de Almacenamiento:
- **Partition Key Simple:** `((partido_id))`
  - Agrupa la totalidad de los comentarios del partido en una única partición física analítica por encuentro. Permite escaneos secuenciales masivos para alimentar pipelines de analítica o reportes.
- **Clustering Column:** `comentario_id WITH CLUSTERING ORDER BY (comentario_id ASC)`
  - Permite reconstruir la cronología completa del partido desde el minuto inicial hasta el final.
- **Tiempo de Vida (TTL):** **Sin TTL (Permanente)**. Resguardo histórico indefinido.
- **Estrategia de Compactación:** **SizeTieredCompactionStrategy (STCS)**, óptima para tablas de tipo *append-only* que no sufren borrados continuos ni expiración masiva de datos.

---

### 2.3. Tabla `comentarios_por_usuario` (Historial Personal desde el Perfil)
Diseñada para resolver **Q2**: permite al usuario explorar cronológicamente todos los comentarios que realizó a lo largo del Mundial.

| Nombre de Columna | Tipo de Dato Cassandra | Rol en la Clave Primaria | Descripción y Semántica |
| :--- | :--- | :--- | :--- |
| `usuario_id` | `text` | **Partition Key** | Identificador del usuario que emite el comentario. |
| `comentario_id` | `timeuuid` | **Clustering Column (DESC)** | Identificador temporal; permite ordenar su historial personal. |
| `partido_id` | `text` | Columna regular | Identificador del partido donde comentó. |
| `bloque_temporal` | `timestamp` | Columna regular | Bloque temporal de origen. |
| `idioma` | `varchar` | Columna regular | Idioma original en el que fue publicado el mensaje. |
| `texto` | `text` | Columna regular | Contenido textual del mensaje. |
| `estado_moderacion` | `text` | Columna regular | Estado operativo del comentario. |

#### Desglose de la Clave Primaria:
- **Partition Key Simple:** `((usuario_id))`
- **Clustering Column:** `comentario_id WITH CLUSTERING ORDER BY (comentario_id DESC)`

---

### 2.4. Tabla `comentarios_moderacion` (Cola Operativa de Revisión)
Diseñada para resolver **Q3**: cola de trabajo para los moderadores humanos o sistemas de análisis de toxicidad.

| Nombre de Columna | Tipo de Dato Cassandra | Rol en la Clave Primaria | Descripción y Semántica |
| :--- | :--- | :--- | :--- |
| `estado_moderacion` | `text` | **Partition Key (Componente 1)** | Estado operativo a revisar: 'PENDIENTE', 'REPORTADO'. |
| `fecha` | `date` | **Partition Key (Componente 2)** | Fecha calendario de emisión (ej. '2030-06-24'). |
| `comentario_id` | `timeuuid` | **Clustering Column (ASC)** | Orden de llegada a la cola de moderación (FIFO). |
| `partido_id` | `text` | Columna regular | Partido al que pertenece el comentario. |
| `bloque_temporal` | `timestamp` | Columna regular | Bloque temporal en la tabla de feed. |
| `idioma` | `varchar` | Columna regular | Idioma del comentario. |
| `usuario_id` | `text` | Columna regular | Identificador del autor reportado. |
| `texto` | `text` | Columna regular | Texto sujeto a revisión. |
| `motivo_reporte` | `text` | Columna regular | Causa del reporte ('SPAM', 'OFENSIVO', etc.). |

#### Desglose de la Clave Primaria:
- **Partition Key Compuesta:** `((estado_moderacion, fecha))`
- **Clustering Column:** `comentario_id WITH CLUSTERING ORDER BY (comentario_id ASC)`

---

### 2.5. Tabla `likes_por_comentario` (Métricas Atómicas de Interacción)
Diseñada para resolver **Q4**: cómputo distribuido y concurrente de likes acumulados.

| Nombre de Columna | Tipo de Dato Cassandra | Rol en la Clave Primaria | Descripción y Semántica |
| :--- | :--- | :--- | :--- |
| `comentario_id` | `timeuuid` | **Partition Key** | Identificador del comentario votado. |
| `likes` | `counter` | Columna regular | Contador atómico distribuido (`counter`). |

#### Desglose de la Clave Primaria:
- **Partition Key Simple:** `((comentario_id))`
  - Direcciona la consulta directamente al nodo que administra las mutaciones del contador para ese mensaje específico. Evita ciclos de *Read-Modify-Write* en la aplicación.

---

### 2.6. Tabla `contadores_por_partido` (Totalizador Global Evita Count Scan)
Diseñada para resolver **Q6**: provee la métrica total de comentarios emitidos sin ejecutar `COUNT(*)` sobre particiones masivas.

| Nombre de Columna | Tipo de Dato Cassandra | Rol en la Clave Primaria | Descripción y Semántica |
| :--- | :--- | :--- | :--- |
| `partido_id` | `text` | **Partition Key** | Identificador del encuentro. |
| `metrica` | `text` | **Clustering Column** | Nombre de la métrica ('TOTAL_COMENTARIOS', 'COMENTARIOS_ES', etc.). |
| `valor` | `counter` | Columna regular | Contador atómico acumulado. |

#### Desglose de la Clave Primaria:
- **Partition Key:** `((partido_id))`
- **Clustering Column:** `metrica`

---

## 3. Identificadores, Inmutabilidad y Navegación de Datos

### 3.1. Semántica y Derivación de `comentario_id` (TimeUUID)
Se adoptó `timeuuid` como identificador fundamental de cada comentario. Esta elección técnica aporta ventajas decisivas:
- **Unicidad global sin coordinación:** Se genera en el cliente o nodo coordinador combinando la dirección física, la marca temporal de 100 nanosegundos y un número secuencial, eliminando secuencias centralizadas o bloqueos distribuidos.
- **Timestamp embebido y derivabilidad:** Permite extraer la marca temporal exacta de emisión directamente del identificador. Con ello, la aplicación deriva matemáticamente el `bloque_temporal` truncando el timestamp a la ventana de 5 minutos, sin necesidad de almacenar columnas intermedias de enlace.

### 3.2. Simplificación del Flujo de Moderación y Mutabilidad del Idioma
La decisión definitiva de excluir `idioma` de la clave de partición aporta beneficios operativos sustanciales:
- **Actualización unívoca sin sobrecarga:** Para cambiar el `estado_moderacion` de un comentario en `comentarios_feed`, la clave requerida es únicamente `(partido_id, bloque_temporal, comentario_id)`. Como el flujo de moderación se activa en el contexto del feed del partido y el `bloque_temporal` es derivable de `comentario_id`, la operación se ejecuta en una única llamada sin requerir estructuras de lookup externas.
- **Mutabilidad y corrección lingüística:** Si un comentario requiere reclasificar su idioma, se realiza un `UPDATE` directo sobre la columna regular `idioma`. No se requiere una eliminación (`DELETE`) ni una reinserción (`INSERT`), eliminando por completo la generación perjudicial de *tombstones*.
