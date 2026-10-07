# Patrones de Acceso — Series Temporales de Estadísticas en Vivo (Hito 8)

## Plataforma del Fixture del Mundial 2030 — Ingeniería de Datos II

InfluxDB **no es fuente de verdad** de entidades maestras (equipos, jugadores, partidos, sedes ni eventos de torneo). Dichas entidades residen conceptualmente en MongoDB (Hito 4) y Neo4j (Hito 5), mientras que los comentarios masivos residen en Cassandra (Hito 6) y la caché de sesiones en Redis (Hito 7).

Cada módulo del TPO opera de forma autónoma e independiente: **la integración técnica o sincronización entre estos motores queda explícitamente fuera de alcance del hito**. En InfluxDB únicamente se reutilizan los identificadores canónicos (`partido_id`, `jugador_id`, `equipo_id`, `sede_id`) para asegurar la coherencia del modelo.

InfluxDB tiene como único propósito almacenar y consultar **observaciones temporales numéricas de alta frecuencia** producidas durante el transcurso de los partidos del Mundial 2030 (telemetría de jugadores, trayectoria de pelota, estadísticas de juego y métricas de concurrencia de usuarios).

---

## 1. Problema Temporal y Escala Operativa

### 1.1 Naturaleza del Fenómeno Temporal
Durante los 127 partidos del Mundial 2030 se capturan flujos continuos de métricas emitidas por sensores ópticos de estadio, sistemas de tracking por chip y plataformas de distribución de streaming.

Los números siguientes son **supuestos de diseño tomados de Hitos 1, 2 y 3, y validados contra los CSV de importación de Neo4j**; no son mediciones arbitrarias:
- **Partidos disputados:** 127 encuentros oficiales (partidos `P-001` a `P-127` de `partidos.csv`), distribuidos a lo largo del torneo con turnos de inicio escalonados (`13:00`, `16:00`, `19:00`, `22:00` UTC).
- **Duración operativa por encuentro:** 90 minutos de juego neto simulado (5.400 segundos correlativos).
- **Titulares por partido:** 22 jugadores simultáneos en cancha (11 por equipo), verificado exactamente en `alineaciones.csv` (2.794 asignaciones totales; suplentes excluidos de la telemetría en vivo).
- **Balón oficial:** 1 pelota activa por partido con posicionamiento tridimensional.
- **Participaciones y sedes:** 2 selecciones por partido (`participaciones.csv`) disputadas en una de las 16 sedes oficiales (`sedes.csv`).
- **Regiones geográficas de streaming:** 6 confederaciones continentales (`CAF`, `UEFA`, `CONMEBOL`, `CONCACAF`, `AFC`, `OFC`) presentes en `equipos.csv`.

### 1.2 Cuello de Botella y Reto Temporal
A diferencia de los almacenes relacionales o grafos, la base de series temporales enfrenta:
1. **Régimen de ingesta sostenido:** Cada segundo de partido inyecta 22 muestras de jugadores, 1 muestra de pelota, y cada 5 segundos métricas de equipo y de concurrencia por región.
2. **Volumen total proyectado:**
   - Tracking de jugadores: $127 \times 22 \times 5.400 = 15.087.600$ puntos.
   - Tracking de pelota: $127 \times 1 \times 5.400 = 685.800$ puntos.
   - Estadísticas de partido: $127 \times 2 \times 1.080 = 274.320$ puntos.
   - Actividad de usuarios: $127 \times 6 \times 1.080 = 822.960$ puntos.
   - **Volumen total efectivo:** **16.637.000 puntos**, superando el piso de 10M exigido por el Hito 8.
3. **Decisiones en tiempo real:** Cuerpos técnicos analizan fatiga y mapa de calor en ventanas de 5 a 15 minutos; la transmisión televisiva requiere la velocidad de tiro o posesión instantánea en menos de 2 segundos; los ingenieros de streaming detectan caídas o picos de tráfico por región para autoescalar CDN.

---

## 2. Catálogo de Patrones de Acceso

Cada patrón de acceso se especifica formalmente con los **7 atributos obligatorios** (quién genera/consulta, rango temporal, dimensiones, medidas, frecuencia de llegada, precisión temporal y comportamiento ante fallas o retrasos).

### Patrón P1: Evolución cinemática y posición de un jugador en ventana activa
- **Quién genera / consulta:**
  - *Genera:* Sistema de tracking óptico de estadio (cámaras perimetrales).
  - *Consulta:* Cuerpo técnico y analistas de rendimiento físico en banco de suplentes.
- **Rango temporal consultado:** Ventana deslizante reciente de 5 a 15 minutos (ej. últimos 300 segundos) durante el partido en juego.
- **Dimensiones (Tags):** `partido_id`, `jugador_id`, `equipo_id`.
- **Medidas (Fields):** `x_m`, `y_m` (coordenadas en metros), `velocidad_kmh` (muestra instantánea), `distancia_acum_m` (contador de odometría).
- **Frecuencia de llegada:** 1 Hz (1 punto por segundo por jugador).
- **Precisión temporal:** Segundos (`s`).
- **Comportamiento ante ausencia / retraso / dato tardío:**
  - *Ausencia:* Si un sensor pierde la señal por oclusión óptica durante 3 segundos, la visualización interpola linealmente las coordenadas $x, y$.
  - *Dato tardío:* Un paquete que llega con timestamp anterior se escribe como un punto más en su instante. Observado en el laboratorio (`consultas_temporales.sh`, caso B): el punto de 12:59:59 quedó consultable.

### Patrón P2: Velocidad máxima y distancia total por jugador y equipo
- **Quién genera / consulta:**
  - *Genera:* Sistema óptico de estadio.
  - *Consulta:* Transmisión de TV oficial (gráficas en pantalla) y preparador físico post-partido.
- **Rango temporal consultado:** Partido completo (90 minutos) o primer/segundo tiempo cerrado.
- **Dimensiones (Tags):** `partido_id`, `equipo_id` (opcionalmente agrupado por `jugador_id`).
- **Medidas (Fields):** `velocidad_kmh` (muestra), `distancia_acum_m` (contador acumulado).
- **Frecuencia de llegada:** 1 Hz.
- **Precisión temporal:** Segundos (`s`).
- **Semántica y Agregación:**
  - Velocidad máxima: `MAX(velocidad_kmh)`.
  - Distancia recorrida: `MAX(distancia_acum_m)` por jugador (o diferencia `MAX - MIN`), **nunca** `SUM(distancia_acum_m)`.
- **Comportamiento ante ausencia / retraso / dato tardío:** Al calcular máximos de un contador monótono, puntos faltantes intermedios no alteran el total acumulado al final de la ventana.

### Patrón P3: Posición tridimensional y velocidad de la pelota (Cruce con evento de gol)
- **Quién genera / consulta:**
  - *Genera:* Sensor UWB/óptico del balón oficial.
  - *Consulta:* Sistema VAR y analistas tácticos al ocurrir un gol o jugada dudosa registrada en Neo4j.
- **Rango temporal consultado:** Ventana hiper-acotada de 60 segundos alrededor del minuto del gol (cruce manual con el timestamp del evento en Neo4j).
- **Dimensiones (Tags):** `partido_id`.
- **Medidas (Fields):** `x_m`, `y_m`, `z_m` (altura sobre el césped), `velocidad_kmh`.
- **Frecuencia de llegada:** 1 Hz.
- **Precisión temporal:** Segundos (`s`).
- **Comportamiento ante ausencia / retraso / dato tardío:** Si hay pérdida de telemetría de pelota, el sistema VAR congela la última coordenada válida; los datos tardíos completan la trayectoria parabólica.

### Patrón P4: Evolución y balance de posesión de balón por equipo
- **Quién genera / consulta:**
  - *Genera:* Algoritmo de procesamiento de video en tiempo real en estadio.
  - *Consulta:* Producción audiovisual en vivo y tableros interactivos para hinchas en app oficial.
- **Rango temporal consultado:** Bloque del partido en curso (ej. acumulado hasta el minuto 30, o ventana deslizante de 10 min).
- **Dimensiones (Tags):** `partido_id`, `equipo_id`, `sede_id`.
- **Medidas (Fields):** `posesion_pct` (porcentaje instantáneo medido en el intervalo).
- **Frecuencia de llegada:** Cada 5 segundos (0.2 Hz).
- **Precisión temporal:** Segundos (`s`).
- **Semántica y Agregación:** `AVG(posesion_pct)` sobre el intervalo de tiempo seleccionado; la suma cruzada entre ambos equipos promedia 100%.
- **Comportamiento ante ausencia / retraso:** Si una muestra no arriba, se mantiene el último porcentaje calculado hasta la siguiente ventana.

### Patrón P5: Resumen y comparación estadística bilateral entre dos equipos
- **Quién genera / consulta:**
  - *Genera:* Sistema estadístico oficial de campo.
  - *Consulta:* Panel de estadísticas comparativas del partido (App móvil y sitio web).
- **Rango temporal consultado:** Desde el inicio del partido hasta el instante actual ($t_0$ a $t_{\text{actual}}$).
- **Dimensiones (Tags):** `partido_id`, `equipo_id` (filtrando ambos rivales del encuentro).
- **Medidas (Fields):** `posesion_pct`, `tiros_acumulados`, `pases_intervalo`.
- **Frecuencia de llegada:** Cada 5 segundos.
- **Precisión temporal:** Segundos (`s`).
- **Semántica y Agregación:**
  - Posesión media: `AVG(posesion_pct)`.
  - Tiros totales: `MAX(tiros_acumulados)`.
  - Pases totales completados: `SUM(pases_intervalo)`.
- **Comportamiento ante ausencia / retraso:** Tiros acumula monótonamente (resistente a pérdidas); pases suma deltas de intervalo.

### Patrón P6: Ritmo ofensivo: volumen de tiros en ventanas deslizantes de 5 minutos
- **Quién genera / consulta:**
  - *Genera:* Registro de eventos en vivo.
  - *Consulta:* Analistas de datos en vivo y modelos predictivos de expectativa de gol ($xG$).
- **Rango temporal consultado:** Todo el partido particionado en baldes de tiempo de 5 minutos (300 segundos).
- **Dimensiones (Tags):** `partido_id`, `equipo_id`.
- **Medidas (Fields):** `tiros_acumulados`.
- **Frecuencia de llegada:** Cada 5 segundos.
- **Precisión temporal:** Segundos (`s`).
- **Semántica y Agregación:** Diferencia de contador `MAX(tiros_acumulados) - MIN(tiros_acumulados)` agrupado por `date_bin` de 5 minutos, reflejando cuántos remates ocurrieron en esa ráfaga.
- **Comportamiento ante dato tardío:** Si un tiro entra con retraso de 10 segundos, cae dentro del mismo bucket de 5 minutos sin alterar el cálculo de ventanas pasadas.

### Patrón P7: Comparación de intensidad y dinamismo entre sedes
- **Quién genera / consulta:**
  - *Genera:* Agregador de métricas de partido.
  - *Consulta:* Comité organizador y directores de operaciones de sedes del Mundial.
- **Rango temporal consultado:** Jornada completa del torneo (múltiples partidos disputados en distintas sedes).
- **Dimensiones (Tags):** `sede_id`, `partido_id`.
- **Medidas (Fields):** `pases_intervalo`, `velocidad_kmh` (de pelota o jugadores).
- **Frecuencia de llegada:** Derivada de las frecuencias base de cada partido.
- **Precisión temporal:** Segundos (`s`).
- **Semántica y Agregación:** `SUM(pases_intervalo)` y `AVG(velocidad_kmh)` agrupado por `sede_id` para evaluar si ciertas canchas propician partidos más rápidos o pausados.
- **Comportamiento ante partido sin datos:** Si un partido no transmitió datos por falla de enlace, la sede muestra únicamente los partidos concluidos sin fallar la consulta general.

### Patrón P8: Concurrencia de audiencia y detección de picos por región geográfica
- **Quién genera / consulta:**
  - *Genera:* Plataforma central de telemetría de streaming y CDN.
  - *Consulta:* Operaciones de red (NOC / SRE) y analistas de derechos de transmisión.
- **Rango temporal consultado:** Ventana de transmisión del partido (incluyendo previa y desenlace).
- **Dimensiones (Tags):** `partido_id`, `region` (las 6 confederaciones).
- **Medidas (Fields):** `usuarios_conectados` (gauge instantáneo).
- **Frecuencia de llegada:** Cada 5 segundos (0.2 Hz).
- **Precisión temporal:** Segundos (`s`).
- **Semántica y Agregación:** `MAX(usuarios_conectados)` para dimensionar capacidad pico de infraestructura por región; `AVG(usuarios_conectados)` para audiencia promedio. **NUNCA** `SUM` temporal de usuarios.
- **Comportamiento ante caída de reporte:** Si una región no envía reporte por 15 segundos, se mantiene la última medición como estimación en tablero y se emite alerta operativa de observabilidad.

### Patrón P9: Resumen histórico downsampleado por minuto para archivo permanente
- **Quién genera / consulta:**
  - *Genera:* Proceso batch de agregación temporal post-partido (Downsampling).
  - *Consulta:* Analistas históricos, periodistas y aficionados consultando partidos disputados semanas o meses atrás.
- **Rango temporal consultado:** Rango histórico amplio (días, semanas, torneo completo).
- **Dimensiones (Tags):** Mismas dimensiones consolidadas (`partido_id`, `jugador_id`, `equipo_id`, `region`).
- **Medidas (Fields):** Valores pre-agregados por minuto (`velocidad_prom`, `velocidad_max`, `distancia_minuto`, `usuarios_pico`).
- **Frecuencia de llegada:** 1 punto cada 60 segundos (en base `resumen`).
- **Precisión temporal:** Segundos (`s`).
- **Comportamiento ante retención:** La base `en_vivo` (alta frecuencia 1 s) descarta los puntos brutos a los 7 días; las consultas históricas se resuelven exclusivamente sobre la base `resumen` sin pérdida de continuidad analítica.

---

## 3. Matriz de Síntesis de Patrones de Acceso

| Patrón | Tabla involucrada | Tags clave | Fields clave | Frecuencia | Agregación correcta | Destino / Base |
|---|---|---|---|---|---|---|
| **P1: Ventana jugador** | `tracking_jugador` | `partido_id`, `jugador_id` | `x_m`, `y_m`, `velocidad_kmh` | 1 s | Raw / Últimos puntos | `en_vivo` |
| **P2: Distancia/Velocidad máx** | `tracking_jugador` | `partido_id`, `jugador_id`, `equipo_id` | `velocidad_kmh`, `distancia_acum_m` | 1 s | `MAX` velocidad, `MAX` distancia | `en_vivo` |
| **P3: Pelota en gol** | `tracking_pelota` | `partido_id` | `x_m`, `y_m`, `z_m`, `velocidad_kmh` | 1 s | Raw (ventana 60 s) | `en_vivo` |
| **P4: Posesión en vivo** | `estadisticas_partido` | `partido_id`, `equipo_id` | `posesion_pct` | 5 s | `AVG(posesion_pct)` | `en_vivo` / `resumen` |
| **P5: Comparativa equipos** | `estadisticas_partido` | `partido_id`, `equipo_id`, `sede_id` | `posesion_pct`, `tiros_acum`, `pases` | 5 s | `AVG` posesión, `MAX` tiros, `SUM` pases | `en_vivo` / `resumen` |
| **P6: Ventanas tiros (5m)** | `estadisticas_partido` | `partido_id`, `equipo_id` | `tiros_acumulados` | 5 s | `MAX - MIN` por balde 5m | `en_vivo` / `resumen` |
| **P7: Dinamismo por sede** | `estadisticas_partido` | `sede_id`, `partido_id` | `pases_intervalo`, `posesion_pct` | 5 s | `SUM(pases)`, `AVG` | `resumen` |
| **P8: Picos usuarios** | `actividad_usuarios` | `partido_id`, `region` | `usuarios_conectados` | 5 s | `MAX(usuarios)`, `AVG(usuarios)` | `en_vivo` / `resumen` |
| **P9: Histórico downsample** | Derivado / Resumen | Todos los tags | Métricas agregadas por minuto | 60 s | Pre-agregados en ingestión batch | `resumen` |
