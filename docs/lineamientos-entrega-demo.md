# Propuesta de entregable final — Fixture 2030

**Fecha de la propuesta:** 2 de noviembre de 2026.  
**Propósito:** lineamiento de alcance, arquitectura y trabajo pendiente para la entrega final y la presentación de la demo del proyecto de Ingeniería de Datos II.  
**Estado:** propuesta de trabajo; las decisiones pendientes se mantienen abiertas.

Fuente: [propuesta original en Claude](https://claude.ai/artifact/GwUECtpE3pcJYGB37AFXYX#366ba437-210a). Este documento recupera el contenido del texto pegado y reorganiza su formato en Markdown; no constituye una validación técnica de las afirmaciones ni evidencia de que los cambios ya estén implementados.

## Resumen

Proponemos cerrar el entregable con tres bases (MongoDB, Redis e InfluxDB), Prometheus y Grafana para observabilidad, la API del Hito 10 adaptada y un módulo nuevo que simula partidos en vivo.

Funcionalidades del entregable:

- Eventos del partido.
- Mapa de calor en vivo.
- Tracking de la pelota en vivo.
- Fixture base e histórico de partidos jugados.
- Estadísticas de partido.
- Estadísticas de jugador.

**Alcance acordado:** solo API (sin frontend), sin login, distribución global documentada pero no levantada, y “en vivo” simulado. Salen Neo4j, Cassandra, IRIS, el login y las sesiones.

## Qué cambió y cómo tratamos las revisiones

La consigna final pide un sistema global con alta concurrencia de espectadores, con la velocidad como prioridad, y alcanza con un mínimo de tres bases.

| Tema | Versión anterior | Ahora | Motivo |
| --- | --- | --- | --- |
| Partidos y eventos | MongoDB (Hito 2) → Neo4j (Hitos 3 y 5) | MongoDB | Las consultas parten de un partido o jugador, con profundidad fija y volumen chico (sección siguiente). |
| Redis | Sesiones (Hitos 3 y 7) | Caché de lecturas calientes | Sin login no hay sesiones; la carga es de millones leyendo lo mismo. |
| Tracking en Influx | Lo consultan analistas después (Hito 3) | Lo consume el público en vivo | Mapa de calor y pelota son funcionalidades. |
| N/R/W en MongoDB | N=3, R=1, W=2 (Hito 3) | Retirado (Hito 4 §5, aceptado por el profesor) | Hay que reescribir el texto de reemplazo sin “oplog”, que el profesor marcó. |

## Por qué MongoDB, Redis e InfluxDB

Cada base cubre un patrón de acceso que las funcionalidades necesitan y que las otras resuelven peor. Es la persistencia políglota de la Clase 12: la mejor herramienta para cada tipo de dato.

| Base | Qué guarda | Por qué este modelo |
| --- | --- | --- |
| MongoDB | Equipos, jugadores, partidos con sus eventos y alineaciones. | Entidades recuperadas por identificador (Hito 2). Un partido con sus eventos adentro se lee en una sola operación; la Clase 12 recomienda desnormalizar para la velocidad de lectura. |
| Redis | Copias de lo que más se lee: partido en vivo, eventos, pelota, mapa de calor, fixture. | Caché con el patrón Cache-Aside y TTL por dato (Clase 8). Absorbe millones de lecturas iguales para que no lleguen a las fuentes. |
| InfluxDB | Tracking de jugadores y pelota, estadísticas de partido, audiencia por región. | Series temporales con consulta por ventana, agregación, retención y downsampling (Clase 9, Hito 8). |

### Por qué no las otras

**Neo4j.** Ninguna funcionalidad pide recorridos de profundidad variable, que es donde el grafo gana. Las consultas parten de un partido o de un jugador, con dos o tres saltos fijos, sobre 127 partidos y unos 15 eventos por partido en la muestra. Un documento de partido las resuelve en una lectura. El Hito 3 además lo señaló como primer cuello de botella: un solo nodo de escritura y sin particionar.

**Cassandra.** Su fuerte es la escritura masiva distribuida (comentarios). Ninguna funcionalidad la necesita, y el tracking ya vive en Influx.

**IRIS.** Descartado desde el Hito 2.

**SQL relacional.** Es pregunta segura en la defensa (Clase 14). Respuesta propuesta: escala tradicionalmente en vertical, y nuestro caso es lectura masiva por clave y series temporales, donde NoSQL rinde cuando el modelo coincide con el acceso (Clase 13).

## Cómo se cumple cada funcionalidad

Cada funcionalidad tiene una fuente de verdad y una copia en Redis. La API lee primero de Redis y, si no está la clave, va a la fuente y la guarda (Cache-Aside, Clase 8).

| Funcionalidad | Fuente de verdad | Copia en Redis | Endpoint propuesto |
| --- | --- | --- | --- |
| Eventos del partido | MongoDB: eventos dentro del documento del partido (tipo, minuto, jugador, equipo). | Sí, TTL corto en vivo; se invalida al llegar un evento. | `GET /partidos/{id}/eventos` (existe; cambia la fuente). |
| Mapa de calor en vivo | Influx `tracking_jugador` (`x_m`, `y_m`), ventana reciente. | Sí, TTL de segundos. | `GET /partidos/{id}/mapa-calor`, por equipo o jugador. |
| Mapa de calor histórico | Influx `fixture2030_resumen`: promedios por minuto. | Sí, TTL largo (partido terminado). | Mismo endpoint, con rango de tiempo. |
| Pelota en vivo | Influx `tracking_pelota`, último punto (uno por segundo). | Sí, TTL de 1 s. | `GET /partidos/{id}/pelota`. |
| Fixture e histórico | MongoDB: partidos con fase, fecha, sede, equipos y resultado. | Sí, TTL largo; se invalida al terminar un partido. | `GET /fixture`, `GET /partidos/{id}`. |
| Estadísticas de partido | Influx `estadisticas_partido` (posesión, tiros, pases) + conteo de eventos en MongoDB. | Sí. | `GET /partidos/{id}/estadisticas` (existe; se amplía). |
| Estadísticas de jugador | MongoDB (ficha + goles, asistencias y tarjetas de los eventos) + Influx (distancia y velocidad máxima, patrón P2 del Hito 8). | Sí. | `GET /jugadores/{id}/estadisticas`. |

Las estadísticas de jugador combinan dos fuentes en la API: es el patrón Aggregator de la Clase 12. Los valores exactos de TTL quedan para decidir en grupo.

### Camino en vivo

Los espectadores leen de Redis; solo lo que falta en la caché llega a MongoDB o InfluxDB.

El simulador reproduce un partido ya generado a velocidad real: tracking a 1 Hz, estadísticas cada 5 s y eventos en su minuto. La propuesta es que escriba a través de la API, así hay un solo camino de escritura validado y medido (Clase 13: captura y validación). La alternativa figura en [Decisiones abiertas](#decisiones-abiertas).

Cuando llega un evento, la API invalida la copia del partido en Redis, como se hacía con la ficha en el Hito 7.

### Histórico

El histórico vive siempre en las bases de origen, nunca en Redis: la Clase 13 advierte que el TTL de una caché impide reconstruir históricos.

| Dato | Dónde | Se conserva |
| --- | --- | --- |
| Fixture, partidos, eventos, equipos, jugadores | MongoDB | Sí, sin vencimiento. |
| Tracking segundo a segundo (jugadores y pelota) | Influx `fixture2030_en_vivo` | 7 días (Hito 8). |
| Tracking agregado por minuto, estadísticas de partido | Influx `fixture2030_resumen` | Sí, sin vencimiento. |

**Decidido:** el mapa de calor histórico se arma con los promedios por minuto (unos 90 puntos por jugador y partido). Consecuencia: la trayectoria segundo a segundo de la pelota de un partido viejo no se conserva; la pelota es solo una funcionalidad en vivo.

### Decisión pendiente: resumen de partidos terminados

| Aspecto | A. Consolidar en MongoDB al terminar | B. Calcular desde Influx y cachear |
| --- | --- | --- |
| Cómo funciona | Al terminar el partido, un proceso escribe resultado y estadísticas finales en el documento del partido. | Cada consulta agrega desde `fixture2030_resumen`; Redis guarda el resultado con TTL largo. |
| A favor | El histórico se lee en una operación por identificador. Separa el camino analítico del operacional (Clase 13). Sigue disponible si Influx cae. | Una sola fuente, nada que sincronizar. El endpoint de estadísticas ya existe. |
| En contra | Proceso extra que tiene que ser idempotente y reprocesable (Clase 13). Copia que puede desfasarse si se corrige un dato en Influx. | Cada consulta que no está en Redis agrega en Influx. Si Influx cae y la caché venció, no hay respuesta. |

## Distribución global, CAP y replicación

La propuesta plantea que todo el sistema queda AP: ante una partición preferimos responder con un dato algunos segundos atrasado antes que no responder. **La distribución se documenta pero no se levanta; el ambiente local tiene un nodo por base.**

| Subsistema | CAP | Replicación y distribución | Qué cambia respecto de lo documentado |
| --- | --- | --- | --- |
| Equipos y jugadores (MongoDB) | AP, consistencia eventual. | Conjunto de tres réplicas con un primario; escrituras confirmadas por mayoría (`writeConcern`, Clase 3); lecturas en secundarios (`readPreference`, Clase 13). Sin particionar (Hito 3). | Se mantiene. Reescribir el texto del Hito 4 §5 sin “oplog”. |
| Partidos y eventos (MongoDB) | AP. Quien mira en vivo no debe ver desaparecer un gol que ya vio. | Un solo primario recibe las escrituras del simulador; réplicas de lectura por región; cada usuario fijo a su región (sticky sessions, Clase 3). Sin particionar: 127 partidos. | Nuevo: antes era Neo4j con timestamp lógico (Hito 3). |
| Caché (Redis) | AP. Dato derivado y descartable. | Un Redis por región (primario + réplica, Clase 8), sin replicar entre regiones: cada uno se llena desde las fuentes. | Antes eran sesiones con consistent hashing; el Hito 7 ya corrigió que Redis Cluster usa slots. |
| Tracking y estadísticas (InfluxDB) | AP, replicación asincrónica sin quórum (Hito 3). | Particionado por ventana de tiempo combinada con partido (Hito 3). | Cambia el motivo: ahora lo consume el público en vivo. |

Salen del análisis Usuarios (era el único CP, con R+W>N) y Comentarios en Cassandra. Con este stack ninguna base usa quórum sin líder. N/R/W queda como concepto que explica por qué no aplica (la Clase 3 lo presenta para Cassandra y DynamoDB).

### ¿Qué pasa si se cae una región?

Es pregunta de la defensa (Clase 14).

- Los usuarios de esa región pasan a otra: más latencia, pero siguen leyendo de réplicas y cachés.
- Si estaba ahí el primario de MongoDB, la mayoría elige otro. Según la Clase 3, la escritura se corta entre 10 y 30 segundos.
- El Redis de esa región se pierde y se reconstruye desde las fuentes.

Objetivos del Hito 3, que pasan a ser los que mide Prometheus:

- 99,99 % de disponibilidad.
- P95 menor a 100 ms en consultas críticas.
- Dos a tres millones de usuarios simultáneos.
- Más de 100.000 solicitudes por segundo.

## Observabilidad: qué medimos y dónde

Prometheus guarda las métricas de operación y Grafana las muestra; el histórico de audiencia queda en Influx. Las métricas son la evidencia para defender CAP y la ubicación de los nodos.

| Dato | Por qué hay que medirlo | Dónde | Cómo se obtiene |
| --- | --- | --- | --- |
| Latencia P50, P95 y P99 por endpoint, región del usuario y región del nodo | Ubicación de nodos; objetivo P95 menor a 100 ms. | Prometheus | API instrumentada. |
| Solicitudes por región o país de origen | Ubicación y tamaño de cada región. | Prometheus | API instrumentada. |
| Aciertos y fallos de caché, memoria, claves desalojadas | Mostrar que la mayoría de las lecturas se responden desde la caché sin llegar a MongoDB ni a InfluxDB, y que la memoria alcanza sin descartar claves (Clase 8). | Prometheus | `redis_exporter`. |
| Antigüedad del dato servido: segundos entre que se escribe y que se lee | Mostrar si la ventana de consistencia eventual es aceptable (núcleo del argumento AP). | Prometheus | API instrumentada. |
| Errores y respuestas 503 por fuente | Disponibilidad por subsistema (Hito 3). | Prometheus | API instrumentada. |
| Estado y uso de MongoDB, CPU y memoria de la máquina | Panel de salud por base (Hito 13). | Prometheus | `mongodb-exporter`, `node-exporter`. |
| Respuesta de la API con MongoDB detenido | Que elegimos disponibilidad sobre consistencia. | Evidencia de la prueba de caída (Clase 12) + Prometheus | Detener el contenedor sin borrar datos. |
| Audiencia por partido y región durante el torneo | Análisis histórico de audiencia. | Influx `actividad_usuarios` (ya existe) | Escritura cada 5 s (Hito 8). |
| Retraso de replicación | Valida las garantías de replicación. | Solo documentado | No medible con un nodo por base. |

### Por qué Prometheus y también Influx para el origen geográfico

Prometheus responde “¿mis nodos están bien ubicados?”. La Clase 14 usa casi el mismo ejemplo: por qué subió la latencia en Argentina y no en Portugal.

Influx guarda la audiencia que tiene que durar todo el torneo. La Clase 9 plantea “el pico de usuarios activos por región” como pregunta típica de series temporales.

Etiquetas de baja cardinalidad: región o país, nunca IP ni un identificador por usuario (Clases 9 y 13).

Origen sin login: sale de la IP. En la simulación, el generador de carga manda el país en un encabezado de la solicitud.

### Cumplimiento del Hito 13 (Clase 14)

- Prometheus lee al menos tres fuentes: la API, `mongodb-exporter` y `redis_exporter`.
- Grafana muestra latencia, throughput, errores y un panel de salud por base.
- La evidencia sale de una prueba de carga con las fases A a E de la Clase 13.
- Los logs no van a Influx: quedan como logs de la API con identificador de request (Hito 10). La Clase 14 los asigna a Loki o ELK, fuera de nuestro alcance.

**Sin confirmar en el material:** si InfluxDB 3 expone métricas para Prometheus, y por cuánto tiempo retiene datos Prometheus.

## Cambios concretos

La mayor parte reutiliza lo construido: el modelo de Influx no cambia, MongoDB suma una colección y Redis cambia de claves.

### MongoDB

- Colección `partidos` con eventos y alineaciones adentro, cargada desde los CSV de `fixture2030-neo4j/import/`, con carga idempotente.
- Índice para el fixture de un equipo (local o visitante, ordenado por fecha).
- Reescribir el Hito 4 §5 sin “oplog”.

### InfluxDB

- Consulta del último punto de la pelota.
- Consulta del mapa de calor por celdas, en vivo (crudo) e histórico (por minuto).
- **Atención:** `generacion_puntos.py` lee los CSV de `fixture2030-neo4j/import/`. Si sacamos esa carpeta, hay que mover los CSV.

### Redis

- Reemplazar las claves de sesión por las de caché de cada funcionalidad, con su TTL y su invalidación.
- Revisar la política de memoria para claves de caché.

### Simulador (módulo nuevo)

- Reproduce un partido ya generado, a velocidad real: tracking a 1 Hz, estadísticas cada 5 s y eventos en su minuto.

### Backend

- Quitar los adaptadores de Cassandra y Neo4j, y las rutas de sesiones.
- Pasar partidos y eventos al adaptador de MongoDB.
- Endpoints nuevos: fixture, mapa de calor, pelota, estadísticas de jugador.
- Exponer `/metrics` para Prometheus y leer el país de origen de un encabezado.

### Observabilidad

- Docker Compose con Prometheus, Grafana y los exporters.
- Dashboard y capturas durante la prueba de carga (la Clase 14 pide la carpeta `/hito-13`).

### Documentación

- Matriz de selección actualizada a tres bases.
- CAP y replicación revisados, citando la versión vigente de cada decisión.
- Retirar del entregable las carpetas de Cassandra, Neo4j e IRIS.

## Decisiones abiertas

- Resumen de partidos terminados: opción A (consolidar en MongoDB) u opción B (calcular desde Influx).
- ¿El simulador escribe a través de la API (un solo camino de escritura, validado y medido) o directo en las bases (más simple)?
- TTL de cada clave de caché, en vivo y para partidos terminados.
- Mapa de calor: tamaño de celda y cómo agruparlas en Influx con lo que muestra la Clase 9.
- Verificar si InfluxDB 3 expone métricas para Prometheus y cuánto retiene Prometheus.
- Cómo documentamos que cada usuario queda fijo a su región.
- Estructura de carpetas de la entrega final (la Clase 14 menciona `/hito-13`).
