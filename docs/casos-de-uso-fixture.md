# Casos de uso — Fixture Mundial 2030

Recorrido incremental para la página del torneo: navegar el fixture, entender un partido y explorar el rendimiento de un jugador. Cada incremento suma una funcionalidad completa para mostrar en la demo.

**Actor:** visitante, sin necesidad de iniciar sesión.  
**Contexto de la demo:** los datos en vivo provienen del simulador de partidos.

| # | Caso de uso | Flujo principal | Resultado |
| --- | --- | --- | --- |
| 1 | **Consultar el fixture** | El visitante abre la página y consulta los partidos ordenados por fecha, con equipos, horario, fase y estado: próximo, en vivo o finalizado. | Puede identificar cuándo juega cada equipo y conocer los resultados disponibles. |
| 2 | **Consultar los partidos de una selección** | Selecciona una selección desde el fixture. La página muestra sus partidos programados, en curso y finalizados. | Puede seguir el recorrido de esa selección en el torneo. |
| 3 | **Consultar el estado de los grupos** | Abre la sección de grupos y selecciona uno. Ve la tabla con posiciones, partidos jugados, puntos, goles a favor, goles en contra y diferencia de gol. Desde allí puede abrir sus partidos. | Puede conocer la situación de cada selección en la fase de grupos. |
| 4 | **Consultar los playoffs** | Abre el cuadro de eliminatorias y recorre las rondas. Ve los cruces, resultados y equipos que avanzaron; los lugares aún no definidos muestran su origen, por ejemplo, “Ganador del partido X”. | Puede entender el camino de las selecciones hacia la final y abrir cada encuentro. |
| 5 | **Ver el detalle de un partido** | Selecciona un partido desde el fixture, un grupo o los playoffs. Ve equipos, fecha, sede, fase, estado y marcador. Si está en vivo, también ve el minuto de juego. | Tiene una vista central del encuentro desde la cual acceder a su información. |
| 6 | **Consultar las alineaciones** | Dentro del partido, abre las alineaciones. Ve los titulares y suplentes de cada equipo, con nombre, dorsal y posición. | Puede identificar a los jugadores que participan y seleccionar uno para explorarlo. |
| 7 | **Seguir los eventos del partido** | Abre la cronología del encuentro. Ve goles, tarjetas y cambios con su minuto, equipo y jugadores involucrados. Durante un partido en vivo, aparecen nuevos eventos y se actualiza el marcador. | Puede seguir lo que ocurre en el encuentro o repasar cómo se desarrolló. |
| 8 | **Comparar las estadísticas de los equipos** | Abre las estadísticas del partido. Ve una comparación de posesión, tiros y pases, junto con goles y tarjetas. Los valores se actualizan durante el encuentro y quedan disponibles al finalizar. | Puede comparar el rendimiento de ambos equipos. |
| 9 | **Consultar el rendimiento de un jugador en el partido** | Selecciona un jugador desde la alineación. Ve sus goles, asistencias, tarjetas, distancia recorrida y velocidad máxima en ese encuentro. | Puede evaluar la participación individual del jugador. |
| 10 | **Ver el mapa de calor de un jugador** | Desde el detalle del jugador, abre su mapa de calor y selecciona todo el partido o un intervalo de tiempo. La cancha muestra las zonas donde tuvo mayor presencia durante ese período. En vivo, el mapa se actualiza a medida que avanza el encuentro. | Puede analizar por qué zonas se movió el jugador y cómo cambió su participación. |
| 11 · Opcional | **Seguir la pelota en vivo** | Dentro de un partido en vivo, el visitante abre la vista de tracking. Una cancha muestra la posición de la pelota y la actualiza a medida que avanza el encuentro. | Puede seguir visualmente por dónde circula la pelota durante el partido. |

## Recorrido sugerido para la demo

Fixture → grupo → partido en vivo → alineaciones → eventos → estadísticas de equipo → jugador → mapa de calor.

El cuadro de playoffs funciona como otra entrada al mismo detalle de partido. El tracking de la pelota se puede mostrar como cierre opcional desde el encuentro en vivo.

## Relación con el alcance de la entrega

Estos casos describen la experiencia funcional de la página. Los [lineamientos de la entrega](lineamientos-entrega-demo.md) mantienen el alcance acordado de solo API, sin frontend; implementar la página requiere ampliar ese alcance. Los casos sirven como guía de las funcionalidades que debe soportar la API y del recorrido de presentación.
