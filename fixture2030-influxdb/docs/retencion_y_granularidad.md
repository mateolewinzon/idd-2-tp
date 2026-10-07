# Retención y Granularidad — InfluxDB (Hito 8)

## Plataforma del Fixture del Mundial 2030 — Ingeniería de Datos II

---

## 1. Ciclo de Vida del Dato Temporal (PDF8 §5.5)

En sistemas de telemetría de alta frecuencia, almacenar indefinidamente observaciones con resolución de un segundo (1 Hz) genera costos desproporcionados de almacenamiento, fragmentación de índices y degradación en consultas de rangos amplios.

El ciclo de vida del dato temporal en el Mundial 2030 se estructura en tres etapas:
1. **Ingesta en Caliente (Granularidad 1 s / 5 s):** Los datos se escriben a máxima frecuencia durante el transcurso del partido para soportar decisiones inmediatas (árbitros VAR, gráficos de transmisión televisiva, control táctico en banco de suplentes y monitoreo de CDN).
2. **Downsampling (Granularidad 1 minuto):** Al finalizar cada ventana o encuentro, los puntos crudos se agregan a resolución de 60 segundos aplicando funciones compatibles con la semántica de cada medida.
3. **Expiración de Puntos Crudos:** Cumplido el período de retención, el motor descarta automáticamente las observaciones de alta frecuencia, conservando únicamente las series consolidadas para análisis histórico.

---

## 2. Arquitectura de Dos Bases de Datos

En InfluxDB 3 Core, la política de retención (*Retention Period*) se define al momento de crear la base de datos y es inmutable. Por este motivo, el sistema segrega el almacenamiento en **dos bases de datos independientes** según el tiempo de vida y propósito analítico:

```
                  +-------------------------------------------------+
                  |          Flujo de Telemetría e Ingesta          |
                  +-------------------------------------------------+
                                     |
               +---------------------+---------------------+
               | (1 punto/s)                               | (cada 5 s)
               v                                           v
    +-----------------------+                   +-----------------------+
    |   tracking_jugador    |                   |  estadisticas_partido |
    |    tracking_pelota    |                   |   actividad_usuarios  |
    +-----------------------+                   +-----------------------+
               |                                           |
               v                                           v
    =====================================================================
    Base: fixture2030_en_vivo                   Base: fixture2030_resumen
    Retención: 7 días                           Retención: Sin expiración (infinita)
    Propósito: Telemetría viva y VAR            Propósito: Estadísticas y archivo
    =====================================================================
               |                                           ^
               |               Downsampling                |
               +-------------------------------------------+
                         (Agregados por minuto)
```

### 2.1 Base: `fixture2030_en_vivo`
- **Retención:** **7 días** (`7d`).
- **Contenido:**
  - `tracking_jugador` (15.087.600 puntos): Telemetría segundo a segundo de los 22 futbolistas titulares.
  - `tracking_pelota` (685.800 puntos): Coordenadas espaciales ($x,y,z$) y velocidad instantánea del balón.
- **Justificación:** Una ventana de 7 días otorga margen operativo suficiente para que cuerpos técnicos y organizadores realicen auditorías post-partido, análisis cinemáticos detallados y revisiones del Tribunal de Disciplina durante la misma semana de competencia. Pasados los 7 días, el nivel de detalle segundo a segundo pierde vigencia operativa.

### 2.2 Base: `fixture2030_resumen`
- **Retención:** **Sin expiración** (`0` / retención infinita).
- **Contenido:**
  - `estadisticas_partido` (274.320 puntos): Posesión, remates y pases cada 5 segundos.
  - `actividad_usuarios` (822.960 puntos): Concurrencia de espectadores por confederación cada 5 segundos.
  - **Métricas agregadas por minuto** derivadas del tracking de jugadores y pelota mediante downsampling.
- **Justificación:** Estas métricas ocupan un volumen marginal comparado con el tracking segundo a segundo y representan el acervo estadístico histórico del torneo para comparativas interanuales, resúmenes periodísticos y perfiles históricos de selecciones.

---

## 3. Estrategia de Downsampling

El **downsampling** es el proceso de transformar una serie temporal de alta frecuencia en una serie de menor granularidad (ej. de 1 segundo a 1 minuto), preservando el comportamiento físico de las variables mediante funciones de agregación semánticamente correctas (RF5, RF9).

> **Aclaración conceptual crítica (Clase 9):** El downsampling **no reemplaza** la política de retención de la base origen. El downsampling genera nuevos registros agregados en la base resumen; la eliminación física de los puntos originales sigue dependiendo exclusivamente de la política de expiración configurada en la base en vivo.

### 3.1 Reglas de Agregación por Medida en Downsampling (1 s $\to$ 1 min)

| Medida Origen | Tipo Semántico | Agregación a 1 minuto | Justificación Técnica |
|---|---|---|---|
| `velocidad_kmh` (jugador) | Muestra | `AVG(velocidad_kmh)` y `MAX(velocidad_kmh)` | Registra la velocidad media de desplazamiento y el pico máximo de sprint en ese minuto. |
| `distancia_acum_m` | Contador | `MAX(distancia_acum_m) - MIN(distancia_acum_m)` | Calcula la distancia neta recorrida por el jugador durante ese minuto específico (delta). |
| `velocidad_kmh` (pelota) | Muestra | `MAX(velocidad_kmh)` | Captura el remate o pase más veloz ocurrido durante el minuto. |
| `posesion_pct` | Muestra | `AVG(posesion_pct)` | Posesión media del balón en el minuto de juego. |
| `tiros_acumulados` | Contador | `MAX(tiros_acumulados) - MIN(tiros_acumulados)` | Remates efectuados en esa ventana de 60 segundos. |
| `pases_intervalo` | Intervalo (5 s) | `SUM(pases_intervalo)` | Totaliza los pases completados a lo largo de las doce muestras del minuto. |
| `usuarios_conectados` | Gauge | `MAX(usuarios_conectados)` y `AVG(usuarios_conectados)` | Pico máximo de demanda de infraestructura y promedio del minuto. NUNCA `SUM`. |

---

## 4. Impacto en Almacenamiento, Rendimiento y Costo

1. **Reducción de Volumen:**
   - La base en vivo almacena transitoriamente 15,77 millones de puntos de tracking (medido: los archivos `.lp` de todo el torneo pesan 2,2 GB; los datos cargados ocupan 458 MB en disco tras la carga completa, en este equipo). Al expirar a los 7 días los puntos crudos dejan de estar disponibles (Clase 9).
   - El downsampling a 1 minuto genera únicamente 90 puntos por jugador por partido:
     $$127 \text{ partidos} \times 22 \text{ jugadores} \times 90 \text{ minutos} = 251.460 \text{ puntos}$$
     Esto representa una **reducción de volumen del 98,3%** para el almacenamiento permanente, manteniendo intacta la capacidad analítica histórica.
2. **Optimización de Consultas Analíticas:**
   - Consultar la velocidad máxima de un jugador en todo el torneo sobre datos de 1 segundo requeriría escanear 15 millones de filas.
   - Consultar la misma métrica sobre la base resumen solo escanea 251 mil filas, reduciendo el tiempo de respuesta y el consumo de CPU en órdenes de magnitud.

---

## 5. Análisis del Riesgo: Timestamps de 2030 frente a la Retención

Un aspecto técnico fundamental evaluado en la Fase 0 es el comportamiento del motor de retención ante datos con marcas temporales futuras (año 2030):
- **Criterio de Expiración en Motores Temporales:** Los mecanismos de retención descartan datos evaluando la condición:
  $$\text{timestamp} < \text{tiempo\_del\_sistema} - \text{período\_de\_retención}$$
- **Comportamiento con Fechas de 2030:** Como los timestamps simulados corresponden al año 2030 ($t \approx 1,9 \times 10^9$ s en epoch), se encuentran en el futuro relativo a la fecha real del reloj del sistema. Por lo tanto, **los puntos nunca son purgados prematuramente durante la ingesta de laboratorio**, permitiendo ejecutar todas las validaciones sin riesgo de pérdida de datos.
- Este comportamiento será verificado empíricamente en la Fase 3 y registrado formalmente en `docs/evidencia/05_retencion_y_persistencia.txt`.
