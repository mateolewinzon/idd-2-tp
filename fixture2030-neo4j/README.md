# Hito 5 — Módulo de Grafos de Torneo, Partidos y Eventos (Neo4j)

Plataforma del Fixture del Mundial 2030 — Ingeniería de Datos II.

Este directorio implementa el módulo de grafos en **Neo4j**, complementando el módulo documental en MongoDB (Hito 4) para modelar y resolver consultas complejas de conectividad, relaciones entre **Equipos**, **Jugadores**, **Partidos**, **Sedes** y **Eventos**.

Las decisiones de modelado del grafo, el inventario de entidades y sus relaciones se detallan en [`docs/modelo_grafo.md`](./docs/modelo_grafo.md).

---

## 1. Requisitos

- **Docker Desktop** (o instalación de Docker con Docker Compose v2).
- Nada más. No hace falta instalar Neo4j localmente ni drivers adicionales: todo se ejecuta dentro del contenedor.
- Los puertos **7474** (HTTP / Neo4j Browser) y **7687** (Bolt) deben estar libres. Si ya tenés una instancia local de Neo4j en ejecución, detenela o modificá el mapeo de puertos en `docker-compose.yaml`.

---

## 2. Puesta en marcha

Comandos principales desde este directorio:

```bash
./scripts/levantarDocker.sh  # Levanta el contenedor de Neo4j y espera a que esté listo
./scripts/estructura.sh      # Aplica constraints de unicidad e índices (queries/estructura.cypher)
```

### Acceso y visualización del grafo

- **Neo4j Browser (Web UI):** [http://localhost:7474](http://localhost:7474)
  - **Usuario:** `neo4j`
  - **Contraseña:** `password123`
  - **URL de conexión:** `bolt://localhost:7687`

- **Acceso interactivo por CLI (`cypher-shell`):**
  ```bash
  docker compose exec -it neo4j cypher-shell -u neo4j -p password123
  ```

---

## 3. Ciclo de vida del ambiente

Los volúmenes `neo4j_data` y `neo4j_logs` resguardan los datos fuera del ciclo de vida efímero del contenedor.

| Acción                              | Comando                  | ¿Se pierden los datos?        |
| ----------------------------------- | ------------------------ | ----------------------------- |
| Levantar                            | `./scripts/levantarDocker.sh` | —                        |
| Detener (conservando contenedor)    | `docker compose stop`    | **No**                        |
| Reiniciar                           | `docker compose restart` | **No**                        |
| Volver a arrancar tras detener      | `docker compose start`   | **No**                        |
| Eliminar el contenedor              | `docker compose down`    | **No** — el volumen persiste  |
| Eliminar contenedor **y volumen**   | `docker compose down -v` | **Sí, todo**                  |

---

## 4. Estructura del proyecto

```
.
├── docker-compose.yaml              Definición del servicio Neo4j con volúmenes persistentes y credenciales
├── README.md                        Este archivo
│
├── docs/
│   └── modelo_grafo.md              Problema relacional, inventario de nodos, propiedades y relaciones
│
├── queries/                         Scripts Cypher de definición y consulta
│   ├── estructura.cypher            Constraints de unicidad e índices para nodos
│   ├── carga.cypher                 Carga e importación de nodos y relaciones
│   ├── crud.cypher                  Operaciones CRUD sobre el grafo
│   └── consultas_grafo.cypher       Consultas analíticas de patrones y caminos
│
├── scripts/                         Scripts envoltorios ejecutables desde el host
│   ├── levantarDocker.sh            Levanta Neo4j y espera disponibilidad de cypher-shell
│   └── estructura.sh                Ejecuta queries/estructura.cypher contra Neo4j
│
├── import/                          Directorio mapeado al volumen /var/lib/neo4j/import para LOAD CSV
│
└── evidencia/                       Salidas de ejecución y resultados de las corridas
    └── estructura.txt               Log de ejecución de restricciones e índices
```

---

## 5. Modelo de Datos en Grafo

El modelo vincula entidades provenientes de la etapa documental previa con las entidades de competencia y desarrollo del torneo:

- **Nodos:**
  - `(:Equipo {id, nombre})`
  - `(:Jugador {id, apellido})`
  - `(:Partido {id, fase, fecha})`
  - `(:Sede {id, nombre, ciudad})`
  - `(:Evento {id, tipo, minuto})`

- **Relaciones principales:**
  - `(:Jugador)-[:PERTENECE_A]->(:Equipo)`
  - `(:Equipo)-[:PARTICIPA_EN {condicion}]->(:Partido)`
  - `(:Partido)-[:SE_DISPUTA_EN]->(:Sede)`
  - `(:Evento)-[:OCURRE_EN]->(:Partido)`
  - `(:Jugador)-[:PROTAGONIZA]->(:Evento)`

Para un detalle exhaustivo con justificaciones de cardinalidad y requerimientos funcionales, consultar [`docs/modelo_grafo.md`](./docs/modelo_grafo.md).
