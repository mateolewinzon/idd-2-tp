# Trazabilidad de requisitos — InfluxDB Hito 8

La matriz consolida la trazabilidad declarada para este módulo y la evidencia disponible. «Verificado» indica respaldo empírico en scripts/evidencias; «documentado» indica que el cumplimiento se define en diseño; «proyectado» identifica lo que no se ensayó.

| Requisito | Cobertura | Respaldo | Estado |
| --- | --- | --- | --- |
| RF1 / RF2 — Ingesta y persistencia temporal | Carga por lotes y almacenamiento de observaciones | [`carga_lotes.sh`](../scripts/carga_lotes.sh), [`carga_y_consultas.md`](./carga_y_consultas.md), [01](./evidencia/01_generacion_y_carga.txt), [05](./evidencia/05_retencion_y_persistencia.txt) | Verificado: 0 líneas rechazadas y persistencia tras reinicio. |
| RF3 / RF4 — Consultas temporales y filtros dimensionales | Consultas acotadas por período y tags | [`consultas_temporales.sh`](../scripts/consultas_temporales.sh), [`patrones_de_acceso.md`](./patrones_de_acceso.md), [03](./evidencia/03_consultas.txt) | Verificado en la corrida documentada. |
| RF5 / RF9 — Agregaciones y downsampling | Funciones según semántica y consolidación por minuto | [`agregaciones.sh`](../scripts/agregaciones.sh), [`modelo_multidimensional.md`](./modelo_multidimensional.md), [`retencion_y_granularidad.md`](./retencion_y_granularidad.md), [04](./evidencia/04_agregaciones.txt) | Verificado: 1.980 puntos de resumen reportados. |
| RF6 / RNF6 — Precisión temporal en segundos | Escritura Line Protocol con timestamps en segundos | [`generacion_puntos.py`](../scripts/generacion_puntos.py), [`modelo_multidimensional.md`](./modelo_multidimensional.md), [01](./evidencia/01_generacion_y_carga.txt) | Documentado y aplicado por el generador. |
| RF7 — Generador desacoplado de la carga | Generación determinista separada del cliente de carga | [`generacion_puntos.py`](../scripts/generacion_puntos.py), [`carga_lotes.sh`](../scripts/carga_lotes.sh), [01](./evidencia/01_generacion_y_carga.txt) | Verificado en la corrida documentada. |
| RF8 — Datos tardíos y ausentes | Partido vacío y escritura/lectura de punto tardío | [`consultas_temporales.sh`](../scripts/consultas_temporales.sh), [`carga_y_consultas.md`](./carga_y_consultas.md), [03](./evidencia/03_consultas.txt) | Verificado en la corrida documentada. |
| RF10 / RF11 — Cardinalidad y estimación de series | Cálculo por dimensiones y control de tags de alta cardinalidad | [`cardinalidad_y_escalabilidad.md`](./cardinalidad_y_escalabilidad.md), [`validacion.sh`](../scripts/validacion.sh), [02](./evidencia/02_validacion.txt) | Verificado: 3.937 series observadas. |
| RF12 — Carga masiva y escalabilidad | Lotes de 10.000 líneas; límites y proyección documentados | [`cardinalidad_y_escalabilidad.md`](./cardinalidad_y_escalabilidad.md), [`carga_lotes.sh`](../scripts/carga_lotes.sh), [01](./evidencia/01_generacion_y_carga.txt) | Carga local verificada; concurrencia y escalado no se ensayaron, están proyectados. |
| RNF1 / RNF2 — Entorno reproducible y persistencia | Compose con `influxdb:3-core`, volumen local y reinicio | [`docker-compose.yml`](../docker-compose.yml), [00](./evidencia/00_ambiente.txt), [05](./evidencia/05_retencion_y_persistencia.txt) | Verificado en el entorno registrado. |
| RNF4 / RNF5 — Modelo guiado por patrones y cardinalidad controlada | Diseño de tablas, tags y fields | [`patrones_de_acceso.md`](./patrones_de_acceso.md), [`modelo_multidimensional.md`](./modelo_multidimensional.md), [`cardinalidad_y_escalabilidad.md`](./cardinalidad_y_escalabilidad.md) | Documentado y respaldado por cardinalidad observada. |
| RNF8 / RNF9 — Consultas acotadas y scripts reproducibles | SQL con rangos temporales y scripts ejecutables | [`carga_y_consultas.md`](./carga_y_consultas.md), [`scripts/`](../scripts/), [03](./evidencia/03_consultas.txt) | Verificado en la corrida documentada. |
| RNF10 — Evidencia verificable | Ambiente, carga, validación, consultas, agregaciones y persistencia | [`evidencia/`](./evidencia/) | Completo: seis archivos de evidencia versionados. |

## Límites de interpretación

- La numeración y descripción de requisitos corresponde a la matriz de alcance del Hito 8 en [`analisis_hito8_influxdb.md`](../../analisis_hito8_influxdb.md). Este documento cubre el módulo InfluxDB, no redefine requisitos globales de otros motores.
- La estimación base es 16.870.680 puntos; la auditoría final registra 16.870.681 por el punto tardío de prueba. Los 1.980 puntos consolidados se almacenan en `fixture2030_resumen`.
- `tracking_jugador` y `tracking_pelota` se escriben en `fixture2030_en_vivo`; `estadisticas_partido` y `actividad_usuarios` se escriben en `fixture2030_resumen`, de acuerdo con la evidencia de validación.
- La evidencia solo acredita el comportamiento de retención observado con timestamps de 2030; no demuestra qué ocurrirá cuando esas fechas sean actuales.
