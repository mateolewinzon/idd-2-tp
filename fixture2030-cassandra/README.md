# Hito 6 — Módulo de Comentarios Masivos (Apache Cassandra)

Plataforma del Fixture del Mundial 2030 — Ingeniería de Datos II.

Este directorio implementa el subsistema de ingestión, visualización y análisis de **comentarios en tiempo real**, moderación y auditoría de interacciones durante el Mundial 2030, utilizando **Apache Cassandra**. Complementa los subsistemas documental en MongoDB (Hito 4) y de grafos en Neo4j (Hito 5), conforme a la arquitectura políglota y los lineamientos de distribución definidos en los Hitos 1, 2 y 3.

Las decisiones de modelado, patrones de consulta, estrategia de particionamiento definitivo y pruebas de rendimiento se detallan exhaustivamente en la carpeta [`docs/`](./docs/):
- [`docs/patrones_de_acceso.md`](./docs/patrones_de_acceso.md): Justificación previa por patrones de consulta, concurrencia masiva y catálogo de preguntas de negocio.
- [`docs/modelo_tabular.md`](./docs/modelo_tabular.md): Especificación tabular final, patrón CQRS con segregación caliente/histórica (`comentarios_feed` y `comentarios_historico`), TTL de 14 días con TWCS y tipos de datos.
- [`docs/decisiones_de_particionamiento.md`](./docs/decisiones_de_particionamiento.md): Justificación analítica del particionamiento definitivo por `((partido_id, bloque_temporal))` fijado en 5 minutos, evaluación matemática de los 166.000 registros en la final como compromiso asumido, y niveles de consistencia por operación.
- [`docs/rendimiento.md`](./docs/rendimiento.md): Protocolo de prueba de carga masiva (objetivo: 10.000 ops/seg), origen y sesgo de los datos sintéticos, y plantilla de evidencia empírica.

---

## 1. Requisitos de Ejecución

- **Docker Desktop** (o Docker Engine con plugin Docker Compose v2).
- Sistema operativo macOS, Linux o Windows con soporte para contenedores Linux.
- Puerto **9042** (puerto de transporte nativo CQL) libre en la máquina host.
- Asignación de recursos recomendada para Docker: mínimo 4 GB de memoria RAM y 2 CPUs virtuales dedicadas (Cassandra ejecuta sobre la JVM y requiere espacio para heap y page cache).
- `docker-compose.yml` utiliza la imagen oficial `cassandra:latest`. Dado el uso del tag dinámico, es requisito registrar la versión exacta y la fecha de ejecución al momento de realizar la prueba (vía `SHOW VERSION` o `nodetool version`).

---

## 2. Puesta en Marcha

Para iniciar el ambiente y validar su funcionamiento, se utilizan los scripts envoltorios ubicados en `./scripts/` (o los comandos directos de Compose):

```bash
# 1. Levantar el servicio de Cassandra y aguardar a que el nodo esté operativo
./scripts/levantarDocker.sh

# 2. Crear el keyspace y las tablas del modelo tabular optimizado (esquema definitivo CQRS)
./scripts/estructura.sh

# 3. Poblar la base con el set de datos sintéticos representativo
./scripts/cargar.sh

# 4. Ejecutar las consultas de validación de los patrones de acceso (sin ALLOW FILTERING)
./scripts/consultar.sh

# 5. Ejecutar la prueba de estrés de escritura masiva
./scripts/rendimiento.sh

# 6. Dejar materializados y verificar exactamente 1.000.000 de comentarios únicos
./scripts/carga_millon.sh
```

### Verificación del estado del nodo

Cassandra puede demorar entre 30 y 60 segundos en inicializar la JVM y unirse al anillo local. Para verificar que el nodo se encuentre en estado **UN** (*Up/Normal*):

```bash
docker compose exec cassandra nodetool status
```

Salida esperada (nodo único local):
```text
Datacenter: datacenter1
=======================
Status=Up/Down
|/ State=Normal/Leaving/Joining/Moving
--  Address     Load       Tokens  Owns (effective)  Host ID                               Rack
UN  127.0.0.1   104.2 KiB  16      100.0%            a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d  rack1
```

### Acceso interactivo por CLI (`cqlsh`)

Para conectarse a la consola interactiva de CQL dentro del contenedor:

```bash
docker compose exec -it cassandra cqlsh -u cassandra -p cassandra
```

> **Aviso de seguridad y entorno local:** Las credenciales `cassandra / cassandra` corresponden al superusuario predeterminado de desarrollo provisto por la imagen oficial. Son exclusivas para el entorno de laboratorio local y no deben trasladarse a entornos productivos (RNF8).

Una vez dentro de `cqlsh`, verificar la versión exacta del motor:
```sql
SHOW VERSION;
```

---

## 3. Topología de Laboratorio vs. Topología Multirregional de Producción

Es mandatario distinguir conceptualmente el entorno de ejecución de este hito de la arquitectura de destino proyectada en los Hitos 1 a 3:

1. **Entorno de Laboratorio (Entregable Hito 6):**
   - Ejecuta sobre un **nodo único local** orquestado con Docker Compose.
   - Utiliza una estrategia de replicación `SimpleStrategy` con factor de replicación `replication_factor = 1`.
   - **No provee tolerancia a fallas ni alta disponibilidad.** Su propósito es puramente funcional y demostrativo: validar el modelo tabular, la distribución de tokens, la corrección de las consultas CQL sin `ALLOW FILTERING` y el comportamiento del motor bajo concurrencia local.

2. **Topología de Producción (Arquitectura Fixture 2030):**
   - Cluster multirregional distribuido geográficamente en los tres continentes anfitriones (Europa, África y Sudamérica).
   - Utiliza `NetworkTopologyStrategy` con réplicas declaradas por datacenter (ej. `datacenter_europa: 3`, `datacenter_sudamerica: 3`, `datacenter_africa: 3`).
   - Permite lecturas y escrituras con latencia ultra baja conectando al centro de datos más próximo vía `LOCAL_ONE`, garantizando alta disponibilidad con nivel de consistencia ajustable ante particiones de red (teorema CAP: AP).

---

## 4. Persistencia y Ciclo de Vida del Contenedor

La persistencia de los datos está ligada al directorio montado en la máquina host `~/docker/data/cassandra`, según la convención establecida para la materia:

| Acción | Comando | ¿Se pierden los datos persistidos? |
| :--- | :--- | :--- |
| **Detener contenedor** | `docker compose stop` | **No** (se conservan en el volumen del host). |
| **Reiniciar servicio** | `docker compose restart` | **No**. |
| **Destruir contenedor** | `docker compose down` | **No** (el directorio `~/docker/data/cassandra` persiste). |
| **Borrado total explícito** | `docker compose down -v` + limpieza manual del host | **Sí** (requiere volver a ejecutar `estructura.sh` y `cargar.sh`). |

---

## 5. Estructura de Entregables y Carpeta `evidencia/`

Siguiendo la convención adoptada en los módulos precedentes (`fixture2030-mongo` y `fixture2030-neo4j`), este módulo cuenta con una carpeta obligatoria de auditoría:

```
fixture2030-cassandra/
├── docker-compose.yml              Definición del contenedor, puertos y volumen ~/docker/data/cassandra
├── README.md                        Este documento de arquitectura y puesta en marcha
├── docs/                            Documentación técnica analítica y decisiones consolidadas
│   ├── patrones_de_acceso.md        Análisis de concurrencia y consultas de negocio prioritarias
│   ├── modelo_tabular.md            Definición tabular, tipos de datos, CQRS, TTL de 14d y claves primarias
│   ├── decisiones_de_particionamiento.md Justificación del particionamiento temporal (5 min), matemática y consistencia
│   └── rendimiento.md               Protocolo y reporte de la prueba de carga de 10.000 escrituras/seg
├── scripts/                         Scripts envoltorios de automatización
│   ├── levantarDocker.sh            Inicialización y comprobación de disponibilidad del nodo
│   ├── estructura.sh                Aplicación del DDL (keyspace, tablas CQRS e índices)
│   ├── cargar.sh                    Poblado de datos sintéticos sesgados
│   ├── consultar.sh                 Ejecución de validación de patrones de acceso
│   ├── generar_millon.py            Generador determinista de timeuuid y comentarios únicos
│   ├── carga_millon.sh              Importación y verificación del millón físico exacto
│   ├── stress-comentarios.yaml      Perfil de cassandra-stress para comentarios_feed
│   └── rendimiento.sh               Benchmark de 1.000.000 de operaciones y registro de telemetría
└── evidencia/                       Registros de ejecución obligatorios para evaluación
    ├── nodetool_status.txt          Captura de salida del estado del anillo y nodo activo
    ├── cql_version.txt              Salida de SHOW VERSION (fecha y versión de imagen latest)
    ├── estructura.txt               Salida de la creación del keyspace y esquemas tabulares
    ├── consultas.txt                Logs con resultados de las queries representativas
    ├── ambiente.txt                 Recursos reales del host, Docker y JVM
    ├── prueba_carga.txt             Salida íntegra del millón de operaciones
    ├── resumen_prueba.txt           Throughput, latencias, total y errores
    ├── tablestats.txt               Estado físico de comentarios_feed luego del flush
    ├── conteo_final.txt             Evidencia del timeout de COUNT(*) global y su diagnóstico
    ├── carga_millon.txt             Importación exacta: filas, tasa y omisiones
    ├── verificacion_millon.txt      Reexportación paginada y conteo físico exacto
    └── tablestats_carga_millon.txt  Estado final de la tabla con el millón materializado
```

### Contenido obligatorio esperado en `evidencia/` por el evaluador:
- **`nodetool_status.txt`**: Comprueba que el nodo levantó correctamente, el rack/datacenter asignado y la carga de datos administrada.
- **`cql_version.txt`**: Documenta la fecha exacta del test y las versiones de `cqlsh`, Apache Cassandra y del protocolo de transporte binario.
- **`estructura.txt`**: Evidencia de la ejecución sin errores de las sentencias DDL.
- **`consultas.txt`**: Registro de respuestas a los patrones de acceso definidos, demostrando que ninguna consulta requirió `ALLOW FILTERING`.
- **`prueba_carga.txt`**: Log consolidado del benchmark local donde se reportan las escrituras por segundo alcanzadas, latencias percentilares y limitaciones observadas del entorno host.
- **`carga_millon.txt` y `verificacion_millon.txt`**: Demuestran que se importaron, sin omitir, y se volvieron a contar exactamente 1.000.000 de comentarios físicos diferentes.
