# Conclusiones del experimento

Se completaron 18 corridas principales, con 14.468 respuestas HTTP correctas dentro de las ventanas sostenidas y 0 errores medidos. Los 127 partidos conservaron contenido, códigos únicos y orden antes/después de cada corrida.

El cambio de TTL de 5 a 15 s redujo las consultas MongoDB de 195 a 57 en el conjunto de ventanas sostenidas (70.8% menos). Esto respalda la hipótesis de menor trabajo repetido para este listado compartido; no demuestra saturación previa ni capacidad máxima posterior.

## Latencia por perfil

- 1 lectores: p95 medio de corridas 30.00 → 27.67 ms; rango base 26–35 ms y variante 22–33 ms. p99 medio 49.67 → 67.33 ms. Throughput medio 0.983 → 0.983 respuestas correctas/s.
- 10 lectores: p95 medio de corridas 26.00 → 22.67 ms; rango base 23–28 ms y variante 17–28 ms. p99 medio 63.00 → 69.67 ms. Throughput medio 9.761 → 9.722 respuestas correctas/s.
- 30 lectores: p95 medio de corridas 30.33 → 23.33 ms; rango base 26–33 ms y variante 21–25 ms. p99 medio 51.67 → 46.67 ms. Throughput medio 29.467 → 29.461 respuestas correctas/s.

Se observó una regresión del p99 medio con 1, 10 lectores. La variante no mejora uniformemente la latencia; se conserva esa regresión aunque disminuyan el p95 y las consultas.

La tasa está limitada deliberadamente por la pausa de un segundo. La variación entre corridas y el host compartido impiden atribuir cada diferencia de latencia exclusivamente al TTL. La tabla completa conserva p99, errores, recursos y resultados individuales; no se selecciona sólo la mejor corrida. El consumo de memoria de MongoDB creció a lo largo de las corridas y no se reinició el motor entre variantes; no se atribuye ese crecimiento al TTL ni se afirma ahorro general de memoria.

## Costo de frescura comprobado

- TTL 5 s: cambio sin invalidar visible después de 5.061 s; con invalidación, primera lectura correcta después de 13.03 ms. Caché inválida reconstruida correctamente.
- TTL 15 s: cambio sin invalidar visible después de 15.070 s; con invalidación, primera lectura correcta después de 15.09 ms. Caché inválida reconstruida correctamente.

Son retrasos observados en actualizaciones controladas, con sondeo cada 200 ms; no máximos garantizados ni latencias de producción.

## Decisión y alcance

Conservar la variante de 15 s como configuración explícita del experimento para consultas previas al partido cuando se acepta esa antigüedad. Mantener 5 s como valor por defecto del backend: el marcador en vivo no adopta automáticamente la tolerancia de este caso. Las escrituras deben invalidar la caché; el TTL limita el tiempo de una copia vieja si eso falla. El cambio no elimina reconstrucciones concurrentes al vencer una clave.

La integridad se verificó con comparación contra MongoDB y huellas de cada respuesta. El control negativo confirma que HTTP 200 con contenido incorrecto falla la validación. La propuesta de Data Mart tiene un prototipo validado de dos filas para el único partido finalizado de la demo y pruebas de corrección/reintento; no es una plataforma BI ni una integración de seis motores. La alternativa SQL es conceptual, sin cifras experimentales inventadas.

El resultado se limita a esta notebook, dataset de 127 partidos y carga cerrada de hasta 30 lectores. No se midieron ingesta masiva, replicación, regiones, saturación máxima ni rendimiento SQL. Prometheus y Grafana quedan para el Hito 13, según la clase de monitoreo.
