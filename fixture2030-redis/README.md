# Fixture 2030 — Módulo Redis (Hito 7)

Caché de usuarios y sesiones del Fixture 2030, sobre un único nodo Redis local.

> **Borrador (fase de documentación).** Los apartados marcados *pendiente* se completan
> junto con los scripts y la evidencia.

## Documentación

| Apartado | Dónde |
| ------------------- | ----- |
| Problema de concurrencia | [`docs/patrones_de_acceso.md`](docs/patrones_de_acceso.md) §1 |
| Patrones de acceso | [`docs/patrones_de_acceso.md`](docs/patrones_de_acceso.md) |
| Modelo clave/valor | [`docs/modelo_clave_valor.md`](docs/modelo_clave_valor.md) |
| Ciclo de vida | [`docs/ciclo_de_vida_e_invalidacion.md`](docs/ciclo_de_vida_e_invalidacion.md) §1 |
| Fuente de verdad y caché | [`docs/ciclo_de_vida_e_invalidacion.md`](docs/ciclo_de_vida_e_invalidacion.md) §2–4 |
| Concurrencia | *pendiente* — `scripts/concurrencia.redis` y `docs/evidencia/03_concurrencia.txt` |
| Memoria y escalabilidad | [`docs/memoria_y_escalabilidad.md`](docs/memoria_y_escalabilidad.md) |
| Datos cargados | *pendiente* (sección 4) |
| Operaciones Redis | *pendiente* (sección 5) |
| Pruebas y evidencia | *pendiente* (sección 6) |
| Coherencia con el TPO | *pendiente* (sección 7) |

## 1. Alcance

Redis **no es fuente de verdad**. Guarda estado temporal propio (sesiones, contador de
visitas) y copias descartables de la ficha de un partido (Neo4j), del feed de
comentarios (Cassandra) y del plantel de un equipo (MongoDB). Es un único nodo: no es
una topología de alta disponibilidad ni Redis Cluster.

## 2. Estructura

```
fixture2030-redis/
├── docker-compose.yml
├── scripts/
│   ├── inicializacion.redis
│   ├── carga_muestra.redis
│   ├── sesiones.redis
│   ├── cache.redis
│   ├── concurrencia.redis
│   └── metricas.redis
├── docs/
│   ├── patrones_de_acceso.md
│   ├── modelo_clave_valor.md
│   ├── ciclo_de_vida_e_invalidacion.md
│   ├── memoria_y_escalabilidad.md
│   └── evidencia/
└── README.md
```

## 3. Ejecución

*Pendiente:* levantar, verificar el servidor, abrir `redis-cli`, ejecutar los scripts en
orden, detener y reiniciar sin perder datos.

## 4. Datos cargados

*Pendiente:* origen, cantidad y distribución de usuarios, sesiones y claves de caché.

## 5. Operaciones Redis

*Pendiente:* propósito de los scripts de inicio, carga, sesiones, caché, concurrencia,
métricas y limpieza.

## 6. Pruebas y evidencia

*Pendiente:* resultados, métricas consultadas, limitaciones y enlaces a
`docs/evidencia/`.

## 7. Coherencia con el TPO

*Pendiente:* relación con Hitos 1 a 3 y con los módulos MongoDB, Neo4j y Cassandra.
Revisiones justificadas ya documentadas:

- Persistencia AOF/RDB frente a "puramente en memoria" de Hito 2 — `docs/memoria_y_escalabilidad.md` §5.
- Consistent hashing de Hito 3 frente a slots de Redis Cluster — `docs/memoria_y_escalabilidad.md` §4.
- IDs de partido distintos entre Neo4j y Cassandra — `docs/modelo_clave_valor.md` §5.
