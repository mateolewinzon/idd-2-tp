# Sección 1: Síntesis del diagnóstico inicial (0,5–1 página)

Durante el Hito 1 se identificaron 9 conjuntos de datos con comportamientos claramente diferenciados. A
su vez, se los dividió en dos grupos principales según sus características:  Grupo A (volúmenes bajos,
datos prácticamente fijos con escritura ocasional) y Grupo B (altos volúmenes de datos, picos de escritura
y lectura)

El grupo A está constituido por: Equipos (~64), Jugadores (1.500+), Partidos (~175) y Alineaciones
(5.000-6.000).

En cambio, El Grupo B, se haya formado por:  Usuarios y Sesiones (2-3M simultáneos, con crecimiento
constante o explosivo durante partidos), Comentarios (1M+ por partido, con picos masivos de escritura),
Eventos (5.000-10.000 por partido) y Tracking de jugadores y pelota (200k-1,5M y 10k-50k por partido
respectivamente, generados en tiempo real).
En cuanto a patrones de acceso, los datos del primer grupo son de lectura frecuente y escritura ocasional,
por lo que no condicionan mayormente la selección tecnológica. El segundo grupo, en cambio, combina
lectura y escritura intensiva y simultánea: Sesiones requiere operaciones muy rápidas sobre datos de
corta duración; Comentarios y Eventos combinan escritura masiva con lectura en tiempo real; y el
Tracking de jugadores y pelota se comporta como series temporales de escritura continua con lectura
mayormente analítica. Este contraste entre datos estables y datos de alta concurrencia/velocidad es el eje
que orienta la elección de modelos de persistencia. Estos hallazgos son los que sugieren mayores
beneficios en el uso de modelos NoSQL.
# Sección 2: Criterios y método de evaluación (0,5–1 página)

#
Criterio
Peso Qué evaluaría
Por qué importa en nuestro
Fixture
1
Adecuación de la
estructura de
datos
15% Qué tan naturalmente el modelo
representa documentos, relaciones, y
datos de la entidad
Tenemos tipos de datos muy
distintos: equipos/jugadores,
eventos, sesiones, comentarios y
tracking.
2
Adecuación al
patrón de acceso
20% Lecturas, escrituras, acceso por clave,
navegación de relaciones, consultas
por tiempo y agregaciones según
casos de uso.
Definimos patrones muy diferentes:
sesiones con acceso muy
frecuente, comentarios con
escritura masiva y tracking con
lectura analítica.
3
Escalabilidad
20% Capacidad de escalar horizontalmente,
soportar crecimiento, concurrencia y
distribución geográfica global.
Hay millones de usuarios de todo
el mundo, grandes picos de carga
y datos históricos que pueden
acumular grandes volúmenes
4
Rendimiento
20% Latencia de las operaciones
El escenario exige menos de 100
ms para el 95% de las consultas
críticas y más de 100.000 requests
/s en situaciones de alta demanda.

#
Criterio
Peso Qué evaluaría
Por qué importa en nuestro
Fixture
5
Consistencia
10% Nivel de integridad, consistencia
fuerte/eventual y tolerancia a datos
temporalmente desactualizados.
No todos los datos necesitan el
mismo nivel: un estado de partido
no tiene el mismo requisito que
una sesión o una estadística
histórica.
6
Complejidad
operacional e
integración
5% Madurez, herramientas, dificultad de
administración e integración con la
plataforma.
No debería dominar la decisión
técnica, pero sí impacta en la
dificultad de la implementación
7
Disponibilidad y
resiliencia
10% Tolerancia a fallos, y capacidad de
seguir funcionando ante caída de
nodos o regiones.
El requisito es 99,99% de
disponibilidad y operación en
múltiples regiones.

TOTAL
100%

# Sección 3: Matriz de decisión (1–2 páginas o planilla anexa)

Base
Para qué
Por qué
Alternativa
Por qué se descarta la alternativa
MongoDB
Documental
Equipos, Jugadores,
Alineaciones, Partidos
y Usuarios
Entidades de estado con atributos
variables/semiestructurados; se recupera la
entidad completa por ID en una sola lectura, sin
joins. Un partido se lee y actualiza como unidad
de estado, no se navega por relaciones.
Esquema flexible.
Neo4j (Grafo) / IRIS
(Objetos)
Volumen bajo y relaciones simples o
conocidas no justifican grafo; los
partidos se recuperan por ID, no se
recorren. Objetos añade
composición/herencia que no
aprovechamos y complejiza sin ganar
consulta por atributos.
Neo4j
Grafo
Eventos del partido
(goles, asistencias,
tarjetas, sustituciones)
El valor del evento está en las relaciones
(ANOTA, ASISTE, REEMPLAZA, PARTICIPA); Neo4j
las recorre en consultas multi-salto sin joins.
Dataset acotado (~1–1,75M en todo el torneo),
no de escritura masiva: el patrón relacional
—no el volumen— define la elección.
Cassandra
(Columnar)
Su fortaleza es la escritura masiva
concurrente, que acá no existe (~1–2
eventos/s por partido). Además obliga
a modelar y desnormalizar a mano las
relaciones que dan el valor analítico.
Redis
Clave-valor
Sesiones
Lectura/escritura sub-milisegundo, expiración
TTL nativa y distribución simple para datos
efímeros de corta vida, accedidos por clave.
MongoDB /
Cassandra
Aportan overhead de índices y
persistencia para datos temporales, sin
expiración nativa ni la latencia
requerida; Cassandra agrega
complejidad para operaciones muy
simples.
Cassandra
Columnar
Comentarios e
interacciones
Escritura masiva tipo append, partición por
partido, orden temporal y escalado horizontal
lineal ante picos reales de 1M+ por partido
concurrentes con la lectura.
MongoDB
Manejar muchos documentos
pequeños bajo escritura masiva es
menos eficiente; la flexibilidad del
documento aporta menos que la
capacidad de absorber escrituras y
distribuir volumen.
InfluxDB
Series
temporales
Tracking de jugadores
y pelota
Mediciones ordenadas por tiempo con
ingestión continua; compresión y
agregaciones/downsampling nativos sobre
cientos de miles de puntos por partido, con
lectura mayormente analítica por intervalos.
Cassandra / IRIS
(Objetos)
Cassandra maneja el volumen pero
obliga a implementar a mano la
retención y agregación temporal;
Objetos no aporta nada a datos de
serie temporal.

# Sección 4: Justificación de decisiones y alternativas
1.  MongoDB para equipos, jugadores, alineaciones y usuarios.
- ​ Se selecciona un modelo documental por su capacidad para manejar atributos variables y
semiestructurados. Esto nos permite recuperar toda la información de los perfiles (jugadores
o usuarios) mediante un esquema flexible en una única lectura, sin la necesidad de realizar
joins.
- ​ Como alternativas, se evaluaron Neo4j (Grafos) e InterSystems IRIS (Objetos). La primera
fue descartada porque, si bien estas entidades estan relacionadas, son relaciones muy
simples, y tienen un volumen bajo, lo cual no justifica la complejidad de un grafo. Por el lado
de IRIS, no se estarian aprovechando la herencia y composición que te brinda un esquema
orientado a objetos, agregando complejidad sin ganancia al sistema. Decidimos aceptar la
redundancia generada por la base documental a cambio de velocidad de lectura y
flexibilidad.
2.  Neo4j para partidos y eventos
- ​ Iterando sobre el Hito 1, el mayor valor para estas entidades reside en la navegación de las
relaciones. El modelo de grafos nos permite recorrer relaciones semánticas (quien metió gol,
quien asistió a, fue reemplazado por, etc) mediante consultas ‘multi-salto’ de alta velocidad.
Este modelo es ideal para aquellos datos que vayan a ser fuertemente analizados.
- ​ Se analizaron CassandraDB y MongoDB como alternativas. Si bien ambos modelos proveen
una inserción rápida, lo cual es clave para la escritura de eventos en tiempo real, ninguno
brinda la plataforma relacional de los grafos que nos permiten aprovechar las herramientas
para análisis de datos.
3.  Redis para las sesiones
- ​ Las sesiones de los usuarios son datos efímeros y de corta vida. Se elige un modelo de
clave - valor por su capacidad para ejecutar operaciones de lectura y escritura en tiempos
menores al milisegundo y su gestión nativa de la expiración de datos (TTL).
- ​ Se descartaron opciones como CassandraDB o MongoDB debido al overhead innecesario
que generan sus índices y mecanismos de persistencia en disco. Estos motores no poseen
un TTL nativo tan optimizado ni garantizan la latencia extrema requerida para mantener 2 a
3 millones de sesiones activas en simultáneo. El trade-off aceptado es mantener esta
información volátil puramente en memoria, priorizando la velocidad sobre la durabilidad.
4.  Cassandra para comentarios
- ​ Este conjunto exige absorber una escritura tipo append masiva (más de 1 millón de registros
por encuentro). La arquitectura columnar permite particionar los datos por partido, mantener
un ordenamiento temporal eficiente y escalar de manera horizontal para distribuir la inmensa
carga operativa.
- ​ Se evaluó MongoDB, pero generar millones de documentos individuales pequeños bajo una
tasa de escritura tan agresiva es estructuralmente menos eficiente. Se descartó para
priorizar el throughput y la distribución que ofrece Cassandra. El trade-off es aceptar un
esquema rígido guiado exclusivamente por las consultas (query-first), sacrificando la
flexibilidad de búsqueda por otros atributos.
5.  InfluxDB para tracking de jugadores y pelota
- ​ Estas métricas consisten en mediciones espacial-temporales continuas y estrictamente
ordenadas. Se elige este modelo por su motor de ingestión optimizado, compresión nativa
de datos y funciones integradas de agregación y downsampling temporal.
- ​ Se consideró utilizar Cassandra o un modelo de Objetos (IRIS). Las bases orientadas a
objetos no aportan ventajas para analizar series de tiempo, y aunque Cassandra podría
soportar el volumen de escritura, obligaría a implementar de forma manual toda la lógica de

retención, purga y cálculo de intervalos temporales. El trade-off asumido es incorporar un
motor de base de datos extra y muy especializado dentro de la arquitectura global.

# Sección 5: Mapa de persistencia y próximos interrogantes
Mapa de persistencia

Necesidad de Datos /
Entidad
Modelo de Persistencia
Asignado
Motor Tecnológico Propuesto

Equipos
Documental
MongoDB
Jugadores
Documental
MongoDB
Usuarios
Documental
MongoDB
Partidos
Grafo
Neo4j
Eventos del Partido
Grafo
Neo4j
Sesiones
Clave-valor
Redis
Comentarios
Columnar
Cassandra
Tracking de Jugadores
Series Temporales
InfluxDB
Tracking de Pelota
Series Temporales (o
Multidimensional)
InfluxDB

Próximos interrogantes
La adopción de esta arquitectura políglota plantea desafíos de integración y consistencia que deberán
abordarse durante la fase de implementación documental de equipos y jugadores:
- ​ Sincronización Inter-Modelo: ¿Qué mecanismo (por ejemplo, colas de mensajes o event-sourcing)
se implementará para garantizar que un cambio crítico en un documento de MongoDB (ej. lesión de
un jugador) se refleje de manera consistente en los eventos almacenados en el grafo de Neo4j?
- ​ Diseño del Esquema Documental: ¿Cómo se estructurarán los documentos de Jugadores y
Equipos para minimizar la redundancia sin generar una necesidad de referenciar de manera
excesiva que impacte en la latencia de lectura?
- ​ Gestión del Histórico en Cassandra: ¿Cuál será la estrategia de partición exacta para los
comentarios de partidos de alta popularidad para prevenir hot-spots (cuellos de botella) en nodos
específicos durante los picos de 3 millones de usuarios simultáneos?
