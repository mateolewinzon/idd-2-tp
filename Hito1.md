# TP - Ingeniería de Datos 2
# Hito 1
## Volúmenes Esperados

## Identificación de Datos


## Sección 2: Análisis de Problemas SQL

## Modelos NoSQL Propuestos

## Conclusión
El análisis realizado muestra que no todos los datos de una plataforma de seguimiento y consumo de partidos de fútbol presentan las mismas características ni requieren el mismo tipo de almacenamiento. Mientras que entidades como equipos, jugadores, partidos y alineaciones poseen una estructura estable, relaciones claras y volúmenes relativamente bajos, otros datos como sesiones, comentarios, eventos y tracking presentan altos niveles de concurrencia, crecimiento acelerado y patrones de acceso muy diferentes.

Las bases de datos relacionales continúan siendo una solución adecuada para la información estructurada que requiere integridad referencial y consistencia. Sin embargo, utilizar exclusivamente SQL para todos los tipos de datos puede generar problemas de rendimiento y escalabilidad, especialmente frente a millones de usuarios concurrentes, grandes picos de escritura y flujos continuos de información en tiempo real.

Los modelos NoSQL permiten complementar la solución utilizando tecnologías más adecuadas para cada necesidad. Los modelos clave-valor se adaptan bien a información temporal como las sesiones; los modelos wide-column permiten manejar grandes volúmenes de escrituras como eventos y comentarios; y las bases orientadas a series temporales resultan especialmente apropiadas para el tracking continuo de jugadores y pelota. Los modelos documentales, por su parte, ofrecen flexibilidad para información semiestructurada, aunque en algunos casos las ventajas frente a SQL no justifican necesariamente reemplazar el modelo relacional.

Por lo tanto, la solución más adecuada no consiste en elegir entre SQL o NoSQL de manera exclusiva, sino en aplicar una estrategia de persistencia políglota, utilizando diferentes modelos de almacenamiento según las características de cada conjunto de datos. Esto permite aprovechar las fortalezas de cada tecnología y construir una arquitectura capaz de mantener consistencia donde es necesaria y, al mismo tiempo, escalar eficientemente frente a grandes volúmenes, alta concurrencia y procesamiento en tiempo real.

| Entidad | Volumen |  | Crecimiento | Acceso |
| --- | --- | --- | --- | --- |
| Equipos | 64 |  | Ninguno (fijo) | Escritura |
| Jugadores | 1500+ |  | Ninguno (fijo) | Escritura |
| Partidos | 175 |  | Ninguno (fijo) | Lectura + Escritura |
| JugadorPartido (alineaciónes) | 5000-6000 |  | Crecimiento durante el torneo | Lectura + Escritura |
| Eventos | 5000-10000 por partido |  | Crecimiento durante partidos | Lectura + Escritura |
| Usuarios | 2-3M simultáneos |  | Crecimiento constante | Lectura + Escritura |
| Sesiones | 2-3M simultáneos |  | Crecimiento durante partidos | Lectura + Escritura |
| Comentarios | 1M+ por partido |  | Escritura masiva, crecimiento constante | Escritura masiva |
| Tracking jugadores | 200k - 1.5M por partido |  | Crecimiento en tiempo real durante partidos | Lectura + Escritura |
| Tracking pelota | 10k-50k por partido |  | Crecimiento en tiempo real durante partidos | Lectura + Escritura |


| Nombre del dato | Descripcion | Volumen estimado | Velocidad de crecimiento | Patrón de acceso |
| --- | --- | --- | --- | --- |
| Equipos | Información general de las selecciones/equipos participantes del torneo. | ~64 | Muy baja / prácticamente fija | Lectura frecuente, escritura ocasional |
| Jugadores | Datos de los jugadores pertenecientes a cada equipo, incluyendo información personal y deportiva. | 1.500+ | Muy baja | Lectura frecuente, escritura ocasional |
| Partidos | Información de cada partido: equipos, fecha, estadio, resultado, estado, etc. | ~175 | Baja, asociada al avance del torneo | Lectura y escritura |
| JugadorPartido / Alineaciones | Relación entre jugadores y partidos. Indica convocatoria, titularidad, posición, minutos jugados, sustituciones, etc. | 5.000–6.000 | Crecimiento progresivo durante el torneo | Lectura y escritura |
| Eventos del partido | Acciones ocurridas durante un partido, como pases, tiros, goles, faltas, tarjetas, recuperaciones, sustituciones, etc. | 5.000–10.000 por partido (~875k–1,75M total) | Alta durante los partidos | Escritura continua y lectura frecuente |
| Usuarios | Usuarios registrados en la plataforma que consumen contenido e interactúan durante los partidos. | Millones de usuarios; hasta 2–3M concurrentes | Crecimiento constante | Lectura y escritura intensiva |
| Sesiones | Estado de las sesiones activas de los usuarios, autenticación y datos temporales asociados a su conexión. | Hasta 2–3M simultáneas | Muy alta durante partidos y eventos importantes | Lectura y escritura muy frecuente; datos de corta duración |
| Comentarios | Mensajes enviados por los usuarios durante los partidos o en espacios de interacción social. | 1M+ por partido | Muy alta y concentrada durante partidos | Escritura masiva y lectura en tiempo real |
| Tracking de jugadores | Posiciones espaciales de los jugadores tomadas periódicamente durante el partido. Permiten analizar movimientos y comportamiento táctico. | 200k–1,5M por partido | Muy alta en tiempo real durante los partidos | Escritura continua; lectura principalmente analítica |
| Tracking de pelota | Posición y eventualmente altura, velocidad y trayectoria de la pelota a lo largo del partido. | 10k–50k por partido | Alta en tiempo real durante los partidos | Escritura continua; lectura principalmente analítica |


| Tipo de dato | Cómo se almacenaría en SQL | Problemas específicos | Impacto en rendimiento | Limitaciones de escalabilidad |
| --- | --- | --- | --- | --- |
| Equipos | En una tabla relacional independiente. | No presenta problemas relevantes por su bajo volumen y estructura estable. | Impacto mínimo en consultas y escrituras. | Prácticamente ninguna para el volumen esperado. |
| Jugadores | En una tabla relacional vinculada con los equipos. | Puede requerir joins frecuentes con equipos, partidos y alineaciones. | Impacto bajo debido al volumen reducido. | No presenta limitaciones relevantes para el caso planteado. |
| Partidos | En una tabla relacional vinculada con los equipos participantes. | Durante el partido puede recibir actualizaciones frecuentes de su estado. | Impacto bajo por la pequeña cantidad total de registros. | No presenta problemas significativos de escalabilidad. |
| JugadorPartido / Alineaciones | En una tabla relacional que vincule jugadores y partidos. | Requiere joins para reconstruir alineaciones y participación de jugadores. | Impacto bajo para el volumen estimado. | El modelo relacional escala correctamente para este volumen. |
| Eventos del partido | Cada evento se almacenaría como un registro asociado a un partido y, cuando corresponda, a jugadores y equipos. | Gran cantidad de inserciones durante los partidos y diversidad entre los distintos tipos de eventos. | Las escrituras constantes y el mantenimiento de índices aumentan el consumo de recursos. Las consultas históricas y agregaciones se vuelven más costosas a medida que crece la tabla. | Con múltiples torneos y años de información puede requerir particionamiento, archivado o distribución de los datos. |
| Usuarios | En una tabla relacional de usuarios y otras tablas relacionadas cuando sea necesario. | La principal dificultad es la elevada cantidad de usuarios concurrentes realizando operaciones simultáneamente. | Puede producir saturación de conexiones, alta utilización de CPU y disco, y contención ante grandes picos de actividad. | Una única instancia puede resultar insuficiente. Escalar horizontalmente puede requerir réplicas, particionamiento o sharding. |
| Sesiones | Cada sesión se almacenaría como un registro relacionado con un usuario. | Son datos temporales con gran cantidad de creaciones, consultas, actualizaciones y eliminaciones. El modelo relacional aporta poco valor para este tipo de información. | Millones de operaciones simples pueden generar una carga elevada sobre la base y sus índices. La eliminación de sesiones expiradas también genera trabajo adicional. | Escalar a millones de sesiones simultáneas puede requerir múltiples instancias o particionamiento, aumentando la complejidad. |
| Comentarios | Cada comentario se almacenaría como un registro relacionado con un usuario y un partido. | Se producen grandes picos de escrituras concentrados durante los partidos. Además, las lecturas ocurren al mismo tiempo que las inserciones. | Alto consumo de escritura y mantenimiento de índices. La lectura constante de los comentarios más recientes puede competir con las inserciones. | Con varios partidos y millones de comentarios, una base centralizada puede convertirse en un cuello de botella. Distribuir los datos agrega complejidad. |
| Tracking de jugadores | Cada posición registrada de un jugador se almacenaría como una fila asociada al jugador y al partido. | Genera una enorme cantidad de registros secuenciales y repetitivos. Las relaciones entre cada muestra y el resto del modelo aportan relativamente poco valor. | Alta frecuencia de escrituras, crecimiento acelerado de tablas e índices y consultas costosas sobre grandes rangos de datos. | Puede alcanzar cientos de millones de registros rápidamente. Requiere particionamiento, compresión, archivado y eventualmente distribución horizontal. |
| Tracking de pelota | Cada posición registrada de la pelota se almacenaría como una fila asociada al partido. | Se comporta como una serie temporal y puede aumentar considerablemente de volumen si se incrementa la frecuencia de medición. | Las inserciones continuas y las consultas sobre trayectorias o períodos de tiempo pueden resultar costosas a medida que crece el histórico. | Aunque inicialmente tenga menor volumen que el tracking de jugadores, su crecimiento acumulado puede requerir particionamiento y estrategias específicas de escalabilidad. |


| Tipo de dato | Modelo NoSQL propuesto | Razón de la elección | Ventajas vs SQL | Alternativas consideradas y por qué no se eligieron |
| --- | --- | --- | --- | --- |
| Equipos | Documental | La información de cada equipo puede representarse como un documento autocontenido y cambia muy poco. | Modelo simple, flexible y permite recuperar toda la información del equipo sin joins. | Clave-valor sería posible, pero ofrece pocas posibilidades de consulta. Grafo sería excesivo para relaciones tan simples. |
| Jugadores | Documental | Cada jugador puede almacenarse como un documento independiente, permitiendo flexibilidad ante atributos diferentes o cambios en la información disponible. | Evita esquemas rígidos y simplifica la recuperación del perfil completo del jugador. | Clave-valor limita las consultas por diferentes atributos. Grafo podría representar relaciones, pero agrega complejidad innecesaria para este volumen. |
| Partidos | Documental | Un partido puede representarse naturalmente como un documento que agrupe su información general y estado actual. | Facilita obtener la información completa del partido en una sola lectura y permite evolucionar su estructura. | Clave-valor podría utilizarse para consultar por identificador, pero resulta limitado ante otras búsquedas. Grafo no aporta beneficios importantes. |
| JugadorPartido / Alineaciones | Documental | Las alineaciones suelen consultarse junto con el partido, por lo que pueden almacenarse dentro del documento correspondiente al encuentro. | Reduce joins y permite obtener el partido junto con sus alineaciones mediante una única consulta. | Grafo modelaría bien las relaciones entre jugadores y partidos, pero sería innecesario para consultas relativamente simples. Mantener cada relación como documento independiente produciría más consultas. |
| Eventos del partido | Columbares / Tabular | Los eventos generan muchas escrituras y normalmente se consultan agrupados por partido y ordenados temporalmente. | Se adapta al gran volumen de información generado y permite trabajar eficientemente con grandes conjuntos de datos | Documental también podría funcionar, pero grandes cantidades de documentos pequeños pueden ser menos eficientes. Clave-valor dificulta búsquedas por tiempo, jugador o tipo de evento. |
| Usuarios | Documental | Los perfiles de usuario pueden variar y crecer con nuevas preferencias o configuraciones sin requerir cambios constantes de esquema. | Flexibilidad de estructura y posibilidad de distribuir usuarios entre múltiples nodos con mayor facilidad. | Clave-valor sería eficiente para búsqueda por ID, pero limitado para otras consultas. Grafo sería útil para una red social compleja, pero no es necesario para el caso planteado. |
| Sesiones | Clave-valor | Cada sesión se identifica principalmente mediante una clave y contiene un pequeño conjunto de datos temporales asociados. | Lecturas y escrituras muy rápidas, fácil distribución horizontal y soporte natural para expiración automática de información. | Documental ofrece capacidades de consulta innecesarias. Wide-column podría escalar, pero agrega complejidad para datos simples y temporales. |
| Comentarios | Columbares / Tabular | Existe un volumen muy alto de escrituras y los comentarios pueden organizarse por partido y tiempo, evitando depender de relaciones complejas. | Facilita la escalabilidad horizontal frente al crecimiento del volumen y evita depender de un esquema relacional complejo. | Documental es viable, pero el patrón es principalmente de escritura secuencial masiva. Grafo solo tendría sentido si las relaciones sociales entre comentarios fueran el aspecto principal. |
| Tracking de jugadores | Base de series temporales | Los datos consisten en mediciones ordenadas temporalmente que se generan continuamente durante el partido. | Optimizada para grandes cantidades de registros temporales, consultas por intervalos de tiempo, compresión y agregaciones temporales. | Documental genera demasiados documentos pequeños. Wide-column puede manejar el volumen, pero una base especializada en series temporales ofrece operaciones más adecuadas para este patrón. |
| Tracking de pelota | Multidimensional/Arrays | Al igual que el tracking de jugadores, consiste en una secuencia de mediciones asociadas al tiempo durante el partido. | Escritura secuencial eficiente, compresión de datos históricos y consultas rápidas sobre intervalos y trayectorias. | Columbares sería una alternativa válida para volúmenes muy grandes, pero requiere modelar manualmente varios aspectos que una base temporal resuelve de forma nativa. |
