# Fixture 2030 — Módulo Redis (Hito 7)

Caché de lecturas, sesiones y contadores temporales del Fixture 2030, implementado
sobre un nodo Redis 7.4 local. El entorno incluye persistencia, política de memoria,
datos representativos, operaciones CRUD, invalidación, concurrencia y evidencia
reproducible.

## 1. Alcance y decisiones

Redis es dueño únicamente de datos temporales: sesiones y contadores de visitas. Las
fichas de partidos, ventanas del feed y planteles son copias descartables de Neo4j,
Cassandra y MongoDB respectivamente. Se aplica Cache-Aside: ante un miss la aplicación
consulta la fuente y carga Redis; ante un cambio actualiza primero la fuente y luego
elimina la copia.

El laboratorio usa un solo nodo. No demuestra alta disponibilidad, Sentinel ni Redis
Cluster. La configuración combina AOF (`appendfsync everysec`) y snapshots RDB, un
límite de 256 MiB y `volatile-ttl`. Todos los datos del modelo tienen vencimiento.

| Tema | Documento |
| --- | --- |
| Problema de concurrencia y patrones | [`docs/patrones_de_acceso.md`](docs/patrones_de_acceso.md) |
| Modelo, estructuras, nombres y TTL | [`docs/modelo_clave_valor.md`](docs/modelo_clave_valor.md) |
| Ciclo de vida, fuente de verdad e invalidación | [`docs/ciclo_de_vida_e_invalidacion.md`](docs/ciclo_de_vida_e_invalidacion.md) |
| Memoria, evicción y escalabilidad | [`docs/memoria_y_escalabilidad.md`](docs/memoria_y_escalabilidad.md) |

## 2. Requisitos

- Docker Desktop o Docker Engine con Docker Compose v2.
- Puerto `6380` libre en el host. Dentro del contenedor Redis conserva el `6379`.
  Puede elegirse otro con `REDIS_PORT`, por ejemplo `REDIS_PORT=6381 docker compose up -d`.
- Aproximadamente 300 MiB disponibles para el contenedor y el volumen.
- Ejecutar los comandos desde `tp/fixture2030-redis`.

## 3. Ejecución rápida

```bash
chmod +x scripts/*.sh
./scripts/ejecutar.sh
```

El script levanta el contenedor, espera `PONG` y ejecuta inicialización, carga, CRUD de
sesiones, caché, métricas y prueba concurrente. La inicialización contiene `FLUSHDB`:
está pensada únicamente para este laboratorio y borra las claves previas de la base.

Ejecución manual:

```bash
docker compose up -d
docker compose exec -T redis redis-cli < scripts/inicializacion.redis
docker compose exec -T redis redis-cli < scripts/carga_muestra.redis
docker compose exec -T redis redis-cli < scripts/sesiones.redis
docker compose exec -T redis redis-cli < scripts/cache.redis
./scripts/concurrencia.sh
docker compose exec -T redis redis-cli < scripts/metricas.redis
./scripts/verificar_persistencia.sh
```

Abrir una consola interactiva:

```bash
docker compose exec redis redis-cli
```

Detener sin perder el volumen y volver a iniciar:

```bash
docker compose stop
docker compose start
docker compose exec -T redis redis-cli DBSIZE
```

`docker compose down` elimina el contenedor pero conserva el volumen. Solo
`docker compose down -v` elimina también los datos persistidos.

## 4. Datos de muestra

La carga crea 13 claves iniciales:

| Categoría | Cantidad | Ejemplo | TTL inicial |
| --- | ---: | --- | ---: |
| Sesiones | 5 | `sesion:SES-0001` | 1.800 s |
| Fichas de partidos | 2 | `cache:partido:P-001` | 3.600 s |
| Ventanas cerradas del feed | 2 | `cache:feed:ARG-ESP-20300624:20300624T2000` | 300 s |
| Planteles representativos | 2 | `cache:plantel:ARG` | 3.600 s |
| Contadores de visitas | 2 | `partido:P-001:visitas:2030-06-08` | 604.800 s |

Los nombres, usuarios, IP del rango reservado `192.0.2.0/24` y resultados son
ficticios. Los JSON de plantel contienen una muestra de jugadores, no los 26 del
equipo: el objetivo es comprobar la estructura y las operaciones sin duplicar toda la
carga de MongoDB.

## 5. Operaciones implementadas

| Archivo | Qué demuestra |
| --- | --- |
| `inicializacion.redis` | Limpieza controlada, política de memoria, persistencia y conectividad. |
| `carga_muestra.redis` | Hashes, Strings JSON, TTL y transacciones de creación. |
| `sesiones.redis` | Crear, leer, renovar y cerrar una sesión con `MULTI/EXEC`. |
| `cache.redis` | Hit, miss, carga con TTL e invalidación de ficha, feed y plantel. |
| `concurrencia.sh` | Varios clientes incrementando la misma clave sin actualizaciones perdidas. |
| `metricas.redis` | Memoria, persistencia, estadísticas, configuración y TTL por categoría. |
| `verificar_persistencia.sh` | Reinicio real del contenedor y conservación de valor y TTL. |
| `generar_evidencia.sh` | Regenera las salidas del laboratorio y un benchmark local. |

`INCR` y `HINCRBY` son operaciones atómicas. `MULTI/EXEC` agrupa la modificación de
una sesión o contador con su `EXPIRE`, evitando que otro cliente intercale comandos.
No hay rollback general: cada comando de la transacción debe ser válido por sí mismo.

La prueba concurrente usa por defecto 20 clientes y 100 incrementos por cliente. Se
puede variar sin editar el archivo:

```bash
CLIENTES=50 OPERACIONES=200 ./scripts/concurrencia.sh
```

## 6. Evidencia y validación

Con Redis levantado, regenerar toda la evidencia:

```bash
./scripts/generar_evidencia.sh
```

Las salidas quedan en [`docs/evidencia`](docs/evidencia): configuración, carga, CRUD,
caché, concurrencia, benchmark, métricas, versión y reinicio del servidor. El benchmark
usa la base aislada 15, que se limpia al terminar, con 10.000 solicitudes, 50 conexiones
y las operaciones `SET`, `GET` e `INCR`. Sus cifras describen únicamente esta
computadora y este contenedor; no proyectan las 100.000 solicitudes por segundo del
escenario.

Comprobaciones esperadas:

- `PING` responde `PONG` y `maxmemory-policy` es `volatile-ttl`.
- Después de la carga, `DBSIZE` informa 13 antes de que venza alguna clave.
- Toda clave de negocio tiene `TTL` positivo; `-1` indicaría un error de diseño.
- Al cerrar una sesión, `EXISTS` devuelve `0` y `TTL` devuelve `-2`.
- Tras invalidar una copia, `EXISTS` devuelve `0`.
- En concurrencia, resultado obtenido y esperado coinciden.
- `INFO persistence` informa AOF habilitado.
- Un valor y su TTL sobreviven a un reinicio del contenedor.

## 7. Coherencia con el TPO

- Hitos 1–3: Redis atiende accesos por clave, sesiones breves y lecturas repetidas; no
  reemplaza las bases elegidas para datos persistentes.
- MongoDB: `cache:plantel:<equipo>` evita repetir la lectura del equipo y jugadores.
- Neo4j: `cache:partido:<id>` reduce presión sobre el cuello de botella identificado en
  el diseño y se invalida después de un gol.
- Cassandra: `cache:feed:<partido>:<bloque>` absorbe lecturas repetidas; la ventana
  actual usa 5 s y no se invalida por cada comentario.
- La persistencia AOF/RDB matiza la descripción inicial de Redis como “puramente en
  memoria”; el análisis está en `docs/memoria_y_escalabilidad.md` §5.
- Redis Cluster distribuye slots, no implementa literalmente el consistent hashing
  propuesto en Hito 3; la revisión está en `docs/memoria_y_escalabilidad.md` §4.
- Neo4j y Cassandra usan IDs distintos para los partidos de muestra. No se oculta esa
  inconsistencia: está registrada en `docs/modelo_clave_valor.md` §5.

## 8. Estructura

```text
fixture2030-redis/
├── docker-compose.yml
├── scripts/
│   ├── inicializacion.redis
│   ├── carga_muestra.redis
│   ├── sesiones.redis
│   ├── cache.redis
│   ├── metricas.redis
│   ├── concurrencia.sh
│   ├── ejecutar.sh
│   ├── generar_evidencia.sh
│   └── verificar_persistencia.sh
├── docs/
│   ├── patrones_de_acceso.md
│   ├── modelo_clave_valor.md
│   ├── ciclo_de_vida_e_invalidacion.md
│   ├── memoria_y_escalabilidad.md
│   └── evidencia/
└── README.md
```
