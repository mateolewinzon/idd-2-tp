# Patrones de Acceso — Subsistema de Comentarios Masivos (Hito 6)

## Plataforma del Fixture del Mundial 2030 — Ingeniería de Datos II

---

## 1. Análisis del Problema de Volumen y Concurrencia

El subsistema de comentarios del Mundial 2030 gestiona la interacción social en tiempo real de millones de espectadores distribuidos por todo el mundo durante la transmisión de los encuentros deportivos. A diferencia de las entidades de catálogo de equipos y jugadores resueltas en MongoDB (Hito 4) y de la red de relaciones de torneos y eventos en Neo4j (Hito 5), el flujo de comentarios presenta un comportamiento asimétrico caracterizado por:
- Tasa extrema de ingestión en ráfagas (*write-heavy*).
- Lecturas continuas y paginadas de los últimos mensajes emitidos (*read-intensive* en la cabeza del feed).
- Sensibilidad extrema a la latencia de escritura para no degradar la experiencia de interactividad.

### 1.1. Supuestos Operativos del Torneo (Modelo de Simulación)
Para el dimensionamiento del sistema se establecen los siguientes supuestos cuantitativos (planteados como hipótesis de diseño operacional, no como hechos consumados):
1. **Universo de encuentros:** 127 partidos totales a disputarse a lo largo del certamen internacional.
2. **Ventana de actividad máxima:** Aproximadamente 150 minutos por encuentro (considerando previa, primer tiempo, entretiempo, segundo tiempo y adición/conferencias).
3. **Distribución del tráfico entre partidos:** El interés del público no es uniforme, observándose un marcado sesgo:
   - *Partidos de bajo interés / fase de grupos periférica:* Entre 50.000 y 200.000 comentarios totales.
   - *Partidos destacados / clásicos y eliminatorias intermedias:* Aproximadamente 1.000.000 de comentarios totales.
   - *Final del Mundo y semifinales decisivas:* Entre 3.000.000 y 5.000.000 de comentarios totales por encuentro.
4. **Tasas promedio de escritura:**
   - Para un partido de 1.000.000 de comentarios en 150 minutos (9.000 segundos): el régimen promedio es de **111 comentarios por segundo**.
   - Para la final de 5.000.000 de comentarios en 150 minutos: el régimen promedio asciende a **555 comentarios por segundo**.
5. **Comportamiento en ráfaga (Picos de Gol / Eventos Críticos):**
   - Ante eventos extraordinarios (un gol convalidado, un penal decisivo en el minuto 90, una tarjeta roja o la definición por penales), el volumen de comentarios se multiplica entre **10x y 20x** respecto de la tasa media.
   - En una final, un pico de 15x a 20x sobre una base de 555 ops/seg proyecta una demanda instantánea de entre 8.325 y 11.100 escrituras concurrentes por segundo.
   - De este análisis surge el **objetivo técnico del módulo: soportar un régimen de 10.000 escrituras por segundo** de forma sostenida durante picos de demanda.
6. **Peso promedio por registro:** Se estima una fila de comentario en aproximadamente **250 bytes** sin comprimir (incluyendo identificadores, marcas temporales, texto del mensaje, estado de moderación y metadatos de usuario).
7. **Cuello de botella de almacenamiento en particiones:** En Apache Cassandra, las recomendaciones operativas señalan no superar las ~100.000 filas por partición ni los ~100 MB de tamaño en disco. Con filas de 250 bytes, 100.000 registros ocupan apenas ~25 MB sin comprimir (~7-10 MB comprimidos con LZ4). Por lo tanto, **el factor limitante primario que restringe el diseño es la cantidad de filas por partición**, y no el tamaño en megabytes.

---

## 2. Metodología de Diseño: *Query-Driven Modeling* y Segregación CQRS

En bases de datos columnares distribuidas como Apache Cassandra, no existen las operaciones de combinación relacional (`JOIN`), las cláusulas `OR`, ni la capacidad de indexar arbitrariamente cualquier campo sin penalizaciones severas de red y CPU.

El modelado debe estar estrictamente subordinado a los patrones de consulta requeridos por el negocio. Se adopta el **patrón CQRS (Command Query Responsibility Segregation) a nivel de almacenamiento**, separando explícitamente:
1. **La vía de lectura transaccional en caliente (`comentarios_feed`):** Optimizada para el consumo en vivo del feed, estructurada en ventanas de 5 minutos, con TTL de 14 días y compactación TWCS.
2. **La vía analítica e histórica (`comentarios_historico`):** Estructura consolidada permanente orientada a auditoría pospartido y reportes globales (RF10 y consulta analítica de rúbrica).

Ambas estructuras se nutren en la ingestión mediante **Dual-Write asincrónico e idempotente** desde la capa de backend, garantizando el cumplimiento estricto del requerimiento RNF7.

---

## 3. Catálogo de Preguntas de Negocio Prioritarias

A continuación se formalizan los requerimientos de consulta que guían la arquitectura tabular del subsistema:

### Pregunta 1 (Q1) — Feed en vivo del partido por ventana temporal
- **Descripción:** Visualizar los comentarios más recientes emitidos durante un partido determinado en una ventana temporal activa de 5 minutos, ordenados de forma estrictamente cronológica inversa (los más nuevos primero).
- **Parámetros de entrada:** `partido_id` (UUID/texto), `bloque_temporal` (timestamp truncado al inicio de la ventana de 5 minutos) y cursor de paginación sobre `comentario_id`.
- **Orden de resultados:** Cronológico descendente (último comentario emitido al inicio).
- **Justificación de acceso:** Es la consulta más caliente del sistema, invocada masivamente por clientes concurrentes para refrescar la interfaz en vivo. Debe responder en un único seek sobre la partición del bloque temporal correspondiente.
- **Compromiso asumido (Feed Global y Filtrado en Aplicación):** La consulta a Cassandra recupera el flujo de comentarios de la ventana sin filtrar por idioma a nivel de clave primaria. Si el cliente o la interfaz requiere visualizar únicamente mensajes en un idioma particular, el filtrado fino se delega a la memoria de la capa de aplicación (backend o cliente). Esto simplifica drásticamente el enrutamiento de escritura y permite desplegar vistas globales del partido sin costosas operaciones distribuidas de *scatter-gather*.

### Pregunta 2 (Q2) — Historial de actividad de un usuario
- **Descripción:** Permitir a un usuario consultar la lista de todos los comentarios que ha emitido a lo largo del torneo desde su perfil personal, ordenados desde el más reciente al más antiguo.
- **Parámetros de entrada:** `usuario_id` (UUID/texto).
- **Orden de resultados:** Cronológico descendente.
- **Justificación de acceso:** No puede resolverse filtrando la tabla de partidos por `usuario_id`, ya que obligaría a escanear todas las particiones del cluster. Requiere una tabla dedicada particionada exclusivamente por usuario.

### Pregunta 3 (Q3) — Cola de moderación y revisión de contenido
- **Descripción:** Presentar a los moderadores de la plataforma los comentarios que han sido reportados o marcados para revisión dentro de un estado operativo específico, ordenados por fecha de emisión.
- **Parámetros de entrada:** `estado_moderacion` ('PENDIENTE', 'REPORTADO', 'REVISADO') y ventana de fecha (`fecha`).
- **Orden de resultados:** Cronológico ascendente (FIFO).
- **Justificación de acceso:** La moderación procesa lotes de comentarios conflictivos sin conocer a priori qué partido o usuario los originó. Requiere una cola de trabajo optimizada.

### Pregunta 4 (Q4) — Métricas y contadores de interacción (Likes acumulados)
- **Descripción:** Obtener la cantidad consolidada de votos favorables ("likes") que ha recibido un comentario en particular.
- **Parámetros de entrada:** `comentario_id` (TimeUUID).
- **Justificación de acceso:** Debido a la alta concurrencia de interacción social, actualizar un contador numérico tradicional mediante lecturas y escrituras atómicas genera condiciones de carrera y pérdida de incrementos. Requiere un modelado desacoplado mediante el tipo nativo `counter` de Cassandra.

### Pregunta 5 (Q5) — Auditoría histórica y analítica pospartido (RF10)
- **Descripción:** Recuperar la totalidad de los comentarios registrados durante un partido una vez finalizado el encuentro, con propósitos de auditoría, archivo reglamentario, minería de texto o generación de métricas de interacción consolidada.
- **Parámetros de entrada:** `partido_id`.
- **Orden de resultados:** Cronológico ascendente / secuencial.
- **Justificación de acceso:** Patrón de acceso analítico en frío (*cold storage*). A diferencia del feed en vivo, no requiere segmentación en bloques de 5 minutos ni expira con TTL. Responde directamente al requerimiento RF10 de estructura secundaria para reportes y a la pregunta 12 de la rúbrica.

---

## 4. Matriz de Trazabilidad: Consulta vs. Tabla Propuesta

| Código | Consulta de Negocio | Frecuencia Operativa | Tabla Destino Propuesta | Estrategia de Clave Primaria |
| :--- | :--- | :--- | :--- | :--- |
| **Q1** | Feed en vivo por partido y bloque de 5 min | Crítica (Millones/seg) | `comentarios_feed` | `((partido_id, bloque_temporal), comentario_id)` con clustering desc (TTL 14d) |
| **Q2** | Historial de comentarios por usuario | Media (Demanda perfil) | `comentarios_por_usuario` | `((usuario_id), comentario_id)` con clustering desc |
| **Q3** | Cola de moderación de comentarios | Baja / Controlada | `comentarios_moderacion` | `((estado_moderacion, fecha), comentario_id)` |
| **Q4** | Conteo atómico de likes por comentario | Alta (Interacción en vivo) | `likes_por_comentario` | `((comentario_id))` asociada a columna tipo `counter` |
| **Q5** | Archivo analítico histórico pospartido (RF10) | Baja (Offline / Batch) | `comentarios_historico` | `((partido_id), comentario_id)` permanente sin TTL |
| **Q6** | Totalizador de comentarios por partido | Media / Monitoreo | `contadores_por_partido` | `((partido_id), metrica)` asociada a `counter` para evitar `COUNT(*)` |
