# Hipótesis y optimización

## Observación previa al cambio

En el piloto funcional y la primera corrida de línea base se observaron misses regulares y consultas MongoDB asociadas a la expiración de la caché. La primera ventana sostenida, con un lector, registró 12 llamadas `MongoDB.list_fixture` en 60 s; la API ya conservaba respuesta durante 5 s. Esta observación se registra antes de ejecutar la variante de 15 s.

**Posible limitación:** reconstruir periódicamente una respuesta compartida genera trabajo repetido de consulta y serialización. No se identifica MongoDB como motor saturado: la evidencia inicial no demuestra saturación ni agotamiento de conexiones. Se trata de una oportunidad de reducir trabajo por request.

## Hipótesis falsable y prueba

Para el listado previo al partido, permitir una copia de hasta 15 s debería reducir las reconstrucciones y consultas a MongoDB respecto de 5 s, manteniendo correcto el contenido de una instantánea estática. Se medirá además si cambian p95/p99, throughput, errores y recursos; la hipótesis no garantiza una mejora en todas esas métricas.

El cambio es exclusivamente `FIXTURE_CACHE_TTL_SECONDS=15` en la variante del laboratorio. La línea base usa 5. El backend ya acepta ese parámetro: no se modifica el contrato HTTP ni el valor por defecto de la aplicación. Los manifiestos de cada corrida documentan el valor efectivo. Misma fuente, dataset, workers, límites de CPU/memoria, instrumentación, generador, tiempos y perfiles.

Se ejecutan tres repeticiones para cada nivel de 1, 10 y 30 lectores. Comparar en primer término la cantidad de consultas MongoDB por ventana y por respuesta, y luego el resto de las métricas. Si aumenta el TTL pero no disminuyen las consultas, revisar invalidaciones, fallos de caché y distribución de misses antes de afirmar mejora.

## Costo y alcance aceptado en el experimento

La contraparte es la frescura: si cambia un resultado y falla/omite la invalidación, puede publicarse una copia vieja durante aproximadamente el TTL restante, más la demora de la próxima lectura. La variante adopta 15 s como decisión del laboratorio para el flujo previo al partido, con actualización explícita e invalidación. No se declara aceptable ese retraso para el marcador en vivo y no se cambia globalmente la configuración de la demo.

No aumenta la cantidad de claves ni el tamaño nominal del cuerpo cacheado; se mantiene durante más tiempo la misma respuesta. Sigue existiendo la complejidad de invalidar la caché al escribir y no hay transacción distribuida entre MongoDB y Redis. Los lectores simultáneos pueden reconstruir a la vez al vencer la clave; el cambio de TTL no elimina ese fenómeno.

La prueba independiente `validar_frescura.py` verifica ambos TTL con una actualización sin invalidar, otra con invalidación y un payload de caché inválido. Guarda el retraso realmente observado y restaura el escenario al terminar. Esa prueba no se mezcla con la carga de sólo lectura.

## Archivos y decisión

- Configuración comparada: `config/escenario.json` y los manifiestos por corrida.
- Implementación del cambio: variable de entorno aplicada al iniciar cada API por `scripts/experimento.py`.
- Instrumentación común: `app/services/fixture_service.py` en el backend/snapshot.
- Resultado y regresiones: tabla generada en `comparacion_antes_despues.md` y `evidencia/comparacion.csv`.

La decisión final se conserva en [conclusiones](conclusiones.md), después de las 18 corridas. Se registraron regresiones del p99 con 1 y 10 lectores, además de la reducción de consultas. La hipótesis previa está fechada en `evidencia/hipotesis_previa.json` antes de la primera variante optimizada. Una reducción de consultas con poca variación de latencia sólo permite afirmar ahorro de trabajo en este escenario. No justifica por sí sola cambiar el TTL del seguimiento en vivo.
