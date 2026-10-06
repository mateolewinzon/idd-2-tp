# Modelo Multidimensional — Series Temporales en InfluxDB (Hito 8)

## Plataforma del Fixture del Mundial 2030 — Ingeniería de Datos II

---

## 1. Fundamentos del Modelo en InfluxDB

A diferencia de las bases relacionales, documentales o de grafos, InfluxDB estructura la información bajo el paradigma **multidimensional de series temporales**:
- **Tabla (Measurement):** Define el fenómeno físico u operativo que se observa (ej. movimiento de un jugador, estado del balón).
- **Etiquetas (Tags):** Metadatos indexados de tipo texto (`string`) que identifican el origen o contexto de la medición (dimensiones de consulta). Se almacenan en el índice invertido y determinan la serie temporal.
- **Campos (Fields):** Valores numéricos o de estado observados en cada instante de tiempo. **No están indexados**. Son las métricas sobre las cuales se aplican funciones matemáticas o de agregación (`AVG`, `MAX`, `SUM`, etc.).
- **Marca de tiempo (Timestamp):** El eje temporal fundamental de la base de datos. Para el Mundial 2030 se declara con **precisión explícita en segundos (`s`)** en todas las operaciones de escritura y consulta (RF6 / RNF6).
- **Serie Temporal:** La combinación única de:
  $$\text{Serie} = \text{Tabla} + \text{Conjunto de pares Tag-Valor}$$
  Dentro de una serie, cada punto temporal es un vector de campos asociados a un timestamp específico.

> **Alcance de integración:** InfluxDB almacena observaciones de telemetría de forma autónoma. No realiza `JOINs` ni enlaces de red en vivo con MongoDB, Neo4j, Cassandra ni Redis. Solo preserva la coherencia de identificadores canónicos (`partido_id`, `jugador_id`, `equipo_id`, `sede_id`).

---

## 2. Definición Tabular del Modelo

El modelo consta de cuatro (4) tablas diseñadas estrictamente a partir de los patrones de acceso documentados en `docs/patrones_de_acceso.md` (RNF4):

### 2.1 Tabla: `tracking_jugador`
Representa el desplazamiento cinemático y la odometría de cada futbolista en el campo de juego.

- **Fenómeno:** Telemetría de movimiento y rendimiento físico en cancha.
- **Tags (Dimensiones indexadas):**
  - `partido_id` (string): Identificador canónico del encuentro (`P-001` a `P-127`).
  - `jugador_id` (string): Identificador del futbolista proveniente del plantel oficial (`ARG-10`, `FRA-07`, etc.).
  - `equipo_id` (string): Identificador de la selección nacional (`ARG`, `FRA`, etc.).
- **Fields (Métricas no indexadas):**
  - `x_m` (float): Coordenada horizontal en metros (rango: $0.0$ a $105.0$).
  - `y_m` (float): Coordenada vertical en metros (rango: $0.0$ a $68.0$).
  - `velocidad_kmh` (float): Velocidad instantánea en kilómetros por hora (rango: $0.0$ a $36.0$).
  - `distancia_acum_m` (float): Odómetro acumulado en metros recorridos desde el inicio del partido.
- **Fuente del dato:** Sistema de seguimiento óptico y chips de indumentaria.
- **Precisión temporal:** Segundos (`s`). Frecuencia: 1 Hz (1 muestra por segundo).
- **Población:** Exclusivamente los **22 jugadores titulares** por encuentro (verificado en `alineaciones.csv`). Los suplentes no generan serie si no ingresan.
- **Patrones asociados:** Patrón P1 (trayectoria y mapa de calor en ventana), Patrón P2 (velocidad máxima y distancia total).

### 2.2 Tabla: `tracking_pelota`
Representa la posición espacial tridimensional y la dinámica del balón oficial del torneo.

- **Fenómeno:** Trayectoria cinemática y física del balón.
- **Tags (Dimensiones indexadas):**
  - `partido_id` (string): Identificador del encuentro (`P-001` a `P-127`).
- **Fields (Métricas no indexadas):**
  - `x_m` (float): Coordenada en longitud ($0.0$ a $105.0$).
  - `y_m` (float): Coordenada en ancho ($0.0$ a $68.0$).
  - `z_m` (float): Altura sobre el césped en metros ($0.0$ a $15.0$).
  - `velocidad_kmh` (float): Velocidad de desplazamiento del balón ($0.0$ a $140.0$).
- **Fuente del dato:** Sensor UWB/IMU interno del balón oficial y cámaras perimetrales.
- **Precisión temporal:** Segundos (`s`). Frecuencia: 1 Hz (1 muestra por segundo).
- **Patrones asociados:** Patrón P3 (trayectoria tridimensional alrededor de jugadas críticas o goles).

### 2.3 Tabla: `estadisticas_partido`
Registra las métricas de dominio y volumen táctico de cada selección durante el transcurso del encuentro.

- **Fenómeno:** Comportamiento colectivo y volumen de juego por selección.
- **Tags (Dimensiones indexadas):**
  - `partido_id` (string): Identificador del encuentro (`P-001` a `P-127`).
  - `equipo_id` (string): Identificador del seleccionado participante.
  - `sede_id` (string): Estadio/sede donde se disputa (`S-01` a `S-16`).
- **Fields (Métricas no indexadas):**
  - `posesion_pct` (float): Porcentaje de posesión instantánea (muestra entre $0.0$ y $100.0$).
  - `tiros_acumulados` (integer): Cantidad total de remates ejecutados hasta el momento (contador monótono).
  - `pases_intervalo` (integer): Cantidad de pases completados en los últimos 5 segundos (métrica de intervalo).
- **Fuente del dato:** Sistema de visión computacional y análisis estadístico en campo.
- **Precisión temporal:** Segundos (`s`). Frecuencia: cada 5 segundos (0.2 Hz).
- **Patrones asociados:** Patrón P4 (posesión temporal), Patrón P5 (resumen comparativo), Patrón P6 (ritmo de tiros), Patrón P7 (dinamismo por sede).

### 2.4 Tabla: `actividad_usuarios`
Mide la audiencia y el tráfico concurrente de usuarios que consumen la transmisión del partido por plataforma digital.

- **Fenómeno:** Carga de usuarios y telemetría de streaming.
- **Tags (Dimensiones indexadas):**
  - `partido_id` (string): Identificador del encuentro (`P-001` a `P-127`).
  - `region` (string): Confederación continental de origen del tráfico (`CAF`, `UEFA`, `CONMEBOL`, `CONCACAF`, `AFC`, `OFC`).
- **Fields (Métricas no indexadas):**
  - `usuarios_conectados` (integer): Cantidad de espectadores concurrentes activos en ese instante.
- **Fuente del dato:** Plataforma de distribución de streaming (CDN / SRE).
- **Precisión temporal:** Segundos (`s`). Frecuencia: cada 5 segundos (0.2 Hz).
- **Patrones asociados:** Patrón P8 (picos de audiencia y monitoreo de infraestructura).

---

## 3. Semántica de las Medidas y Reglas de Agregación

Un error crítico en bases de series temporales es aplicar funciones matemáticas incompatibles con la naturaleza física del dato (RF5, RF9). El sistema aplica las siguientes reglas estrictas:

| Medida | Tabla | Tipo Semántico | Comportamiento | Funciones Permitidas | Función PROHIBIDA |
|---|---|---|---|---|---|
| `velocidad_kmh` | `tracking_jugador` / `tracking_pelota` | **Muestra instantánea** | Valor medido en un punto temporal aislado. No acumulable. | `AVG`, `MAX`, `MIN` | `SUM` (sumar velocidades no tiene sentido físico) |
| `posesion_pct` | `estadisticas_partido` | **Muestra instantánea** | Distribución porcentual en la ventana. | `AVG`, `MIN`, `MAX` | `SUM` (produciría valores mayores al 100%) |
| `distancia_acum_m` | `tracking_jugador` | **Contador acumulado** | Medida monótonamente creciente (odómetro). | `MAX`, `MAX - MIN` (delta de ventana) | `SUM` (sumar lecturas acumuladas infla exponencialmente la distancia) |
| `tiros_acumulados` | `estadisticas_partido` | **Contador acumulado** | Registro total de remates en el partido. | `MAX`, `MAX - MIN` (tiros en la ventana) | `SUM` |
| `pases_intervalo` | `estadisticas_partido` | **Métrica de intervalo** | Delta de pases ocurridos exclusivamente en el período de 5 s. | `SUM` (totaliza pases en un lapso mayor) | `AVG` directo sin ponderar |
| `usuarios_conectados` | `actividad_usuarios` | **Gauge (nivel instantáneo)** | Nivel de concurrencia en un momento dado. | `MAX` (pico), `AVG` (audiencia media) | `SUM` temporal (sumar usuarios concurrentes a lo largo de 90 min distorsiona la audiencia) |

---

## 4. Evolución del Modelo y Decisiones de Arquitectura

### 4.1 Ampliación frente a Hitos Anteriores
En los Hitos 1 y 2, InfluxDB se perfiló inicialmente para el *"tracking de jugadores y pelota"*. En este Hito 8, y conforme al enunciado técnico oficial (§3 RF, §5 especificación), el alcance se amplió formalmente a cuatro tablas para abarcar:
1. Telemetría cinemática de alta frecuencia (`tracking_jugador`, `tracking_pelota`).
2. Rendimiento colectivo y táctico (`estadisticas_partido`).
3. Observabilidad de infraestructura y audiencia masiva (`actividad_usuarios`).

Esta ampliación respeta íntegramente el principio de que InfluxDB **solo almacena series numéricas temporales** y no sustituye el rol de catálogo de Mongo ni las relaciones de Neo4j.

### 4.2 Elección de Motor: InfluxDB 3 Core vs InfluxDB 2.x
El enunciado (RNF1) menciona `influxdb:latest`. Sin embargo, la verificación empírica de la Fase 0 constató que `influxdb:latest` en Docker Hub descarga la rama v2.9.1 (puerto 8086, lenguaje Flux/InfluxQL y motor TSM antiguo).

Para alinearse con la **Clase 9 oficial de la cátedra**, se adopta la imagen `influxdb:3-core`:
- Motor moderno basado en **Apache Arrow**, **DataFusion** y almacenamiento columnar en **Parquet**.
- Soporte nativo de **SQL estándar** para todas las consultas analíticas temporales (puerto 8181).
- CLI oficial `influxdb3` y gestión granular de bases de datos y tokens.

### 4.3 Manejo de Identificadores (Neo4j vs Cassandra)
Se constata que el módulo de comentarios en Cassandra utilizó identificadores sintéticos de partido (ej. `'ARG-ESP-20300624'`), mientras que la fuente de verdad del grafo en Neo4j utiliza identificadores canónicos (`'P-001'`, `'P-002'`, etc.).
- InfluxDB adopta de forma uniforme los **identificadores canónicos de Neo4j (`partido_id = 'P-xxx'`)** y los códigos de jugadores y equipos de Mongo/Neo4j (`'ARG-10'`, `'ARG'`).
- La discrepancia con los IDs de Cassandra se documenta como limitación del subsistema de comentarios previo, manteniendo consistencia con lo documentado en Redis (`fixture2030-redis/docs/modelo_clave_valor.md §5`).
