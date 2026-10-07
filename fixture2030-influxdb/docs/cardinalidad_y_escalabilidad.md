# Cardinalidad y Escalabilidad — InfluxDB (Hito 8)

## Plataforma del Fixture del Mundial 2030 — Ingeniería de Datos II

---

## 1. Análisis de Cardinalidad y Dimensiones

La **cardinalidad de series** es el número total de series temporales únicas generadas en una base de datos InfluxDB. Se define como el producto cartesiano de los valores únicos de todas las etiquetas (tags) indexadas:
$$\text{Cardinalidad Total} = \sum_{\text{tablas}} \left( \prod_{\text{tag} \in \text{Tags}(\text{tabla})} |\text{Valores Únicos de tag}| \right)$$

Una cardinalidad descontrolada (*cardinality explosion*) aumenta la cantidad de series, que condiciona índice, memoria y desempeño de consultas y escrituras (Clase 9). Por ello, el diseño del Mundial 2030 clasifica estrictamente qué atributos pertenecen al índice de tags y cuáles deben mantenerse exclusivamente como métricas (`fields`).

### 1.1 Variación Esperada de cada Dimensión (Datos Reales de los CSV)
A partir de los archivos de importación oficiales (`fixture2030-neo4j/import/`), los valores únicos por dimensión son:
- `partido_id`: **127** valores únicos (`P-001` a `P-127` en `partidos.csv`).
- `equipo_id`: **64** selecciones nacionales en el torneo (`equipos.csv`), exactamente 2 por partido en `participaciones.csv`.
- `jugador_id`: **2.794** asignaciones titulares efectivas en los 127 partidos (exactamente 22 titulares por partido en `alineaciones.csv`).
- `sede_id`: **16** estadios oficiales (`sedes.csv`).
- `region`: **6** confederaciones continentales (`equipos.csv`: `CAF`, `UEFA`, `CONMEBOL`, `CONCACAF`, `AFC`, `OFC`).

### 1.2 Cálculo de Series Temporales por Tabla (RF11)

El cálculo de series temporales no es un producto cartesiano ciego, sino que responde a las restricciones de integridad y calendario del torneo:

1. **Tabla `tracking_jugador`:**
   - Tags: `partido_id`, `jugador_id`, `equipo_id`.
   - Restricción: En cada uno de los 127 partidos participan exactamente 22 jugadores titulares.
   - Total de series:
     $$\text{Series}_{\text{tracking\_jugador}} = 127 \times 22 = \mathbf{2.794\ \text{series}}$$
2. **Tabla `tracking_pelota`:**
   - Tags: `partido_id`.
   - Restricción: Hay 1 pelota oficial por partido.
   - Total de series:
     $$\text{Series}_{\text{tracking\_pelota}} = 127 \times 1 = \mathbf{127\ \text{series}}$$
3. **Tabla `estadisticas_partido`:**
   - Tags: `partido_id`, `equipo_id`, `sede_id`.
   - Restricción: Cada partido se disputa en 1 sede única y entre 2 selecciones participantes (`participaciones.csv`).
   - Total de series:
     $$\text{Series}_{\text{estadisticas\_partido}} = 127 \times 2 = \mathbf{254\ \text{series}}$$
4. **Tabla `actividad_usuarios`:**
   - Tags: `partido_id`, `region`.
   - Restricción: Se monitorean las 6 confederaciones continentales por cada partido disputado.
   - Total de series:
     $$\text{Series}_{\text{actividad\_usuarios}} = 127 \times 6 = \mathbf{762\ \text{series}}$$

$$\mathbf{Cardinalidad\ Total\ del\ Sistema} = 2.794 + 127 + 254 + 762 = \mathbf{3.937\ \text{series}}$$

Una cardinalidad de **3.937 series** es óptima y altamente eficiente para el motor de almacenamiento de InfluxDB 3 (diseñado para gestionar cientos de miles a millones de series sin penalización).

---

## 2. Justificación de Atributos Excluidos de Tags (RNF5)

Un principio de diseño fundamental en series temporales es: **ningún atributo de alta cardinalidad o valor continuo debe ser definido como tag**.

Se justifican las exclusiones específicas:

1. **Coordenadas espaciales (`x_m`, `y_m`, `z_m`):**
   - *Por qué NO son tags:* Las posiciones en cancha son valores continuos con infinitos decimales. Si `x_m` o `y_m` fuesen tags, cada nueva coordenada crearía una nueva serie temporal en cada segundo, provocando la creación de más de 15 millones de series distintas y agotando la memoria de metadatos de InfluxDB en segundos.
   - *Ubicación correcta:* `fields` numéricos de punto flotante.
2. **Velocidad instantánea (`velocidad_kmh`):**
   - *Por qué NO es tag:* Es una magnitud física continua que varía segundo a segundo.
   - *Ubicación correcta:* `field` (permite calcular agregaciones `AVG`, `MAX`).
3. **Métricas porcentuales y contadores (`posesion_pct`, `distancia_acum_m`, `tiros_acumulados`, `pases_intervalo`):**
   - *Por qué NO son tags:* Son medidas acumuladas o de muestra que cambian en cada reporte. Los tags solo deben identificar *quién* o *dónde* se emite el dato, nunca *qué valor* toma la medida.
   - *Ubicación correcta:* `fields` (numéricos enteros o flotantes).
4. **Identificadores de usuario individual o sesión (`usuario_id`, `session_token`):**
   - *Por qué NO son tags:* Si el tráfico de streaming incluyera el ID de cada uno de los millones de hinchas como tag, la cardinalidad explotaría a millones de series efímeras de corta vida. La plataforma solo monitorea la agregación por `region`.
   - *Ubicación correcta:* Fuera del modelo de InfluxDB (los datos de usuario y sesión residen en Cassandra y Redis).
5. **Identificador único por punto / UUID por lectura:**
   - *Por qué NO existe:* En InfluxDB la unicidad de una fila está dada de forma natural por la tupla `(serie, timestamp)`. Agregar un `punto_id` sintético como tag generaría una serie por cada punto físico escrito.

### Contraste con el Caso Explosivo (Ejemplo ilustrativo de Clase 9)
Si un diseñador inexperto colocara un identificador único por observación o las coordenadas como tags en `tracking_jugador`:
- Cardinalidad resultante: $15.087.600 \text{ series}$.
- Consecuencia (Clase 9): la cantidad de series deja de estar acotada por las dimensiones del torneo y se aproxima al volumen total de puntos, con el impacto en índice, memoria y desempeño que la clase describe. No se ejecutó este caso.
- En contraste, con nuestro modelo controlado de **3.937 series**, la cantidad de series queda acotada por las dimensiones del torneo. Observado en el laboratorio: la carga de 16.870.680 puntos se completó sin líneas rechazadas.

---

## 3. Estrategia de Carga Masiva para 16,6M+ Puntos (RF12)

Para ingerir los **16.637.000 puntos** calculados sin degradar el motor, se establece una estrategia diferenciada entre la prueba de laboratorio ejecutada localmente y la arquitectura proyectada para producción:

### 3.1 Prueba de Laboratorio Ejecutada Localmente
- **Generador desacoplado:** Script Python puro (`scripts/generacion_puntos.py`) utilizando únicamente la biblioteca estándar (`csv`, `random`, `datetime`), con semilla pseudoaleatoria fija (`seed=2030`) que garantiza determinismo absoluto entre ejecuciones (RF7).
- **Formato Line Protocol (`.lp`):** Archivos planos generados en disco estructurados según el estándar de InfluxDB:
  ```text
  tracking_jugador,partido_id=P-001,equipo_id=ARG,jugador_id=ARG-10 x_m=52.3,y_m=34.1,velocidad_kmh=18.4,distancia_acum_m=120.5 1907409600
  ```
- **Ingesta en lotes fijos (Batching):** Script de carga (`scripts/carga_lotes.sh`) que agrupa las escrituras en bloques fijos de **10.000 líneas** por invocación HTTP/CLI. Esto minimiza el overhead de red y llamadas a sistema.
- **Precisión temporal declarada:** Precisión explícita en segundos (`precision=second`).
- **Manejo de errores y reintentos:** Mecanismo simple de reintentos ante error de escritura y volcado de registros anómalos o rechazados a un log de auditoría.
- **Prueba previa de humo:** Ejecución de 1 partido completo previa a la carga masiva total, con el fin de validar sintaxis de Line Protocol, tipos de datos y persistencia.

### 3.2 Arquitectura Proyectada para Producción (Escala Teórica Mundial)
En un escenario de despliegue real a gran escala durante un Mundial (PDF8 §5.4):
- **Ingesta concurrente particionada:** Múltiples procesos o trabajadores independientes ingestando en paralelo la telemetría de los partidos en juego (particionamiento por `partido_id`).
- **Búfer de desacople:** Un búfer intermedio que absorba las ráfagas de los sensores de estadio antes de persistir en InfluxDB, evitando saturar los puertos de ingesta.
- **Regulación de flujo (Backpressure):** Mecanismo de control para regular la tasa de envío cuando la base no alcance a absorber la carga.

*Nota:* Esta arquitectura distribuida es únicamente una **proyección teórica de diseño**. En el laboratorio del Hito 8 la carga se ejecuta localmente mediante el script en lotes de 10.000 líneas.

---

## 4. Límites del Entorno de Laboratorio

Las mediciones del módulo se realizan sobre el hardware local del equipo:
- **Procesador:** Apple M1 Pro (8 núcleos, medido con `sysctl`).
- **Memoria RAM:** 16 GB.
- **Almacenamiento:** Disco SSD local APFS (173 GiB libres al ejecutar la Fase 3).
- **Restricciones locales:**
  - Ejecución en contenedor Docker mononodo sobre la máquina de desarrollo.
  - La ingesta masiva de 16,6M de puntos se ejecuta secuencialmente en un solo hilo para garantizar trazabilidad y reproducibilidad estricta de la prueba.
  - Los tiempos y tasas de ingesta observados serán registrados de forma empírica en `docs/evidencia/01_generacion_y_carga.txt` durante la Fase 4 sin extrapolaciones teóricas no verificadas.
