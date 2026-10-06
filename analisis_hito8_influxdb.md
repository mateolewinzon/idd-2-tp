# Análisis Hito 8 — InfluxDB — Fixture 2030

## §0 Decisiones tomadas

1. **Ubicación y Entorno**: El módulo se aloja en `fixture2030-influxdb/` dentro del repositorio del grupo (`idd-2-tp`).
   - Imagen Docker seleccionada: `influxdb:3-core` (para compatibilidad con Clase 9, binario `influxdb3`, SQL nativo y puerto 8181; documentando el desvío técnico respecto al `influxdb:latest` del PDF8 que apuntaba a v2.9.1).
2. **Tablas y Modelado**: Cuatro tablas derivadas de patrones de acceso:
   - `tracking_jugador` (tags: `partido_id`, `jugador_id`, `equipo_id`; fields: `x_m`, `y_m`, `velocidad_kmh`, `distancia_acum_m`). Solo titulares (22 por partido verificados en CSV).
   - `tracking_pelota` (tags: `partido_id`; fields: `x_m`, `y_m`, `z_m`, `velocidad_kmh`).
   - `estadisticas_partido` (tags: `partido_id`, `equipo_id`, `sede_id`; fields: `posesion_pct`, `tiros_acumulados`, `pases_intervalo`).
   - `actividad_usuarios` (tags: `partido_id`, `region`; fields: `usuarios_conectados`).
3. **Semántica de agregación**:
   - Muestras (`posesion_pct`, `velocidad_kmh`): `AVG` / `MAX`.
   - Contadores acumulados (`tiros_acumulados`, `distancia_acum_m`): `MAX` o delta, NUNCA `SUM`.
   - Intervalos (`pases_intervalo`): `SUM`.
   - Gauges (`usuarios_conectados`): `MAX` / `AVG`, NUNCA `SUM`.
4. **IDs y consistencia**: `partido_id` (`P-001`..`P-127`), `jugador_id`, `equipo_id` alineados a Neo4j/Mongo. Se documenta la discrepancia con IDs sintéticos de Cassandra.
5. **Precisión y Frecuencia**:
   - Precisión temporal: Segundos (`s`).
   - `tracking_jugador` y `tracking_pelota`: 1 Hz (cada 1 s).
   - `estadisticas_partido` y `actividad_usuarios`: cada 5 s (0.2 Hz).
   - Duración de partido: 90 min (5.400 segundos).
   - Distribución horaria realista: franjas de inicio escalonadas por día (`13:00`, `16:00`, `19:00`, `22:00` UTC) según el turno del partido en la jornada, reflejando la concurrencia real de un Mundial y evitando superposiciones artificiales masivas.
   - Regiones geográficas: las 6 confederaciones reales de `equipos.csv` (`CAF`, `UEFA`, `CONMEBOL`, `CONCACAF`, `AFC`, `OFC`).
6. **Generador y Carga**: Python standard library únicamente, semilla reproducible, generación en `.lp` (ignorados por git). Carga en un solo hilo con lotes de 10.000 líneas.
7. **Bases y Retención**:
   - Base `en_vivo`: retención de `7d` (7 días).
   - Base `resumen`: sin expiración (`0` / retention inf).

## Coherencia RF / RNF -> Archivo

| Requisito | Descripción | Archivo destino |
|---|---|---|
| RF1 / RF2 | Ingesta de métricas y persistencia temporal | `scripts/carga_lotes.sh`, `docs/carga_y_consultas.md` |
| RF3 / RF4 | Consultas por rango temporal y filtros dimensionales | `scripts/consultas_temporales.sh`, `docs/patrones_de_acceso.md` |
| RF5 / RF9 | Agregaciones por ventana y downsampling | `scripts/agregaciones.sh`, `docs/retencion_y_granularidad.md` |
| RF6 / RNF6 | Precisión temporal explícita (segundos) | `scripts/generacion_puntos.py`, `docs/modelo_multidimensional.md` |
| RF7 | Generador desacoplado de la carga | `scripts/generacion_puntos.py` |
| RF8 | Manejo de datos tardíos / ausentes | `scripts/consultas_temporales.sh`, `docs/patrones_de_acceso.md` |
| RF10 / RF11 | Cardinalidad y estimación de series | `docs/cardinalidad_y_escalabilidad.md` |
| RF12 | Estrategia de carga y escalabilidad proyectada | `docs/cardinalidad_y_escalabilidad.md`, `scripts/carga_lotes.sh` |
| RNF1 / RNF2 | Imagen Docker y persistencia en volumen | `docker-compose.yml`, `README.md` |
| RNF4 / RNF5 | Modelo guiado por patrones y control de cardinalidad | `docs/modelo_multidimensional.md`, `docs/cardinalidad_y_escalabilidad.md` |
| RNF8 / RNF9 | Consultas acotadas y scripts reproducibles | `scripts/*.sh`, `docs/carga_y_consultas.md` |
| RNF10 | Evidencia verificable | `docs/evidencia/*.txt` |

## Riesgos y mitigaciones

1. **Versión de InfluxDB (`influxdb:latest`)**: `influxdb:latest` en Docker Hub descarga InfluxDB v2.9.1 (CLI `influx`, Flux/InfluxQL, puerto 8086, buckets, orgs), mientras que InfluxDB 3 Core (puerto 8181, SQL, binario `influxdb3`) está en `influxdb:3-core`. Si se mantiene `latest`, se debe definir si se usa v2.9.1 o si se ajusta a `influxdb:3-core` según lo estipulado en la Clase 9.
2. **Timestamps 2030 vs Políticas de Retención**: Los timestamps son del año 2030 (futuros). Las políticas de retención descartan datos cuyo timestamp `t < now() - retencion`. Los datos de 2030 no son purgados al entrar; sin embargo, al hacer agregaciones relativas o pruebas en tiempo presente se debe verificar el comportamiento exacto de retención.
3. **Volumen de 10M+ puntos**: El volumen total calculado para los 127 partidos es de **16.637.000 puntos** (~1,5 GB en disco en formato line protocol). Se requiere verificar tiempos de ingesta en el hardware local (Apple M5, 16 GB RAM).

## Plan por fases

- **Fase 0**: Preparación, esqueleto, verificación de imagen, conteo de volumen/series y confirmación de decisiones.
- **Fase 1**: Documentación de diseño (`patrones_de_acceso`, `modelo_multidimensional`, `cardinalidad_y_escalabilidad`, `retencion_y_granularidad`, `carga_y_consultas`, borrador `README`).
- **Fase 2**: Scripts ejecutables (`inicializacion`, `generacion_puntos.py`, `carga_lotes`, `consultas_temporales`, `agregaciones`, `validacion`).
- **Fase 3**: Ensayo integrado completo desde cero y persistencia.
- **Fase 4**: Generación y registro de evidencia en `docs/evidencia/`.
- **Fase 5**: Cierre, revisión final, trazabilidad RF/RNF y entrega.
