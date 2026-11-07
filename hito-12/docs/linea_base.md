# Línea base

La línea base es el flujo ya existente: `GET /fixture` con Cache-Aside, TTL 5 s, índice `(fecha_hora, _id)` y proyección de campos. No se desactiva la caché ni se elimina el índice para fabricar una mejora. El decorador de adaptadores y el middleware HTTP ya registraban tiempos; se agregaron dos mensajes de acierto/miss en el servicio antes del piloto y se mantuvieron en ambas versiones.

## Registro reproducible

- `evidencia/source_manifest.json`: commit de origen, estado local y huellas por archivo.
- `evidencia/backend-source.tar.gz`: copia de fuente y datos que incluye las modificaciones locales necesarias.
- `evidencia/environment.json`: Python, paquetes, Java, arquitectura, RAM, Docker y huellas de imágenes.
- `evidencia/scenario.json`: parámetros del escenario principal.
- `evidencia/baseline/r*-u*/manifest.json`: versión de TTL, concurrencia, comando, configuración y huellas del arnés/JMX por corrida.
- `requests.jtl`, `api.log`, `resources.jsonl`: registros crudos de cada capa.
- `integrity_before.json` / `integrity_after.json`: conteos y huellas de fuente/respuesta.

El snapshot se usa porque el commit del backend por sí solo no incluye el seed ni todos los cambios existentes. La fecha de ejecución se conserva en UTC en los manifiestos; JMeter y logs de Python registran además la hora local de Argentina.

## Método de medición

| Capa | Método | Alcance y límite |
| --- | --- | --- |
| Consumidor | `elapsed` de JMeter, en ms; código HTTP y aserción SHA-256 del cuerpo. | Incluye el intercambio HTTP observado por JMeter. La aserción se ejecuta después; su CPU puede reducir la tasa del cliente. |
| API | Middleware con reloj monotónico y duración por request. | Tiempo hasta producir la respuesta en el middleware, no equivale exactamente al tiempo de recepción total en el cliente. |
| Adaptadores | Decorador `observe` con reloj monotónico. | Incluye driver, comunicación y obtención del resultado; no es tiempo interno puro del motor. |
| Caché | Logs explícitos `fixture_cache=hit/miss`. | Conteos por ventana temporal; no se atribuye un miss únicamente al costo del motor. |
| Motores | `docker stats` durante la corrida. | Recursos de cada contenedor, no recursos completos del host ni tiempos internos de consulta. |
| Generador/API | Árbol de procesos mediante `ps`, RSS y CPU media de proceso; JVM identificada entre descendientes. | `ps %CPU` es promedio del proceso. No se afirma CPU instantánea. |
| Host | `vm_stat` y promedio de carga de macOS. | Incluye actividad ajena al experimento. |

La latencia se reporta como mínimo, media, p50, p95, p99 y máximo por corrida. Los percentiles usan rango más cercano. Throughput = respuestas correctas en la ventana / segundos de ventana. Error = timeout, fallo HTTP o cuerpo distinto del esperado. Las cantidades y errores están disponibles por fase y tipo; el CSV permite revisar cada request.

El resumen de adaptadores selecciona sus logs por tiempo de finalización, mientras el resumen JMeter selecciona requests por inicio. Puede haber una diferencia de borde si una operación atraviesa la ventana; no se promete igualdad exacta de ambos conteos.

La línea base se ejecuta antes del cambio de configuración. El diagnóstico con `explain` y las pruebas de actualización se hacen fuera de la carga para no alterar la observación. La tabla completa de resultados y recursos se genera en `comparacion_antes_despues.md`.
