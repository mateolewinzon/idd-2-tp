# Modelo técnico para los casos de uso — Fixture 2030

Decisiones de diseño para completar los [lineamientos de entrega](lineamientos-entrega-demo.md) y soportar los [once casos de uso](casos-de-uso-fixture.md). Este documento define trabajo pendiente de implementación en la API; no amplía por sí mismo la entrega al desarrollo de un frontend.

**Alcance único:** Mundial 2030. Todos los datos pertenecen a ese Mundial; no hay colección `torneos`, campo `torneo_id`, selector de torneo ni API para administrar competiciones. Las reglas y el cuadro son los del dataset del Mundial 2030 usado en la demo.

## Responsabilidad de cada base

| Base | Responsabilidad | Consultas principales |
| --- | --- | --- |
| MongoDB | Datos del torneo, grupos, cruces, partidos, alineaciones y eventos. Persistencia de resultados y resúmenes finales de estadísticas. | Fixture, posiciones, playoffs, detalle de partido, goles de un jugador, estadísticas finales y acumulados del torneo. |
| InfluxDB | Tracking de jugadores y pelota, evolución temporal de estadísticas, ocupación espacial agregada y audiencia. | Última posición de la pelota, mapa de calor por intervalo y métricas físicas durante un partido. |
| Redis | Caché de respuestas derivadas, con TTL e invalidación. | Respuestas frecuentes de la API. Una clave vencida se reconstruye desde las bases persistentes. |

**Decisión:** las estadísticas finales se consolidan en MongoDB. Influx conserva la evolución temporal; los totales históricos de jugadores y partidos se pueden consultar sin acceder a Influx.

## Modelo mínimo en MongoDB

Los nombres son contratos propuestos, no colecciones ya implementadas.

| Colección | Campos principales | Claves e índices propuestos |
| --- | --- | --- |
| `equipos` y `jugadores` | Identificadores, nombre, selección; dorsal y posición en la alineación del partido. | Identificadores únicos. |
| `grupos` | Código, equipos participantes y orden de desempate del dataset cuando sea necesario. | Código único. |
| `partidos` | Fase, grupo o cruce, fecha, sede, local, visitante, estado, reloj de juego, resultado, alineaciones, eventos, estadísticas finales y estado de consolidación. | Índices por `fecha`, `grupo_id`, `(local_id, fecha)`, `(visitante_id, fecha)` y sobre `eventos.jugador_id`. |
| `cruces` | Fase, orden visual, partido, origen de cada plaza, equipo resuelto y ganador. | Único `(fase, orden)` e índice por partido. |
| `estadisticas_jugador_partido` | Partido, jugador, equipo, goles, asistencias, tarjetas, distancia total, velocidad máxima y fecha de actualización. | Único `(partido_id, jugador_id)`; índice por `jugador_id`. |

Cada evento incluye `evento_id`, tipo, tiempo de juego, equipo y jugadores involucrados. Su identificador evita que reenviar un evento duplique un gol. Los eventos conservan el detalle que permite reconstruir las estadísticas deportivas.

El resumen final del partido contiene el resultado y estadísticas por equipo. El resultado distingue goles de juego de la tanda de penales; los goles de la tanda no se suman a los goles individuales ni a los goles de la tabla de grupos.

## Estadísticas: escritura, cierre y consulta

### Durante el partido

1. El simulador envía los datos a la API con identificadores estables y tiempo de juego.
2. La API guarda los eventos y actualiza marcador/estado en MongoDB. Guarda tracking y muestras temporales en InfluxDB.
3. Las estadísticas deportivas se calculan desde los eventos; las físicas desde el tracking. La API combina ambas fuentes para el detalle en vivo.
4. Se invalidan las cachés afectadas. El endpoint devuelve el estado, la fecha de actualización y si el resumen es provisional o final.

No se presupone una transacción distribuida entre MongoDB e InfluxDB. Las escrituras tienen reintentos identificables y la consolidación verifica la disponibilidad de sus entradas.

### Al finalizar

1. Registrar el resultado final y cerrar la ingesta del partido, confirmando que están disponibles sus muestras y eventos esperados.
2. Calcular goles, asistencias y tarjetas desde los eventos de MongoDB.
3. Obtener distancia y velocidad máxima desde el tracking de Influx. Para distancia acumulada usar la diferencia entre el valor final y la base inicial; conservar esa base y no sumar contadores acumulativos. Para tiros acumulados usar el valor final/base; para pases por intervalo sumar los intervalos. La posesión se pondera por duración si los intervalos difieren.
4. Materializar la ocupación espacial histórica antes de que expire el tracking crudo.
5. Guardar con `upsert` los resúmenes por jugador y el resumen de partido, reemplazando valores anteriores.
6. Marcar la consolidación como completa cuando todos los resúmenes estén guardados. Las consultas finales usan partidos con consolidación completa; durante el cierre o reproceso las estadísticas se informan como pendientes/provisionales.
7. Invalidar cachés de partido, jugador, fixture, grupos y playoffs. Recalcular la clasificación y resolver las plazas de cruces que correspondan.

Si falta una fuente, conservar el resultado deportivo y marcar las estadísticas como pendientes; no sustituir datos faltantes por ceros. Reintentar el cierre. Una corrección de eventos vuelve a ejecutar el proceso y reemplaza los resúmenes, sin incrementar totales por segunda vez. Los agregados físicos finales deben persistirse antes del vencimiento del crudo: después de ese plazo no se promete recalcularlos con precisión de un segundo.

### Ejemplo: los goles de Messi

- **Primera versión:** consultar en MongoDB los eventos de gol asociados al identificador del jugador en los partidos del Mundial 2030. El nombre sirve para encontrar al jugador, no como clave de relación.
- **Con resúmenes finales:** sumar `goles` de `estadisticas_jugador_partido` para ese jugador, considerando únicamente los partidos con consolidación completa.
- **Incluyendo un partido en vivo o pendiente de consolidar:** sumar sus eventos por separado. Los conjuntos de partidos consolidados y no consolidados son disjuntos para evitar dobles conteos.
- **Detalle de los goles:** consultar los eventos para obtener partido, rival y minuto.
- Redis puede cachear cualquiera de estas respuestas. Influx no participa en el conteo de goles.

Para el volumen del torneo no se agrega todavía una colección de totales por jugador: se agregan los resúmenes por partido. El patrón de valores calculados permite persistir agregados cuando la frecuencia de lectura lo justifica: [MongoDB, Store Computed Data](https://www.mongodb.com/docs/manual/data-modeling/design-patterns/computed-values/computed-schema-pattern/).

## Grupos y clasificación

- Cada grupo referencia las selecciones participantes y sus partidos.
- La tabla se calcula en MongoDB desde los resultados de partidos finalizados: jugados, ganados, empatados, perdidos, goles a favor, goles en contra, diferencia y puntos.
- Para la demo se propone victoria = 3 puntos, empate = 1 y derrota = 0. Orden: puntos, diferencia de gol y goles a favor; si persiste la igualdad, usar el orden de desempate cargado explícitamente en el dataset. Son reglas de la demo, no una afirmación del reglamento oficial de 2030.
- Las posiciones se muestran durante la fase. Las plazas clasificadas se resuelven al completar los partidos requeridos y aplicar los cupos de clasificación del dataset del Mundial 2030.
- Si el dataset incluye mejores terceros, cargar sus cupos, criterios de comparación y asignación a cruces como parte de las reglas fijas de esta demo. No se implementa un motor de reglas configurable.
- Una corrección de resultado recalcula el grupo y actualiza sus plazas antes de volver a publicar la clasificación y el cuadro afectados.

No se necesita otra base para esta funcionalidad: resultados y reglas están en MongoDB; Redis conserva la tabla calculada.

## Playoffs

Cada plaza de un cruce conserva su origen aunque el equipo aún no esté definido:

- Selección ya asignada.
- Puesto de un grupo, por ejemplo `grupo A / posición 1`.
- Plaza de mejores terceros, si está incluida en el cuadro del dataset.
- Ganador de otro cruce, referenciado por identificador.

El cuadro devuelve fase, orden, partido, plazas y ganador. Hasta resolver una plaza muestra su descripción. Al finalizar un encuentro, el ganador se obtiene del resultado, incluyendo la tanda cuando corresponda, y se propaga al siguiente cruce. Repetir la resolución reemplaza la asignación existente. Las dependencias del cuadro se validan al cargar el dataset y no contienen ciclos.

## Mapas de calor en vivo e históricos

**Unidad espacial propuesta para la demo:** celdas de 5 × 5 m, con dimensiones de cancha explícitas en la configuración. Se usa el mismo sistema de coordenadas y la misma grilla en vivo e histórico.

- En vivo: agrupar las muestras de `tracking_jugador` por celda para el jugador, partido e intervalo solicitado.
- Histórico: materializar `ocupacion_jugador_minuto` en `fixture2030_resumen`, con dimensiones partido, equipo, jugador y celda; el tiempo representa el comienzo de la ventana de un minuto. Guardar `muestras` como entero.
- Cada muestra de tracking a 1 Hz pertenece a una única celda y ventana. Sumar muestras por celda aproxima el tiempo de presencia en segundos; no confundir cantidad de muestras con segundos si cambia la frecuencia.
- Reprocesar una ventana escribe el valor agregado completo para la misma clave temporal y dimensiones; no suma nuevamente al valor almacenado. Verificar esta identidad de escritura en la versión de Influx instalada.
- Para un jugador histórico, sumar celdas de las ventanas del intervalo solicitado. Para un equipo, sumar las de sus jugadores.
- La API permite todo el partido o rangos con precisión de minuto, usando inicio inclusivo y fin exclusivo. El frontend debe ofrecer esa misma precisión; no se promete precisión de segundos después de expirar el crudo.
- Retornar celda, cantidad de muestras, intensidad normalizada, grilla e intervalo efectivo. Una celda sin ocupación representa cero.

No usar `AVG(x_m)` y `AVG(y_m)` como mapa de calor: una posición promedio no representa la distribución de posiciones. El script actual `fixture2030-influxdb/scripts/agregaciones.sh` agrega velocidad y distancia, pero todavía no genera ocupación espacial.

La retención sin expiración del resumen no garantiza por sí sola que las consultas históricas sean adecuadas para la edición instalada. El repo usa `influxdb:3-core`: validar consultas de partidos antiguos y rangos del torneo con esa versión antes de prometer el histórico. La documentación de Core describe los límites de archivos consultados y su configuración: [InfluxDB 3 Core, configuration options](https://docs.influxdata.com/influxdb3/core/reference/config-options/).

## Contratos de lectura propuestos

Los filtros son opcionales salvo donde se indica. Todos los endpoints leen Redis primero y reconstruyen desde su fuente cuando falta la caché.

| Caso | Endpoint | Fuente persistente |
| --- | --- | --- |
| Fixture y selección | `GET /fixture?equipo_id=…&fecha=…&fase=…` | MongoDB. |
| Grupos | `GET /grupos` | MongoDB. |
| Posiciones | `GET /grupos/{id}/posiciones` | MongoDB: reglas y resultados finalizados. |
| Playoffs | `GET /playoffs` | MongoDB: cruces y partidos. |
| Detalle | `GET /partidos/{id}` | MongoDB. |
| Alineaciones | `GET /partidos/{id}/alineaciones` | MongoDB. |
| Eventos | `GET /partidos/{id}/eventos` | MongoDB. |
| Estadísticas de equipos | `GET /partidos/{id}/estadisticas` | En vivo: MongoDB + InfluxDB. Finales: MongoDB. |
| Jugador en un partido | `GET /partidos/{id}/jugadores/{jugador_id}/estadisticas` | En vivo: MongoDB + InfluxDB. Finales: MongoDB. |
| Totales de jugador | `GET /jugadores/{id}/estadisticas` | MongoDB; acumulado del jugador en el Mundial 2030. |
| Mapa de calor | `GET /partidos/{id}/mapa-calor?jugador_id=…&desde_minuto=…&hasta_minuto=…` | InfluxDB. Se puede filtrar por equipo en lugar de jugador; sin rango, todo el partido transcurrido. |
| Pelota (opcional) | `GET /partidos/{id}/pelota` | Última muestra de InfluxDB durante el partido en vivo. |

Las claves de caché incluyen todos los filtros que cambian la respuesta. Evento nuevo: invalidar eventos, marcador y estadísticas deportivas afectadas. Nuevas muestras: TTL corto en tracking y estadísticas físicas. Cierre/corrección: invalidar también fixture, posiciones, cruces y acumulados de jugadores. Los TTL concretos quedan por configurar y medir.

## Evidencia funcional para la demo

- Navegar fixture, grupo y cruce hasta el mismo detalle de partido.
- Ver marcador y eventos avanzar durante la simulación.
- Finalizar un partido y verificar que los goles del jugador coinciden con sus eventos y su resumen.
- Consultar estadísticas finales con Influx detenido y caché vacía: MongoDB permite responderlas. El mapa de calor sigue dependiendo de Influx.
- Ejecutar dos veces el cierre y obtener los mismos totales.
- Ver que finalizar un partido actualiza posiciones y completa la plaza del próximo cruce.
- Comparar el mapa completo con la suma de sus ventanas de un minuto; verificar que la suma de celdas coincide con las muestras válidas del intervalo.
- Consultar un mapa histórico desde el agregado, sin usar el tracking crudo, incluyendo un partido antiguo para validar el comportamiento de Core.

Estas verificaciones no prueban la escala global ni las garantías CAP: esas propiedades requieren un diseño y pruebas de distribución separados del entorno local de un nodo por base.
