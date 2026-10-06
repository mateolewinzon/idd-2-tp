# Carga de Datos y Consultas Temporales — InfluxDB (Hito 8)

## Plataforma del Fixture del Mundial 2030 — Ingeniería de Datos II

---

## 1. Diseño del Proceso de Carga Masiva (Borrador de Especificación)

Este documento describe la especificación técnica de los scripts de ingestión, consultas temporales y agregaciones que se implementarán en la Fase 2, conforme a los requisitos del enunciado (PDF8 §8).

### 1.1 Canal de Generación e Ingestión
1. **Generador Desacoplado (`scripts/generacion_puntos.py`):**
   - Consume los archivos CSV maestros de `fixture2030-neo4j/import/` (`partidos.csv`, `participaciones.csv`, `alineaciones.csv`, `equipos.csv`, `sedes.csv`).
   - Genera archivos planos en formato **Line Protocol** (`.lp`), ignorados por Git, organizados por tabla y partido.
   - Aplica una semilla fija (`seed=2030`) en la biblioteca estándar de Python para asegurar determinismo matemático en las coordenadas, velocidades y métricas.
   - Declara explícitamente precisión temporal en segundos (`s`).
2. **Cargador por Lotes (`scripts/carga_lotes.sh`):**
   - Ingesta los datos hacia el motor InfluxDB 3 mediante lotes fijos de **10.000 líneas** por petición.
   - Implementa un paso inicial de **prueba de humo (1 partido completo)** para verificar sintaxis, esquema de tags/fields y conectividad antes de proceder con la carga masiva total.
   - Registra reintentos simples ante saturación de búfer y audita líneas rechazadas si las hubiera.

---

## 2. Catálogo de Consultas Temporales Proyectadas

Conforme a RNF8, todas las consultas analíticas acotan estrictamente su rango temporal mediante cláusulas `WHERE time >= ... AND time <= ...` y aplican filtros por dimensiones (`partido_id`, `equipo_id`, `sede_id`, `region`), evitando escaneos globales no acotados.

Las consultas se implementarán en SQL nativo (soportado por InfluxDB 3 Core sobre Apache Arrow DataFusion):

### Consulta Q1: Trayectoria y odometría de un futbolista en ventana activa (Patrón P1)
- **Objetivo:** Recuperar las coordenadas espaciales ($x,y$), la velocidad instantánea y la distancia acumulada de un jugador durante una ventana de 5 minutos de un partido determinado.
- **Tabla:** `tracking_jugador`
- **Filtros obligatorios:** `partido_id = 'P-001'`, `jugador_id = 'ARG-10'`, acotado a un rango de 300 segundos.

### Consulta Q2: Velocidades máximas y ranking de distancia por equipo (Patrón P2)
- **Objetivo:** Calcular la velocidad pico (`MAX(velocidad_kmh)`) y la distancia total recorrida (`MAX(distancia_acum_m)`) por cada jugador titular de una selección en los 90 minutos de juego.
- **Tabla:** `tracking_jugador`
- **Filtros obligatorios:** `partido_id = 'P-001'`, `equipo_id = 'ARG'`.
- **Agrupamiento:** `GROUP BY jugador_id`.

### Consulta Q3: Posicionamiento 3D del balón en ventana de gol (Patrón P3)
- **Objetivo:** Analizar la altura ($z$), trayectoria y velocidad del balón en una ventana de 60 segundos coincidente con un gol registrado.
- **Tabla:** `tracking_pelota`
- **Filtros obligatorios:** `partido_id = 'P-001'`, rango temporal de 1 minuto.

### Consulta Q4: Balance comparativo de posesión y volumen de pases (Patrones P4 y P5)
- **Objetivo:** Comparar el promedio de posesión (`AVG(posesion_pct)`), el total de remates (`MAX(tiros_acumulados)`) y los pases completados (`SUM(pases_intervalo)`) entre ambos rivales del partido.
- **Tabla:** `estadisticas_partido`
- **Filtros obligatorios:** `partido_id = 'P-001'`.
- **Agrupamiento:** `GROUP BY equipo_id`.

### Consulta Q5: Ritmo ofensivo en ventanas de 5 minutos (Patrón P6)
- **Objetivo:** Analizar la evolución de tiros por bloque temporal mediante `date_bin` de 5 minutos, calculando la diferencia del contador de tiros en cada bloque.
- **Tabla:** `estadisticas_partido`
- **Filtros obligatorios:** `partido_id = 'P-001'`, `equipo_id = 'ARG'`.

### Consulta Q6: Comparación de intensidad de juego entre dos sedes (Patrón P7)
- **Objetivo:** Contrastar el dinamismo y volumen de pases entre dos estadios distintos a lo largo de una fecha del torneo.
- **Tabla:** `estadisticas_partido`
- **Filtros obligatorios:** `sede_id IN ('S-01', 'S-02')`, rango de la jornada completa.
- **Agrupamiento:** `GROUP BY sede_id`.

### Consulta Q7: Picos de concurrencia y tráfico de streaming por región (Patrón P8)
- **Objetivo:** Identificar el pico máximo de audiencia simultánea (`MAX(usuarios_conectados)`) y el promedio de conexión por confederación durante la transmisión del partido.
- **Tabla:** `actividad_usuarios`
- **Filtros obligatorios:** `partido_id = 'P-001'`.
- **Agrupamiento:** `GROUP BY region`.

---

## 3. Casos Especiales de Validación Temporal (RF8)

El diseño contempla dos escenarios atípicos para validar la robustez del motor:
1. **Caso de Partido sin Puntos:** Consulta dirigida a un identificador de partido válido que no haya recibido telemetría (ej. por falla de enlace o partido no disputado aún). El sistema debe responder con resultado vacío en tiempo submétrico, sin provocar errores en el motor ni consultas colgadas.
2. **Caso de Dato Tardío (Late-arriving data):** Inserción deliberada de una observación con timestamp anterior al último dato recibido. InfluxDB 3 debe ubicar el dato en la partición columnar correspondiente sin descartarlo ni sobreescribir puntos posteriores.

---

## 4. Agregaciones y Downsampling Proyectado

En el script `scripts/agregaciones.sh` se implementará la consulta SQL que calcula los agregados por minuto sobre `tracking_jugador` y vuelca el resultado en la base permanente `fixture2030_resumen`:
- Ventana de agregación: `date_bin(INTERVAL '1 minute', time)`.
- Agregados por jugador: `AVG(velocidad_kmh)`, `MAX(velocidad_kmh)`, `MAX(distancia_acum_m) - MIN(distancia_acum_m)`.
- Destino: Base `fixture2030_resumen`.
