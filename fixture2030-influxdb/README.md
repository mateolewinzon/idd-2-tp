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
   Lee los CSV maestros de `fixture2030-neo4j/import/` y genera 16,6M+ puntos en archivos Line Protocol deterministas con semilla fija.

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

---

## 5. Pruebas y Evidencia (Fase 4)

Los resultados empíricos y salidas crudas de las pruebas de laboratorio se registrarán en `docs/evidencia/`:
- `00_ambiente.txt`: Estado del contenedor, versión del motor, configuración de bases y recursos del equipo.
- `01_generacion_y_carga.txt`: Conteo de puntos generados, tiempos medidos de ingesta y límites del laboratorio.
- `02_validacion.txt`: Auditoría de series y puntos efectivos por tabla.
- `03_consultas.txt`: Ejecución y resultados interpretados de las consultas temporales.
- `04_agregaciones.txt`: Evidencia de downsampling y métricas consolidadas.
- `05_retencion_y_persistencia.txt`: Comprobación de retención y persistencia tras detención y reinicio del contenedor.
