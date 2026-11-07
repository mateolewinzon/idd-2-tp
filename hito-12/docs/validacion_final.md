# Validación final

| Comprobación | Resultado | Evidencia |
| --- | --- | --- |
| Backend, tests unitarios | 123 aprobados, más 5 subtests | `evidencia/tests_backend_unit.txt` y `.xml`. |
| Fixture, integración con MongoDB/Redis reales | 6 aprobados | `evidencia/tests_backend_integration.txt` y `.xml`. |
| Data Mart, correcciones/reintentos/fallas/penales | 6 aprobados | `evidencia/tests_data_mart.txt`. |
| Contenido incorrecto aunque HTTP 200 | 43 respuestas deliberadamente incorrectas rechazadas | `evidencia/generador_negativo/validation.json` y JTL. |
| Corridas principales | 18 completas, 14.468 respuestas medidas, 0 errores | `evidencia/comparacion.json` y archivos de cada corrida. |
| Integridad de datos | 127 códigos únicos, sin cambio de fuente/respuesta en cada corrida | `integrity_before.json` / `integrity_after.json`. |
| Recarga | 0 nuevos insertados; fuente sin cambios relevantes | `evidencia/diagnostico.json`. |
| Frescura y caché inválida | Ambos TTL comprobados; reconstrucción correcta | `evidencia/frescura-ttl5.json` y `frescura-ttl15.json`. |
| Fuente archivada | Huellas del tar y archivos verificadas | `evidencia/verificacion_entrega.json`. |
| Reproducción de seed desde extracción nueva | 127 validados, 0 rechazados | `evidencia/reproduccion_snapshot.json`. |

El conjunto suma 135 tests aprobados, además de los subtests y los controles experimentales. Pytest informa una advertencia de deprecación de Starlette/httpx; no hubo fallos y no se modificaron dependencias fuera del alcance del hito.

La auditoría comprueba configuraciones, código del orquestador y JMX iguales en ambas variantes, el registro de hipótesis anterior a la optimización y la correspondencia de conteos entre JTL, resúmenes e informe. Los controles negativos y el piloto se conservan separados de los resultados principales.
