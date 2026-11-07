# Flujo, datos y escenario de carga

## Operación y resultado correcto

Un espectador consulta el calendario previo al partido. Cada operación es un `GET /fixture`, sin parámetros, y espera los 127 partidos ordenados por fecha/hora UTC y código, con fase, equipos, estado y resultado. La API lee `fixture:v1:todos` en Redis; ante miss consulta `partidos` en MongoDB, construye la respuesta y la guarda con TTL. Una copia válida permite responder sin consultar MongoDB.

Las lecturas constituyen el 100% de la carga. No hay escrituras de negocio durante las ventanas medidas. La escritura de caché en un miss es parte interna del flujo, no un porcentaje adicional de operaciones del consumidor. Todas las solicitudes comparten una clave caliente; no se simula una distribución uniforme de claves distintas.

## Dataset y preparación

Se usa el generador y los archivos de `data/fixture` del backend conservado en el snapshot. Origen: CSV del equipo, calendario y escenario sintéticos de la demo; no es el calendario oficial. Hay 127 códigos `P-001` a `P-127`; P-001 está finalizado 2–1, P-002 en vivo 1–0 y los 125 restantes próximos. Los marcadores no avanzan durante la carga. Las plazas aún no resueltas conservan los valores nulos previstos por el contrato.

El cargador valida el lote, crea el validador de documentos e índice, y hace upsert por código. Cada corrida restablece explícitamente el escenario dentro de la base exclusiva `fixture2030_hito12`. Las huellas de los CSV, calendario, código y respuesta permiten identificar exactamente la entrada. La recarga repetida se valida por separado.

Los 127 partidos representan el volumen completo de este listado de la demo; el crecimiento estudiado es el acceso. No se inventan partidos adicionales del Mundial ni se presenta este dataset como representativo del volumen de tracking o comentarios. Tampoco se extrapola linealmente a usuarios mundiales.

## Configuración fijada antes de medir

| Parámetro | Valor |
| --- | --- |
| Generador | Apache JMeter 5.6.3 sin interfaz; Java 21. |
| Lectores concurrentes | 1, 10 y 30, en corridas independientes. |
| Repeticiones | Tres por nivel y por versión: 18 corridas principales. |
| Calentamiento | 10 s de consultas a la API, fuera de JMeter y del resumen principal. |
| Rampa | 10 s de incorporación de lectores en JMeter, excluida del resumen sostenido. |
| Sostenimiento | 60 s con concurrencia objetivo. |
| Pausa | 1000 ms por usuario antes de cada request, además de la espera de respuesta/procesamiento. |
| Timeout | Conexión y respuesta HTTP de 10 s cada una. No se suman como promesa de latencia máxima total. |
| Reintentos/redirecciones | Desactivados en el cliente HTTP de JMeter. |
| API | Un proceso Uvicorn en loopback:58000; misma instrumentación y código. |
| MongoDB | Loopback:57017, límite 1 CPU y 512 MiB. |
| Redis | Loopback:56379, límite 0,5 CPU y 128 MiB; maxmemory 64 MiB y sin persistencia. |
| Finalización | Scheduler de JMeter al completar rampa+sostenimiento; proceso terminado antes de validar la fuente. |

Se redujeron los tiempos inicialmente propuestos en el plan de diseño (30/30/120) a 10/10/60 **antes de la línea base definitiva**, para mantener acotada la duración del laboratorio y sostener las tres repeticiones y los tres perfiles. Cada ventana sostenida abarca aproximadamente 12 períodos de TTL 5 s o 4 de TTL 15 s. No es una elección exigida por la materia ni una garantía de estabilidad estadística. El piloto de 2/2/10 es una comprobación funcional, se conserva aparte y no participa de la comparación.

El generador implementa carga cerrada: el usuario espera respuesta antes de continuar. Por eso 30 usuarios no equivalen a 30 requests/s exactas, y el experimento no encuentra la capacidad máxima de la API. Una degradación de respuesta puede disminuir la tasa producida; se reporta la tasa lograda.

## Ventanas, seguridad de ejecución y limpieza

`origin.txt` registra el origen temporal de JMeter. El resumen selecciona muestras HTTP por inicio de request en `[origen+rampa, origen+rampa+sostenimiento)`. Las fases anteriores quedan en los logs/JTL y en el manifiesto, pero no se mezclan con la estadística principal. Las validaciones antes/después se ejecutan fuera de esa ventana.

El orquestador comprueba terminación de API, impone un plazo al generador y detiene la carga si más del 10% de las muestras de los últimos 30 s fallan, una vez transcurridos al menos 30 s. El usuario puede interrumpir con Ctrl+C si observa presión de memoria o pérdida de respuesta. Ese umbral es un mecanismo de interrupción del experimento, no un SLA. Los límites de contenedores, heap de JVM, concurrencia y tiempo evitan una carga abierta sin límites. No hay detección automática de toda forma de presión de memoria de macOS.

Cada intento queda en su propia carpeta. Un aborto no se presenta como una corrida completa. La limpieza opcional sólo elimina `partidos` de la base exclusiva y la clave fija en el Redis exclusivo. No afecta los contenedores ni datos de Hito 11 u otros proyectos.
