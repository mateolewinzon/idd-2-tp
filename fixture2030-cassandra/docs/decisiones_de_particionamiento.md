# Decisiones de Particionamiento — Subsistema de Comentarios Masivos (Hito 6)

## Plataforma del Fixture del Mundial 2030 — Ingeniería de Datos II

---

## 1. Continuidad y Evolución Metodológica respecto a Hitos Previos

En estricto cumplimiento con la regla metodológica del grupo, el diseño de este hito no surge como una formulación aislada ni recurre a recetas genéricas, sino como la **continuidad y el refinamiento formal** de los acuerdos asentados en las etapas preliminares del proyecto:

1. **Decisiones del Hito 2 (Selección Tecnológica):**
   - El subsistema de comentarios fue asignado exclusivamente a **Apache Cassandra** debido a su capacidad intrínseca para absorber flujos extremos de escritura distribuida en tiempo real (*write-heavy*), escalabilidad horizontal lineal y tolerancia a particiones de red.
2. **Definiciones Vinculantes del Hito 3 (Sección 3 — Particionamiento y Consistencia):**
   - El documento del Hito 3 estableció explícitamente para comentarios:
     > *"Criterio de particionamiento: particionamiento compuesto por identificador de partido combinado con ventana temporal. Se identifica un riesgo crítico de hotspot si se particionara únicamente por partido_id, ya que todo el tráfico de un partido de alta audiencia recaería sobre un único nodo del cluster."*
   - Asimismo, el Hito 3 clasificó este subsistema bajo una **estrategia AP** (alta disponibilidad con consistencia eventual), asumiendo que la prioridad absoluta es que el usuario pueda publicar y visualizar comentarios sin bloqueos, aceptando una convergencia asincrónica entre réplicas.

El presente documento formaliza la **decisión arquitectónica definitiva del grupo**: particionamiento compuesto por `(partido_id, bloque_temporal)` con ventana fijada en 5 minutos, segregación CQRS con TTL de 14 días bajo TWCS, y asunción explícita de los compromisos cuantitativos en partidos de máxima afluencia.

---

## 2. La Decisión Central: Particionamiento Compuesto por Partido y Bloque Temporal

Para resolver la ingestión masiva y la lectura paginada del feed en vivo (`comentarios_feed`), la clave de partición adoptada es estrictamente:

$$\text{Partition Key} = (\text{partido\_id}, \text{bloque\_temporal})$$

con ordenamiento de clustering descendente por `comentario_id` (`timeuuid`).

El campo `idioma` se mantiene como una **columna regular informativa y de filtrado**, excluyéndose deliberadamente de la clave de partición.

### 2.1. Justificación de la Exclusión del Idioma y Adopción de `((partido_id, bloque_temporal))`
1. **Simplicidad de Enrutamiento y Escritura:** Al no requerir la dimensión lingüística en la clave primaria, la capa de ingestión no necesita clasificar sincrónicamente el texto ni validar perfiles lingüísticos antes de direccionar la inserción en el cluster. La tupla `(partido_id, bloque_temporal)` se calcula inmediatamente en el coordinador a partir del instante de llegada.
2. **Compromiso Asumido (Feed Global y Filtrado en la Capa de Aplicación):** Se asume formalmente como decisión de diseño que el feed recuperado desde Cassandra para una ventana temporal es un flujo global. Si el usuario desea consumir el feed filtrado por su lengua materna, el filtrado fino se realiza en la memoria de la capa de aplicación (backend o cliente web/mobile). Esto evita crear particiones diminutas y dispersas por idiomas secundarios y simplifica la infraestructura de lectura.
3. **Mutabilidad del Idioma sin Generación de Tombstones:** Al ser una columna regular, cualquier reclasificación o corrección posterior del idioma se realiza mediante un `UPDATE` puntual. No se requiere ejecutar un `DELETE` seguido de un `INSERT`, erradicando la proliferación de *tombstones* en disco.
4. **Lookup Directo en Moderación:** La clave de la fila en `comentarios_feed` depende únicamente de `partido_id`, `bloque_temporal` y `comentario_id`. Dado que el `bloque_temporal` es derivable matemáticamente de la marca temporal contenida en el propio `timeuuid`, la acción de moderación no precisa tablas intermedias de resolución.
5. **Mecanismo Físico de Distribución de Carga:** Cassandra calcula el token de distribución aplicando Murmur3 sobre la clave de partición:
   $$\text{Token} = \text{Murmur3}\big(\text{partido\_id} \parallel \text{bloque\_temporal}\big)$$
   A medida que el partido avanza y se suceden los bloques de 5 minutos, el hash asigna la partición activa a un conjunto diferente de réplicas en el anillo. De este modo, la carga de escritura rota periódicamente a lo largo de los servidores del cluster, eliminando el riesgo de saturar térmicamente un único nodo durante los 150 minutos del evento.

---

## 3. Dimensionamiento Cuantitativo y Evaluación Matemática

### 3.1. Supuestos Operativos del Torneo
- **Duración activa del encuentro:** 150 minutos (9.000 segundos).
- **Ventana temporal del bloque:** Fijada en **5 minutos** (30 bloques totales por partido).
- **Partido de bajo interés:** 100.000 comentarios totales.
- **Partido popular / destacado:** 1.000.000 de comentarios totales.
- **Final del Mundo:** 5.000.000 de comentarios totales.
- **Peso de fila:** ~250 bytes sin comprimir.
- **Límites operativos de Apache Cassandra:**
  - Límite máximo recomendado por partición: **~100.000 filas**.
  - Tamaño máximo recomendado en disco: **~100 MB**.
  - Con filas de 250 bytes, 100.000 filas ocupan ~25 MB sin comprimir (~7-10 MB comprimidos con LZ4). **El factor crítico que limita el diseño es la cantidad de filas por partición**, y no el tamaño en disco.

### 3.2. Evaluación Matemática por Escenario de Partido

Al unificar todos los idiomas dentro de la partición temporal de 5 minutos:

| Escenario de Partido | Volumen Total Comentarios | Cantidad de Bloques (150 min / 5 min) | Filas por Partición (Bloque de 5 min) | Tamaño Estimado en Disco (Comprimido) | Estado frente a la Guía (~100.000 filas) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Partido de Bajo Interés** | 100.000 | 30 bloques | **3.333 filas** | ~0,3 MB | **Ampliamente seguro** |
| **Partido Popular / Destacado** | 1.000.000 | 30 bloques | **33.333 filas** | ~3,3 MB | **Óptimo (1/3 del límite)** |
| **Final del Mundo / Semifinal** | 5.000.000 | 30 bloques | **166.666 filas** | ~16,6 MB | **Compromiso asumido (1,6x del límite)** |

### 3.3. Justificación del Compromiso Asumido en la Final (166.000 filas)
La matemática demuestra que para un partido popular de 1.000.000 de comentarios, el bloque de 5 minutos genera **33.333 escrituras por partición**, lo que representa un valor óptimo que opera a un tercio del umbral preventivo de Cassandra.

En el caso extraordinario de la Final del Mundo (5.000.000 de comentarios), una partición de 5 minutos alcanza en promedio unas **166.666 filas**, superando moderadamente el límite sugerido de 100.000 filas.

**El grupo asume y documenta explícitamente este trade-off como plenamente válido en virtud de los siguientes criterios técnicos:**
1. **Pico Excepcional y Aislado:** La superación ocurre exclusivamente en 1 de los 127 partidos del torneo (el 0,78% del certamen).
2. **Rechazo a la Sobrefrecuencia de Particiones:** Fragmentar el diseño global a bloques de 1 o 2 minutos para acomodar un único encuentro penalizaría a los 126 partidos restantes, multiplicando de forma innecesaria la cantidad de particiones vacías o diminutas y sobrecargando la capa cliente con saltos constantes de ventana en la paginación.
3. **Margen de Seguridad en Megabytes:** Incluso con 166.666 filas, la partición ocupa menos de 17 MB en disco comprimido, muy por debajo de la barrera de riesgo de los 100 MB. Con hardware moderno aprovisionado con almacenamiento SSD NVMe y memoria JVM dimensionada (heap de 8 a 16 GB), Cassandra gestiona particiones de 166.000 filas con total solvencia sin comprometer la estabilidad del nodo.

---

## 4. Segregación CQRS: Tabla en Caliente (`comentarios_feed`) vs. Histórica (`comentarios_historico`)

Para armonizar las necesidades transaccionales extremas del vivo con los requerimientos analíticos y de auditoría sin colisionar en rendimiento, se adopta el **patrón CQRS a nivel de base de datos**:

```
                       ┌────────────────────────────┐
                       │  Backend Ingestión Dual    │
                       └─────────────┬──────────────┘
                                     │
                 ┌───────────────────┴───────────────────┐
                 │ (Dual-Write asincrónico e idempotente)│
                 ▼                                       ▼
    ┌──────────────────────────┐           ┌──────────────────────────┐
    │     comentarios_feed     │           │   comentarios_historico  │
    ├──────────────────────────┤           ├──────────────────────────┤
    │ PK: ((partido, bloque))  │           │ PK: ((partido_id)), id   │
    │ TTL: 14 días             │           │ TTL: No tiene (Infinito) │
    │ Compaction: TWCS (1d)    │           │ Compaction: STCS         │
    │ Propósito: Feed en Vivo  │           │ Propósito: Analítica RF10│
    └──────────────────────────┘           └──────────────────────────┘
```

### 4.1. Vía en Caliente (`comentarios_feed`): TTL de 14 Días y TWCS
- **TTL de 14 Días (1.209.600 segundos):** El interés transaccional de los aficionados por consultar y scrollear el feed en vivo de un partido decae a cero pasadas dos semanas de su disputa.
- **Sinergia con TimeWindowCompactionStrategy (TWCS):** TWCS organiza las SSTables en ventanas de tiempo discretas basadas en la fecha de inserción. Al transcurrir los 14 días y expirar todos los registros de una SSTable, Cassandra descarta el archivo de datos directamente a nivel de sistema operativo (*drop file*). Esto erradica por completo la compactación celda a celda y previene la formación masiva de *tombstones*, manteniendo el cluster limpio y de alta respuesta.

### 4.2. Vía Histórica (`comentarios_historico`): Persistencia y Analítica (RF10)
- **Particionamiento por `((partido_id))`:** Agrupa la totalidad del partido en una única partición física secuencial, optimizada para escaneos batch y generación de métricas de interacción pospartido.
- **Sin TTL y con STCS:** Al ser una tabla de solo inserción (*append-only*) sin borrados ni expiraciones, la estrategia predeterminada `SizeTieredCompactionStrategy` (STCS) resulta óptima para consolidar SSTables de tamaño comparable. Responde directamente al requerimiento RF10 y a la pregunta 12 de la rúbrica.
- **Dual-Write Asincrónico:** Ambas tablas reciben el mismo registro con idéntico `comentario_id` (`timeuuid`). Al ser inserciones idempotentes, se asegura la consistencia eventual requerida por RNF7.

---

## 5. Comparación contra Alternativas Descartadas

| Alternativa Evaluada | Clave de Partición | Causa Formal de Descarte |
| :--- | :--- | :--- |
| **Particionar solo por `partido_id`** | `((partido_id), comentario_id)` | Colapso por hotspot masivo. En la final acumularía 5.000.000 de filas y 1,25 GB en una sola partición (**50x sobre el límite**), saturando la JVM y un único nodo del anillo. |
| **Bucketing con Idioma** | `((partido_id, idioma, bloque), id)` | Descartada por complejidad y dispersión. Fragmenta el feed en particiones pequeñas para idiomas minoritarios, complica la lógica de enrutamiento y hace que el idioma sea inmutable a nivel de clave primaria. |
| **Bloques de 15 minutos** | `((partido_id, bloque_15m), id)` | Descartada. En partidos populares genera 100.000 filas (al límite) y en la final genera 500.000 filas (**5x sobre el límite**), degradando severamente las compactaciones. |
| **Bloques de 1 minuto** | `((partido_id, bloque_1m), id)` | Descartada por sobrefragmentación. Genera 150 particiones por partido, provocando particiones vacías en partidos de bajo interés y obligando a los clientes a paginar de forma discontinua. |

---

## 6. Geografía, Replicación y Niveles de Consistencia

> **Formulación Arquitectónica Obligatoria:**
> - **La clave de partición** resuelve la **distribución homogénea de carga** y el tamaño físico de almacenamiento en el cluster.
> - **La estrategia de replicación** resuelve la **cercanía geográfica al usuario** y la tolerancia a fallas entre centros de datos.
> - **El nivel de consistencia** resuelve **cuánto tiempo y cuántas réplicas se espera** para dar por confirmada una operación.

### 6.1. Replicación en Producción
En producción, se emplea `NetworkTopologyStrategy` con réplicas locales en cada región del Mundial:
- `datacenter_europa: 3`
- `datacenter_sudamerica: 3`
- `datacenter_africa: 3`

Cada centro de datos aloja una réplica de cada partición de 5 minutos. Los usuarios leen y escriben en su datacenter local con `LOCAL_ONE`, absorbiendo el impacto con latencia mínima (< 5 ms) sin cruzar enlaces transoceánicos. La sincronización entre continentes es asincrónica, alineada con la clasificación AP del Hito 3.

### 6.2. Consistencia Ajustada por Operación

| Operación | Nivel de Consistencia | Justificación Técnica |
| :--- | :--- | :--- |
| **Escritura de nuevo comentario** | `LOCAL_ONE` | Maximiza la tasa de ingestión (objetivo: 10.000 ops/seg). Confirma al persistir en CommitLog y Memtable local. |
| **Lectura del feed en vivo** | `LOCAL_ONE` | Garantiza latencias ultra bajas (< 5 ms) en lecturas concurrentes masivas. |
| **Escritura de moderación (Ocultar)** | `LOCAL_QUORUM` | Garantiza que el contenido prohibido sea ocultado en la mayoría de las réplicas locales, evitando su reaparición momentánea. |
| **Lectura analítica / Auditoría (RF10)** | `LOCAL_QUORUM` | Garantiza consistencia fuerte al consolidar reportes pospartido. |
| **Entorno de Laboratorio (Hito 6)** | `SimpleStrategy` / `ONE` (`RF=1`) | **Nodo único en Docker Compose sin tolerancia a fallas**, exclusivo para validación funcional del modelo tabular. |
