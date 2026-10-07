# Módulo de Series Temporales (InfluxDB) — Hito 8

## Plataforma del Fixture del Mundial 2030 — Ingeniería de Datos II

Repositorio del grupo: [mateolewinzon/idd-2-tp](https://github.com/mateolewinzon/idd-2-tp)

---

## 1. Descripción del Módulo

Este módulo implementa el subsistema de almacenamiento y consulta analítica de **series temporales de estadísticas en vivo y telemetría de alta frecuencia** para los 127 partidos del Mundial 2030, utilizando **InfluxDB 3 Core**.

El alcance del módulo abarca:
- Seguimiento cinemático segundo a segundo de 22 jugadores titulares por partido (`tracking_jugador`).
- Trayectoria tridimensional y velocidad instantánea del balón oficial (`tracking_pelota`).
- Métricas tácticas de posesión, remates y pases cada 5 segundos (`estadisticas_partido`).
- Monitoreo de concurrencia y streaming de usuarios por confederación (`actividad_usuarios`).

---

## 2. Coherencia con el Ecosistema del TPO

InfluxDB **no es fuente de verdad** de entidades maestras ni de relaciones:
- **MongoDB (Hito 4):** Catálogo documental maestro de selecciones y jugadores.
- **Neo4j (Hito 5):** Estructura del torneo, fixture de partidos, sedes y red de relaciones.
- **Cassandra (Hito 6):** Feed de comentarios masivos en vivo de alta tasa de escritura.
- **Redis (Hito 7):** Gestión de sesiones de usuario y caché de lectura.
- **InfluxDB (Hito 8):** Persistencia exclusiva de observaciones numéricas temporales de alta frecuencia.

*Nota de alcance:* Cada base opera de forma autónoma. La integración o sincronización técnica entre motores queda fuera del alcance de este trabajo práctico.

---

## 3. Seguridad Local y Persistencia

- **Persistencia en disco:** Configurada mediante un volumen montado en el host en `${HOME}/docker/data/influxdb`, preservando la base de datos entre reinicios del contenedor Docker.
- **Gestión de tokens:** El token de autenticación de InfluxDB 3 se genera durante la inicialización y se almacena en el archivo local `.influxdb3-token`, excluido explícitamente del control de versiones mediante `.gitignore`.
- **Exclusión de archivos pesados:** Los archivos generados de Line Protocol (`.lp`) y logs de carga no se versionan en Git.

---

## 4. Guía de Ejecución

Ejecutar desde la raíz del repositorio `idd-2-tp`. Se requiere Docker Compose, Python 3 y los CSV de `fixture2030-neo4j/import/`. Los scripts resuelven sus rutas a partir de su ubicación.

El pipeline de ejecución se compone de los siguientes pasos secuenciales:

1. **Inicialización del entorno:**
   ```bash
   bash scripts/inicializacion.sh
   ```
   Levanta el contenedor Docker, verifica la versión del motor, genera el token local y crea las dos bases de datos (`fixture2030_en_vivo` con retención de 7 días y `fixture2030_resumen` sin expiración).

2. **Generación de puntos sintéticos:**
   ```bash
   python3 scripts/generacion_puntos.py
   ```
   Lee los CSV maestros de `fixture2030-neo4j/import/` y genera archivos Line Protocol deterministas con semilla fija. La estimación base es 16.870.680 puntos; las validaciones también contemplan el punto tardío de prueba.

3. **Carga por lotes:**
   ```bash
   bash scripts/carga_lotes.sh
   ```
   Ejecuta una prueba de humo con 1 partido y posteriormente realiza la carga masiva en lotes de 10.000 líneas.

4. **Validación de integridad:**
   ```bash
   bash scripts/validacion.sh
   ```
   Comprueba conteos por tabla, series temporales, rangos de fechas y detecta posibles inconsistencias.

5. **Consultas temporales analíticas:**
   ```bash
   bash scripts/consultas_temporales.sh
   ```
   Ejecuta las consultas por rango temporal acotado, filtros por sede, equipo, jugador y evalúa casos de borde (dato tardío y partido sin puntos).

6. **Agregaciones y Downsampling:**
   ```bash
   bash scripts/agregaciones.sh
   ```
   Aplica agregados por minuto y vuelca el resumen consolidado a `fixture2030_resumen`.

7. **Validación final:**
   ```bash
   bash scripts/validacion.sh
   ```
   Volver a validar al final comprueba los datos consolidados y el estado de ambas bases.

8. **Prueba de persistencia (ya realizada y registrada):**
   ```bash
   docker compose -f fixture2030-influxdb/docker-compose.yml stop
   docker compose -f fixture2030-influxdb/docker-compose.yml up -d
   sleep 15
   bash scripts/validacion.sh
   ```
   La evidencia está en `docs/evidencia/05_retencion_y_persistencia.txt`. El volumen persistente vive en `${HOME}/docker/data/influxdb`; eliminarlo borra las bases locales.

---

## 5. Pruebas y Evidencia (Fase 4)

Las salidas de la corrida del 7 de octubre de 2026 están versionadas en [`docs/evidencia/`](./docs/evidencia/):

| Evidencia | Contenido |
| --- | --- |
| [00_ambiente.txt](./docs/evidencia/00_ambiente.txt) | Host, Docker, versión de InfluxDB, configuración de bases y recursos disponibles. |
| [01_generacion_y_carga.txt](./docs/evidencia/01_generacion_y_carga.txt) | Puntos generados, carga por lotes, tiempos y límites del laboratorio. |
| [02_validacion.txt](./docs/evidencia/02_validacion.txt) | Conteos, cardinalidad, cobertura y plausibilidad física. |
| [03_consultas.txt](./docs/evidencia/03_consultas.txt) | Consultas temporales y casos de borde. |
| [04_agregaciones.txt](./docs/evidencia/04_agregaciones.txt) | Agregaciones semánticas y downsampling. |
| [05_retencion_y_persistencia.txt](./docs/evidencia/05_retencion_y_persistencia.txt) | Retención observada, reinicio, conteos persistidos y advertencias registradas. |

Los resultados representan una corrida concreta; los tiempos y el uso de disco dependen del entorno. La evidencia de retención acredita solo el comportamiento observado con timestamps futuros.

## 6. Trazabilidad y cierre (Fase 5)

La matriz requisito por requisito, su respaldo y el estado (medido, documentado o proyectado) están en [`docs/trazabilidad_rf_rnf.md`](./docs/trazabilidad_rf_rnf.md).

## 7. Revisión de seguridad y entrega

- El token local `.influxdb3-token`, los datos generados y los logs están excluidos por [`.gitignore`](./.gitignore). No incluir ni copiar tokens en evidencias.
- El puerto del servicio se publica solo en `127.0.0.1`; la configuración está en [`docker-compose.yml`](./docker-compose.yml).
- Antes de entregar, revisar `git status --short` y confirmar que no aparezcan `.influxdb3-token`, `.DS_Store`, `data/`, archivos `.lp` o logs. Revisar también las evidencias en busca de credenciales.
- Los datos pesados generados no se versionan; se regeneran siguiendo la sección 4.

Commit sugerido: `docs(influxdb): completa trazabilidad y guía de entrega`.
