Ingeniería de Datos II: Hito 3
# Sección 1: Síntesis de decisiones previas (0,5-1 página)

Necesidad
de datos
Características
identificadas
Modelo y
motor
seleccionad
os
¿Requiere
diseño
distribuido?
Justificación
Equipos,
jugadores y
alineacione
s
Volumen bajo,
lectura frecuente y
escritura ocasional.
Datos variables o
semiestructurados,
recuperados
principalmente por
ID.
Documental
— MongoDB
No por
volumen; sí
replicación
por
disponibilida
d.
El volumen no
supera
necesariamente la
capacidad de un
único servidor. Sin
embargo, el
requisito de 99,99 %
de disponibilidad y
la operación en
múltiples regiones
justifican mantener
réplicas para
eliminar un punto
único de falla.
Usuarios
Crecimiento
constante y
millones de
usuarios
concurrentes.
Acceso frecuente a
perfiles completos.
Documental
— MongoDB
Sí.
La concurrencia, el
crecimiento y la
distribución
geográfica requieren
escalamiento
horizontal. El
particionamiento
permite distribuir la
carga y las réplicas
regionales reducen
la latencia y
aumentan la
disponibilidad.

Partidos y
eventos
Aproximadamente
175 partidos y entre
5. 000 y 10.000
eventos por partido.
El valor principal
está en relaciones
como ANOTA,
ASISTE,
REEMPLAZA y
PARTICIPA.
Grafo —
Neo4j
No por carga
de escritura,
sí replicación
por
disponibilida
d.
El modelo fue
elegido por la
navegación de
relaciones, no por el
volumen. Por eso, el
particionamiento no
aparece como una
necesidad inicial,
aunque la
replicación resulta
necesaria para
evitar un punto
único de falla.
Sesiones
Entre 2 y 3 millones
de sesiones
simultáneas, de
corta duración,
accedidas por clave
y con necesidad de
latencia
submilisegundo.
Clave-valor
— Redis
Sí.
La carga supera lo
conveniente para un
único nodo. Redis
utiliza consistent
hashing, presentado
en la clase como
una técnica para
distribuir claves,
reducir el
rebalanceo y escalar
horizontalmente.
Comentario
s e
interaccione
s
Más de un millón
por partido, con
picos masivos de
escritura y lectura
en tiempo real.
Columnar —
Cassandra
Sí.
Requieren
particionamiento
para distribuir
escrituras y volumen
entre múltiples
nodos. La clase
señala que
Cassandra utiliza
arquitectura en
anillo y consistent
hashing. Debe
evitarse que la
partición por partido
genere hotspots
durante los
encuentros más
populares.

Tracking de
jugadores y
pelota
Entre 200.000 y 1,5
millones de
registros de
jugadores y entre
10. 000 y 50.000 de
pelota por partido,
generados
continuamente y
consultados por
intervalos
temporales.
Series
temporales
— InfluxDB
Sí, por
acumulación
e ingestión
continua.
El particionamiento
permite distribuir el
volumen histórico y
paralelizar
operaciones. La
replicación aporta
disponibilidad y
durabilidad. La
estrategia concreta
de particionamiento
no fue definida en el
hito anterior, por lo
que no corresponde
anticiparla aquí.

# Sección 2: Análisis CAP y modelos de consistencia (1-1,5
páginas)
Sesiones (Redis)
Para las sesiones adoptaremos un esquema AP, sacrificando la consistencia pura.
Nuestro razonamiento para esto se basa en la idea de que los usuarios siempre
puedan acceder a la plataforma sin mayores problemas, incluso cuando podamos
tener una caída en alguna de las particiones del servidor. Nos parece evidente que
el sistema debe permitir a los usuarios seguir utilizando la aplicación si algún nodo
fallase, y en ese escenario decidimos darle prioridad a la disponibilidad. Además,
creemos que en este caso podemos adoptar un esquema de consistencia de sesión,
lo cual nos permite brindarle a los usuarios una experiencia fluida durante su estadía
en la aplicación. Al no tratarse de un servicio crítico, como podría ser un banco,
podemos sacrificar la consistencia y tener dos sesiones “activas” del mismo usuario
durante un periodo.

Comentarios (CassandraDB)
En este caso, volvemos a elegir un esquema AP. En primer lugar, Cassandra está
diseñado para este tipo de esquemas, donde se prioriza la disponibilidad y la
tolerancia a particiones por encima de una consistencia fuerte. Pensando en el
negocio parece bastante intuitivo decir que no podemos bloquear la funcionalidad
entera si hubiese una partición de red teniendo en cuenta que estimamos tener 1
millón de registros por encuentro, pensando en la consistencia, ya que la
información que se manipulara en esta sección es de importancia baja y no afecta
otros subsistemas. Podemos aceptar que durante algunos momentos, un usuario

pueda no ver el último comentario de su amigo sobre un partido, teniendo en cuenta
además que adoptaremos una convergencia eventual sobre los mismos.

Equipos y Jugadores (MongoDB)
Para estas entidades adoptamos un esquema AP, nuevamente. Nuestro
razonamiento detrás de esto reside, principalmente, en la idea de que son dos
entidades en las que no escribiremos a menudo, pero si tienen que estar disponibles
para la lectura constantemente. A nuestro entender, estas entidades rara vez
sufrirán modificaciones, ya que una vez iniciada la competencia los equipos y los
jugadores no suelen modificarse. Por lo tanto, no vemos justificable priorizar la
consistencia fuerte. Podemos asumir el riesgo de que estas pocas escrituras no se
vean reflejadas instantáneamente para todos los usuarios, si de eso depende que la
información esté siempre disponible.
Usuarios (MongoDB)
En contraposición a lo dicho en el último párrafo, en este caso vamos a inclinarnos
por un esquema CP. Esto es porque encontramos la necesidad de preservar la
consistencia sobre todo a la hora de los registros de usuarios. No podemos permitir
que dos usuarios se registren con una misma dirección de correo. En este caso,
deberíamos bloquear temporalmente los nuevos registros ante una partición en la
red, pero es un costo aceptable con tal de no tener estas colisiones de usuarios.

Partidos y Eventos (Neo4j)
Este punto presenta un dilema. Por un lado, afecta la experiencia del usuario que
los datos no sean consistentes. Si entro a ver un partido en el que acaba de ver un
gol y no veo quien lo hizo mi experiencia no será excelente. Pero, por otro lado,
parece inadmisible no mostrar la información de partidos y eventos hasta que no
sean consistentes. Es por esto que nos inclinamos por un esquema AP con una
consistencia causal. La consistencia causal nos acompaña a la hora de mantener
una lógica de negocio, por ejemplo, de no mostrar una tarjeta si no hubo una
infracción previamente. De esta manera, mantenemos la disponibilidad de los datos
arriba incluso cuando haya una partición de red, aceptando que los usuarios
consuman información temporalmente desactualizada.

Tracking de jugadores (InfluxDB)
Por último, para el tracking de jugadores y de la pelota la decisión es sencilla. Esta
información no será consultada por los usuarios constantemente en la mayoría de los
casos. Sino que será utilizada posteriormente para realizar Data Analysis. Por esto, es
sencillo concluir que la consistencia fuerte es innecesaria en este caso. Además, estos

datos tienen mucho valor, por lo que es muy costoso frenar su escritura por una partición de
red. Por lo tanto, iremos con un esquema de AP. Aceptamos que por algunos segundos la
información no se encuentre actualizada para todos los usuarios, pero ganando el poder de
escribir siempre nuevas entradas.
# Sección 3: Replicación, particionamiento y quórum (1-1,5
páginas)
# Sección 3: Replicación, particionamiento y quórum
Sesiones (Redis). El acceso es puntual por clave, de muy alta frecuencia y corta duración.
Las claves se distribuyen con consistent hashing sobre el identificador de sesión, lo que
mantiene bajo el riesgo de hotspot porque el hash las reparte de forma uniforme entre los
nodos del anillo. La replicación es master-réplica asíncrona, sin quórum configurable: el
master confirma solo, lo que equivale a W=1 y sostiene la latencia submilisegundo que
exigen 2-3 millones de sesiones simultáneas. La garantía es de sesión, y no la aporta la
replicación sino las sticky sessions, que fijan a cada usuario al mismo nodo para que
siempre lea sus propias escrituras. El costo es perder las escrituras todavía no propagadas
si cae el master.
Comentarios (Cassandra). El patrón es de escritura masiva y concurrente por partido, con
lectura en tiempo real. La partición es compuesta por partido y ventana temporal, con orden
interno por el momento del comentario. Si se particionara solo por partido el riesgo de
hotspot sería alto, porque un encuentro de gran audiencia concentraría toda la escritura en
una única partición y sus tres réplicas; la ventana temporal la divide en particiones
sucesivas y los virtual nodes las reparten entre nodos distintos del anillo. La replicación es
en anillo peer-to-peer con factor de réplica 3 y quórum N=3, R=2, W=1, de modo que R+W =
3 ≤ N y la garantía resultante es eventual. W=1 confirma con una sola réplica y permite
absorber el pico de más de un millón de comentarios por partido, mientras que R=2 reduce
la probabilidad de mostrar un comentario atrasado sin frenar la escritura. La convergencia
entre réplicas se resuelve en segundo plano con anti-entropy y merkle trees, y al no haber
master la caída de un nodo no bloquea la escritura.
Equipos y Jugadores (MongoDB). El acceso es de lectura frecuente por ID y escritura
ocasional. No se particiona porque el volumen no lo justifica, y sin particionamiento no hay
partición que pueda concentrar carga. La replicación es master-slave, con el primario
recibiendo las escrituras y los secundarios sirviendo las lecturas, bajo un quórum N=3, R=1,
W=2, donde R+W = 3 ≤ N y la garantía es eventual. R=1 da la lectura más rápida posible
contra un secundario, que es el patrón dominante, y W=2 protege la escritura sin costo real,
porque las altas y bajas de plantel son esporádicas y no compiten con el tráfico de lectura.
Usuarios (MongoDB). Combina una escritura de registro poco frecuente pero sensible con
una lectura de perfil muy frecuente. El particionamiento es geográfico por región, con hash
sobre el identificador de usuario dentro de cada una: el hash mantiene bajo el riesgo de
hotspot dentro de la región, mientras que el riesgo propio del criterio geográfico es la
distribución desigual entre regiones, ya que una sede con más audiencia sostiene más
carga que otra. La replicación es semi-síncrona —la escritura espera la confirmación de la
mayoría del conjunto— con secundarios en cada región, y el quórum es N=3, R=2, W=2. Es
el único subsistema que cumple R+W = 4 > N, y por lo tanto el único con garantía fuerte:
lectura y escritura comparten al menos una réplica, lo que impide registrar dos usuarios con
el mismo correo. Cuesta latencia en el alta y bloquea el registro si se pierde la mayoría, que
es el sacrificio del esquema CP de la Sección 2.

Partidos y Eventos (Neo4j). El acceso es de navegación de relaciones, es decir recorridos
del grafo. No se particiona, porque partir el grafo convertiría cada recorrido en una
cross-shard query entre particiones; sin particionamiento no hay hotspot posible, aunque el
costo se traslada a la capacidad de un solo nodo, viable con 127 partidos. La replicación es
semi-síncrona con quórum de 2 de 3, expresado como N=3, R=1, W=2, donde R+W = 3 ≤
N. W=2 aporta durabilidad y fija el orden del log confirmado, y R=1 mantiene la lectura
rápida durante el partido. La garantía causal, sin embargo, no surge del quórum: la aporta el
timestamp lógico que el cliente arrastra entre lecturas, que impide que lo atienda una réplica
que todavía no aplicó lo que ese cliente ya vio. Sin ese mecanismo, dos lecturas sucesivas
en réplicas distintas romperían la consistencia monotónica y un gol ya visto podría
desaparecer al refrescar. El costo es el overhead de tracking causal.
Tracking de jugadores y pelota (InfluxDB). El patrón es de ingesta continua y consulta
por intervalos temporales. El particionamiento es por rango sobre la ventana temporal,
combinado con el partido: el rango favorece la consulta por intervalos pero concentra la
escritura, porque la ventana más reciente recibiría toda la ingesta en vivo, y combinarla con
el partido reparte la ingesta simultánea entre segmentos distintos. La replicación es
asíncrona y sin quórum, ya que la ingesta se confirma sin esperar réplicas, con garantía
eventual. Esto evita que la ingesta se frene esperando confirmaciones, que es el riesgo
principal con hasta 1,5 millones de registros por partido. Se acepta perder los últimos puntos
no propagados ante la caída de un nodo, porque el análisis posterior trabaja sobre
agregados y no sobre registros individuales.
Donde hay quórum, la garantía se define por la relación R + W > N. Solo Usuarios la
cumple, y es el único subsistema con esquema CP: esa relación obliga a que lectura y
escritura compartan al menos una réplica, y por lo tanto a que una lectura vea la última
escritura confirmada. En los demás R + W ≤ N, o directamente no hay quórum porque la
replicación es asíncrona, lo que corresponde a convergencia eventual. N se mantiene impar
para que la elección por mayoría ante una partición de red no derive en split-brain.
Resolución de conflictos. Ningún subsistema adopta un esquema multi-master, que es
donde aparecen los conflictos de escritura. El criterio es evitarlos por diseño antes que
resolverlos después: en Redis, MongoDB y Neo4j existe un único nodo que acepta
escrituras para cada dato, de modo que dos escrituras concurrentes se serializan en ese
nodo y no divergen. En InfluxDB cada punto queda identificado por su marca temporal y sus
etiquetas, así que dos ingestas simultáneas no compiten por el mismo registro. Cassandra
es el único caso con escritura en cualquier nodo del anillo, pero los comentarios son
inserciones inmutables que no se actualizan: dos escrituras nunca disputan la misma celda
y el orden se resuelve por el momento del comentario. El conflicto residual, entonces, no es
de contenido sino de propagación, y se resuelve con la convergencia en segundo plano ya
descrita.
# Sección 4: Escalabilidad, fallos y métricas (1-1,5 páginas)
Escenario de crecimiento. La carga no es uniforme: la determina el calendario del torneo. Entre
partidos el sistema opera sobre una línea base baja, y durante los encuentros de alta audiencia debe
sostener entre 2 y 3 millones de usuarios simultáneos y más de 100.000 solicitudes por segundo.
Sobre esa base se superponen dos crecimientos de naturaleza distinta. Uno es transitorio y se repite
en cada partido —concurrencia de sesiones, comentarios y eventos— y vuelve a la línea base al
terminar el encuentro. El otro es acumulativo y no se revierte: el tracking suma hasta 1,5 millones de
registros por partido, que sobre 127 encuentros se acercan a los 200 millones de puntos, y los
comentarios superan el millón por partido. Equipos, jugadores y partidos, en cambio, tienen volumen
fijo desde el inicio del torneo. El crecimiento sostenido se concentra entonces en Cassandra e
InfluxDB, y el pico de concurrencia en Redis y Cassandra.

Estrategia de escalamiento. El criterio es escalar horizontalmente donde el volumen o la
concurrencia crecen sin techo, y verticalmente donde el dato es acotado y el costo de distribuir
supera el beneficio. Comentarios y tracking escalan agregando nodos, apoyados en el
particionamiento compuesto ya definido: las particiones nuevas se reparten entre los nodos
incorporados sin obligar a redistribuir el histórico. En tracking el escalamiento no es solo de
hardware, porque las políticas de retención y el downsampling reducen la resolución del dato
antiguo y contienen el crecimiento del histórico en lugar de acompañarlo. Sesiones también escala
horizontalmente, y el consistent hashing es lo que abarata ese crecimiento, porque agregar un nodo
mueve solo una fracción de las claves. Usuarios escala incorporando regiones, que en un esquema de
partición geográfica equivale a agregar particiones. Equipos y jugadores se resuelve verticalmente,
porque el volumen es fijo y, si hiciera falta más capacidad de lectura, alcanza con sumar secundarios
sin particionar. Partidos y eventos es el único caso sin salida horizontal, ya que decidimos no
particionar el grafo: crece agregando réplicas de lectura y ampliando el nodo de escritura.
Cuellos de botella previsibles. El primero en aparecer es Neo4j. Es la tecnología con la peor
calificación de escalabilidad de la matriz del Hito 2, no está particionada y concentra toda la escritura
en un único nodo; con varios partidos simultáneos generando entre 5.000 y 10.000 eventos cada
uno, esa escritura no tiene cómo repartirse. La mitigación es parcial y se apoya en el patrón de
acceso real: el tráfico dominante es de lectura y las réplicas sí escalan, pero la escritura queda
acotada por la capacidad de un nodo. El segundo es la memoria de Redis, porque el almacenamiento
es íntegramente en RAM y de 2 a 3 millones de sesiones la ocupan por completo; la contención viene
por el TTL corto de las sesiones y por el agregado de nodos. El tercero no es un nodo sino una
ventana: en Cassandra e InfluxDB la ingesta en vivo se concentra siempre en el segmento temporal
más reciente, de modo que el cuello se desplaza con el tiempo en lugar de quedar fijo. Por último, las
consultas de Usuarios que cruzan regiones deben resolverse contra varias particiones y pagan la
latencia de la más lejana.
Fallo de un nodo. En MongoDB la mayoría del conjunto elige un nuevo primario, con una
interrupción de escritura de entre diez y treinta segundos mientras las lecturas siguen atendidas por
los secundarios. En Cassandra no hay master y W=1 se confirma con cualquier otra réplica, así que la
escritura no se interrumpe. En Redis se promueve una réplica del shard afectado, y como la
replicación es asíncrona se pierden las escrituras no propagadas: las sesiones de ese shard se
rehacen, lo cual es tolerable porque son de corta duración. En Neo4j, si cae el nodo de escritura el
quórum de 2 de 3 elige otro; si caen dos, no hay mayoría posible y la escritura se detiene hasta
recuperar un nodo.
Latencia de red elevada. El síntoma es el percentil 99 subiendo sin que aparezcan errores, porque el
sistema sigue respondiendo mientras se degrada. La respuesta es bajar temporalmente el nivel de
lectura donde el esquema es AP, llevando Comentarios a R=1 para sostener el objetivo de latencia a
costa de más lecturas atrasadas. En Usuarios esa palanca no está disponible: reducir R rompería la
relación R+W>N y reintroduciría el riesgo de correos duplicados, de modo que ahí se prefiere
degradar el alta de usuarios antes que la garantía de consistencia.
Fallo regional completo. La partición geográfica de Usuarios correspondiente a esa región queda sin
escritura, y los registros nuevos de esa zona se bloquean hasta que vuelva, que es la consecuencia
asumida al elegir un esquema CP; las réplicas de otras regiones siguen sirviendo la lectura de esos
perfiles. Las sesiones alojadas en la región caída se pierden y sus usuarios vuelven a autenticarse, sin
más impacto que ese por la corta vida de las sesiones. Comentarios se mantiene disponible porque
las réplicas del anillo están distribuidas entre regiones. En Equipos y Jugadores y en Partidos y
Eventos, si el nodo de escritura estaba en la región afectada, se produce el mismo failover descrito
para la caída de un nodo.
Saturación por pico. Un encuentro de gran audiencia dispara simultáneamente la escritura de
comentarios y de tracking. El diseño la absorbe porque ambos confirman con W=1 y no esperan

réplicas, y el riesgo real no es el volumen agregado sino la concentración en la ventana temporal más
reciente, ya mitigada con la clave compuesta. Si aún así se satura, la degradación esperada es que la
convergencia entre réplicas se vuelva más lenta y los comentarios tarden más en verse, no que el
sistema rechace escrituras.
Métricas. La disponibilidad se mide por subsistema y no de forma global, porque las garantías
declaradas difieren entre ellos, y se contrasta contra el objetivo de 99,99%, que equivale a poco más
de cuatro minutos de indisponibilidad mensual. La latencia se sigue por percentiles 50, 95 y 99: el
percentil 95 es el indicador contractual, ya que el escenario exige menos de 100 ms para el 95% de
las consultas críticas, y el 99 funciona como alerta temprana. El throughput se mide en operaciones
por segundo por subsistema, y su valor diagnóstico está en la linealidad: si agregar un nodo no
aumenta el throughput de forma proporcional, el límite no es de capacidad sino un hotspot o un
problema de enrutamiento de consultas. La utilización de CPU, memoria, disco y red se mantiene en
una banda de 60 a 80% para conservar margen ante los picos, y en Redis la memoria ocupada contra
la disponible es la métrica crítica por el límite de RAM. Por último, el estado de las réplicas se sigue
con el retraso de replicación y la cantidad de réplicas vivas por dato: es la métrica que valida las
hipótesis de la Sección 3, porque si el retraso crece, la convergencia eventual deja de resolverse en
segundos y las garantías declaradas dejan de cumplirse. El deterioro se detecta antes de incumplir la
disponibilidad porque el percentil 99, el retraso de replicación y la utilización sostenida por encima
del 80% se degradan mientras el sistema todavía responde.
# Sección 5: Diagrama y decisiones pendientes (0,5-1 página)

Supuestos, riesgos y decisiones futuras
Supuestos
- ​ El particionamiento distribuirá los datos y la carga de manera suficientemente
uniforme.
- ​ El uso de consistent hashing reducirá el movimiento de claves al agregar o quitar
nodos.
- ​ Las réplicas permitirán continuar atendiendo solicitudes cuando falle un nodo.
- ​ En los subsistemas AP, la consistencia eventual resulta aceptable para el negocio.
- ​ Los datos almacenados en réplicas diferentes convergerán una vez resuelta la
partición de red.
- ​ En Usuarios, la relación R+W>NR + W > N permitirá priorizar la consistencia.
- ​ Los subsistemas con R+W≤NR + W \leq N podrán devolver temporalmente datos
desactualizados.
- ​ Agregar nodos aumentará la capacidad de Redis, Cassandra e InfluxDB.
- ​ El volumen de Equipos, Jugadores, Partidos y Eventos seguirá siendo
suficientemente bajo como para no requerir particionamiento.
- ​ Las escrituras concurrentes no producirán conflictos importantes porque se utilizan
nodos únicos de escritura o datos inmutables.

Riesgo
Consecuencia
Particiones mal distribuidas
Aparición de hotspots y sobrecarga de algunos nodos
Particionar únicamente por
partido
Concentración de la carga durante los encuentros
populares
Replicación asíncrona
Pérdida de escrituras todavía no propagadas si falla un
nodo
R+W≤NR + W \leq N
Posibilidad de leer una réplica que todavía no recibió
la última escritura
Pérdida de la mayoría en un
esquema CP
Bloqueo temporal de las escrituras
Retraso elevado de replicación
La convergencia eventual puede tardar más de lo
esperado
Particionamiento geográfico
desigual
Algunas regiones pueden recibir más carga que otras
Grafo sin particionamiento
Neo4j puede convertirse en un cuello de botella de
escritura
División del grafo en el futuro
Aparición de consultas entre particiones
Crecimiento acumulativo
Cassandra e InfluxDB pueden necesitar nuevos nodos
Escalamiento no lineal
Agregar nodos puede no aumentar proporcionalmente
el throughput
Caída del nodo principal
Interrupción de escrituras durante la elección de un
nuevo nodo

Decisiones futuras
1.  Definir el tamaño de las ventanas temporales.​
 Se debe determinar cómo dividir los comentarios y el tracking para evitar hotspots
sin producir demasiadas particiones pequeñas.
2.  Validar las claves de particionamiento.​
 Será necesario comprobar que las claves elegidas distribuyan uniformemente los
datos y la carga.
3.  Definir la ubicación de las réplicas.​
 Se deberá decidir cómo distribuirlas entre regiones para tolerar fallos de nodos y
fallos regionales.
4.  Revisar los valores de NN, RR y WW.​
 Estos valores podrán modificarse según el equilibrio requerido entre consistencia,
disponibilidad y latencia.
5.  Definir el nivel de consistencia aceptable.​
 Para cada subsistema se deberá establecer cuánto tiempo puede tolerarse una
lectura desactualizada.
6.  Establecer el límite de escalamiento vertical.​
 Será necesario determinar cuándo Equipos, Jugadores, Partidos y Eventos dejan de
poder crecer aumentando la capacidad de un único nodo.
7.  Evaluar el cuello de botella de Neo4j.​
 Si aumenta el volumen de eventos, deberá revisarse la decisión de mantener el
grafo sin particionamiento.
8.  Definir cuándo agregar nodos.​
 El escalamiento horizontal deberá activarse según el throughput, la latencia y la
utilización de recursos.
9.  Establecer métricas por subsistema.​
 Se deberán controlar disponibilidad, latencia p50, p95 y p99, operaciones por
segundo, utilización de recursos y retraso de replicación.
10. Revisar las decisiones ante cambios de carga.​
 Las elecciones de CAP, particionamiento, replicación y quórum deberán reevaluarse
si las estimaciones iniciales dejan de representar la carga real.
