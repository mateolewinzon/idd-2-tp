# Integridad, limitaciones y trazabilidad

## Qué se comprueba

Cada corrida carga el lote validado y comprueba 127 códigos únicos. La respuesta inicial se compara estructuralmente contra una respuesta construida desde los documentos MongoDB, respetando el contrato Pydantic. Sólo después se obtiene el SHA-256 del cuerpo HTTP de referencia. JMeter calcula el SHA-256 de **cada** respuesta y falla la muestra si no hay HTTP 200 o el cuerpo difiere. Esto incluye orden, códigos, estados y resultados: no se considera éxito por status solamente.

Al terminar, se vuelve a comparar API contra MongoDB y se exige igualdad de las huellas de fuente y respuesta con el estado anterior. La fuente canónica comprende los campos relevantes del listado, incluyendo resultado/fecha; excluye `actualizado_en`, que el cargador cambia legítimamente al restablecer la instantánea. La carga principal es de lectura: no se inventan cantidades de inserciones aceptadas durante ella. Los conteos de preparación se conservan por separado.

Un control negativo independiente (`verificar_generador.py`) devuelve HTTP 200 con un cuerpo deliberadamente incorrecto en el puerto 58001 y exige que JMeter lo rechace. Sus fallos son esperados y se conservan fuera de las 18 corridas principales; no son errores de la API medida.

El JTL conserva las muestras HTTP registradas por el generador, incluyendo fallos de contenido, estado o transporte. Al completar cada corrida se cuentan éxitos y errores; las solicitudes ya terminadas fuera de la ventana también quedan registradas. La finalización del proceso se espera antes de validar; un aborto no tiene resumen válido. No se utiliza el contador de muestras como prueba de capacidad del generador ni se confunde con registros insertados en MongoDB.

`diagnostico.json` conserva la recarga repetida sin nuevas inserciones y el plan real de la consulta. `frescura-ttl5.json` y `frescura-ttl15.json` comprueban actualización sin invalidación, actualización con invalidación y reconstrucción ante payload inválido. Las actualizaciones son sólo del laboratorio y se restauran. Las pruebas de Data Mart comprueban claves, goles, correcciones y fallas de publicación por separado.

## Límites del experimento

- Sólo se estudia el listado de 127 partidos, con una clave compartida y datos estáticos durante las ventanas medidas. No hay volumen de telemetría, escritura simultánea de resultados ni comportamiento completo del torneo.
- Se prueba una única notebook y un nodo por motor. No se simulan replicación, particiones de red, regiones ni fallos de nodo.
- El recolector de recursos y el orquestador también consumen recursos; se mantienen iguales en ambas variantes y no se descuentan de las mediciones.
- El generador y la API comparten host; Docker comparte una VM y recursos con servicios existentes. Se registran recursos, pero no se atribuye todo el consumo del host al hito.
- La CPU de JMeter puede incluir arranque/JIT y validación; la pausa de 1 s limita deliberadamente la carga. El throughput logrado no identifica saturación de la API. No se midió la capacidad máxima del generador mediante un benchmark independiente.
- Hay tres repeticiones y muestras limitadas, particularmente con un lector. p99 es sensible a pocas operaciones lentas. No se calculan intervalos de confianza ni significancia estadística.
- Primero se mide toda la línea base y después toda la variante; no hay orden aleatorio. Cambios de carga del host/cachés internas pueden afectar latencias. Ambas variantes conservan el mismo calentamiento y límites.
- La copia Redis ya existía y el índice ya estaba creado por el seed. La mejora estudiada es únicamente el TTL. No se presenta una optimización previa como nueva.
- Aumentar TTL reduce oportunidades de reconstrucción; no elimina las reconstrucciones concurrentes al expirar ni garantiza una lectura reciente en caso de falla de invalidación.
- `docker stats` informa recursos del contenedor; logs del adaptador incluyen driver/red. No se dispone de trazas internas completas de MongoDB/Redis ni se calcula costo exacto de CPU por request.
- El prototipo analítico publica un archivo local atómicamente, no una transacción distribuida ni una captura transaccional de la fuente mientras cambia. Su programación cada 5 minutos es propuesta, no implementada.
- La comparación relacional es conceptual y no tiene resultados SQL. No demuestra superioridad universal de NoSQL o relacional.
- El piloto conserva el primer esquema de recursos, que medía el proceso lanzador de JMeter. Se corrigió para incluir la JVM antes de la línea base; el piloto no interviene en las tablas comparativas.

## Evidencia, aislamiento y secretos

El manifiesto de fuente usa una lista explícita de archivos. No incluye `.env`, `.git`, directorios de dependencias ni dumps de otras bases. Los logs de adaptadores no imprimen consultas, parámetros ni errores detallados de drivers. Los contenedores se publican sólo en loopback y tienen nombres, puertos y datos distintos de Hito 11. No se borra ningún volumen existente.

La entrega conserva manifiestos, JTL, logs, recursos y verificaciones en lugar de capturas aisladas. Los valores del informe se generan con `comparar_resultados.py`; una nueva reproducción no debe sobrescribir silenciosamente la evidencia original.

## Cobertura de requisitos

| Requisitos | Implementación/evidencia |
| --- | --- |
| RF1–RF3 | Escenario, dataset, generador y manifiestos de preparación. |
| RF4–RF6 | Snapshot, entorno, JTL, logs API/adaptadores, recursos por contenedor/proceso. |
| RF7–RF8 | Hipótesis registrada antes de la variante y cambio TTL aplicado por configuración. |
| RF9–RF11 | 18 corridas, tabla/CSV por repetición, recursos, frescura y costos. |
| RF12–RF13 | Diseño del Data Mart, procedencia, prototipo y pruebas de fallos/correcciones. |
| RF14 | Comparación relacional del mismo listado y proyección, explícitamente conceptual. |
| RF15–RF16 | Conteos, unicidad, comparación de contenido, huellas antes/después y registros crudos. |
| RNF1–RNF5 | README reproducible, versiones/huellas, escenario común, integridad y unidades. |
| RNF6–RNF9 | Límites de extrapolación, laboratorio, exclusión de secretos y control de recursos. |
| RNF10–RNF14 | Organización, limpieza acotada, procedencia analítica, historial Git y separación entre mediciones/propuestas. |
