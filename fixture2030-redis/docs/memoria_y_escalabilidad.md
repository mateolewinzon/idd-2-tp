# Memoria y escalabilidad — Caché de usuarios y sesiones (Hito 7)

## Plataforma del Fixture del Mundial 2030 — Ingeniería de Datos II

La política elegida es una **recomendación del grupo basada en el comportamiento de cada política y en el Hito 3**. Se justifica por escrito; no se demuestra evicción.

---

## 1. Qué ocupa memoria de verdad

Con los volúmenes del Fixture, las copias estáticas son diminutas: 127 partidos, 64
equipos y 1.664 jugadores caben en cualquier límite razonable. Lo que crece:

1. **Sesiones.** Hito 3: "de 2 a 3 millones de sesiones la ocupan por completo"; la
   memoria es el segundo cuello de botella del sistema (el primero es Neo4j).
2. **Ventanas del feed:** una por partido cada 5 minutos, durante unos 150 minutos por
   partido (doc de Cassandra §1.1), pero con TTL de 5 s a 300 s.
3. **Contadores de visitas:** una clave por partido y día; ocupan poco.

No se dimensiona aquí la memoria necesaria para 2–3 millones de sesiones: no hay una
medición del tamaño de una sesión y no se inventan cifras.

---

## 2. TTL y evicción son cosas distintas

| | Expiración (TTL) | Evicción (`maxmemory`) |
| --- | --- | --- |
| Pregunta | ¿Cuánto tiempo sigue siendo válido el dato? | ¿Qué sacrifica el sistema cuando no hay memoria? |
| Quién decide | El diseño, por dato | La política configurada |
| Cuándo actúa | Al cumplirse el tiempo | Solo bajo presión de memoria |
| Garantía | La clave vence al cumplirse el tiempo | **Un TTL no garantiza que una clave sobreviva hasta ese instante**: Redis puede removerla antes |

Efecto de cada mecanismo en este módulo:

| Dato | Por TTL | Por evicción | Consecuencia de perderlo antes |
| ---- | ------- | ------------ | ------------------------------ |
| Sesión | Inactividad de 30 min: comportamiento esperado | El usuario pierde la sesión sin haber estado inactivo | Se reautentica. Tolerable, pero molesto |
| Ficha | 1 h sin renovarse | Se descarta antes | Un miss: una lectura a Neo4j. **Costo alto**: Neo4j es el primer cuello de botella |
| Feed | 5 s a 300 s | Se descarta antes | Un miss: una lectura a Cassandra. Costo bajo |
| Plantel | 1 h | Se descarta antes | Dos lecturas a MongoDB. Costo bajo |
| Contador de visitas | 7 días | Se descarta antes | Se pierde el conteo del día; no hay fuente donde reconstruirlo |

Una caché debe poder reconstruirse desde su fuente. La sesión y el contador **no**
tienen fuente: lo que se pierde de ellos no se recupera.

---

## 3. Política de memoria elegida: `volatile-ttl`

**Orden de sacrificio deseado:** feed < sesión < ficha (y plantel).

- Feed: perderlo cuesta una lectura a Cassandra, que escala horizontalmente.
- Sesión: perderla obliga a reautenticarse (Hito 3: "las sesiones de ese shard se rehacen").
- Ficha: perderla carga a Neo4j, el primer cuello de botella.

Sobre `volatile-ttl`: *"Prioriza claves con expiración y menor tiempo restante. Útil
solo cuando el producto asigna TTL cortos a los mejores candidatos para descartar"*. Es
nuestro caso: los TTL se asignaron para que los mejores candidatos a descartar sean los
de menor valor.

| Clave | TTL | Posición al descartar (menor TTL restante primero) |
| ----- | --- | -------------------------------------------------- |
| Feed, ventana actual | 5 s | 1.º |
| Feed, ventana cerrada | 300 s | 2.º |
| Sesión | 1800 s | 3.º |
| Ficha y plantel | 3600 s | 4.º |
| Contador de visitas | 604800 s | 5.º |

**Límites del argumento:**

- La política compara el tiempo **restante**, no el TTL inicial. Una ficha a la que le
  quedan 100 s se descarta antes que una sesión recién renovada. El orden vale para
  claves recién creadas y se vuelve aproximado a medida que envejecen.
- El contador de visitas es lo último en descartarse por tener el TTL más largo, aunque
  su valor de negocio es bajo. Se acepta: ocupa una clave por partido y día.
- Exige **disciplina**: todo `SET` debe llevar `EX`, y toda clave debe tener `EXPIRE`.
  La política solo considera claves con expiración. Por eso `ciclo_de_vida_e_invalidacion.md` fija `SET … EX` en las copias, y `EXPIRE` dentro de `MULTI/EXEC` junto con `HSET` (sesión) o con `INCR` (visitas).

**Por qué no las otras:**

| Política | Comportamiento | Por qué no |
| -------- | ----------- | ---------- |
| `allkeys-lru` | "Útil para una instancia dedicada exclusivamente a caché de lecturas" | La instancia no es solo caché: contiene sesiones y contadores, que no se pueden reconstruir. Evictaría sesiones activas por antigüedad de uso, tengan o no TTL. |
| `noeviction` | "Devuelve error para operaciones que agregan datos" | Al llenarse la memoria, crear una sesión fallaría: nadie podría ingresar durante un pico. |
| `allkeys-lfu` | "Puede ser razonable si pocos partidos o perfiles concentran gran parte del tráfico" | Eso ocurre (la final recibe 3–5 M de comentarios frente a 50–200 mil en partidos menores, doc de Cassandra §1.1), pero trata igual a sesiones inactivas y a copias. |
| `volatile-lru` | "Considera solo claves que ya tienen expiración" | Ordena por último uso, no por TTL; no permite expresar el orden feed < sesión < ficha. |

**Configuración:** `maxmemory` y la política se fijan con `CONFIG SET`. En el laboratorio se aplica
`CONFIG SET maxmemory-policy volatile-ttl` en `scripts/inicializacion.redis`. El valor
de `maxmemory` del laboratorio es 256 mb: no está dimensionado
para 2–3 millones de sesiones. Cómo conservar el ajuste después de un reinicio se resuelve en la fase de scripts.

---

## 4. Un nodo frente a las topologías de Redis

El ambiente de este módulo es **un único nodo Redis en un contenedor local**. Es un
entorno de aprendizaje: no es una topología de alta disponibilidad ni Redis Cluster.

| Topología | Qué resuelve | Limitación | ¿Está aquí? |
| -------------- | ------------ | ---------- | ----------- |
| Standalone | Laboratorio o carga moderada | Único punto de falla y límite de RAM/CPU de una máquina | **Sí** |
| Primary + réplicas (con Sentinel para monitoreo) | Copias para lectura y recuperación ante la caída del primary | Las réplicas pueden estar atrasadas; la escritura sigue en el primary | No |
| Redis Cluster | Reparte claves en slots y permite sumar nodos para capacidad y escritura | Una operación con varias claves debe considerar si caen en el mismo slot | No |

Qué dice Hito 3 y **no está implementado aquí**:

- **Replicación master-réplica asíncrona** (Hito 3): se pierden las escrituras todavía no
  propagadas si cae el master. Con un solo nodo no hay réplica ni failover.
- **Distribución por "consistent hashing"** sobre el id de sesión (Hito 3). **Revisión:**
  Redis Cluster distribuye las claves con un hash de la clave que deriva un *slot* lógico, no con consistent hashing. La intención de Hito 3 (repartir
  sesiones entre nodos por hash de su id) se mantiene, pero el mecanismo de Redis Cluster es el de slots. Este módulo no implementa ninguno de los dos.
- **Sticky sessions** (Hito 3): fijan a cada usuario al mismo nodo para que lea sus
  propias escrituras. Con un solo nodo no hacen falta y no se aplican.

**Compatibilidad con Cluster:** la renovación de sesión (`MULTI/EXEC`) opera sobre **una
única clave**, así que no necesitaría etiquetas de hash para caer en el mismo slot.

---

## 5. Persistencia: revisión frente a Hito 2

Hito 2 aceptó "mantener esta información volátil puramente en memoria, priorizando la
velocidad sobre la durabilidad". El laboratorio **se aparta** de eso: usa la configuración estándar del laboratorio, con `--appendonly yes --save 60 1` y el volumen `~/docker/data/redis`.

**Justificación de la revisión:**

- El entorno exige preservar los datos locales de Redis en `~/docker/data/redis`.
- Permite detener y reiniciar el ambiente sin perder la carga de muestra.
- No cambia el rol de Redis: persistir no convierte una clave derivada en
  fuente autoritativa. Las copias siguen siendo reconstruibles desde su fuente y la
  sesión sigue siendo un dato de vida corta.
- La decisión de Hito 2 sobre producción no se modifica en este hito: la persistencia es una
  elección del laboratorio.

En producción se revisan frecuencias, costo de I/O, memoria durante el
snapshot y recuperación. Qué ocurre con los TTL tras un reinicio **no está establecido de antemano**: se
registra lo observado en la evidencia (`evidencia/06_persistencia.txt`) y no se afirma
como regla.

---

## 6. Pasos futuros de escala

1. **Dimensionar `maxmemory`** con una medición del tamaño real de una sesión y de cada
   copia (`INFO memory`), para estimar la memoria de 2–3 millones de sesiones.
2. **Agregar una réplica y monitoreo (Sentinel)** para eliminar el punto único de falla
   (Hito 3: SLA de 99,99%).
3. **Pasar a Redis Cluster** cuando la memoria o la escritura superen a un nodo,
   revisando antes si alguna operación multi-clave exige el mismo slot.
4. **Decidir la corrección de Hito 3** (consistent hashing frente a slots) y las sticky
   sessions si se despliega más de un nodo.
5. **Revisar la política de memoria** con una prueba que provoque evicción en un volumen
   controlado.
