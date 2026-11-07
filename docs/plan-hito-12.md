# Plan de implementación del Hito 12

Estado: plan de diseño original. La implementación y la evidencia de ejecución se conservan en [hito-12](../hito-12/README.md); allí se documentan los parámetros finalmente fijados y los resultados medidos.

## 1. Consigna y relación con las clases

La fuente de requisitos es el PDF **Hito 12 — Requisitos Técnicos: Pruebas de Carga y Optimización del Fixture 2030**, especialmente sus secciones 5 a 10. Los ejemplos de las clases sirven como apoyo; no agregan obligaciones al hito.

| Material | Relación con este trabajo | Uso propuesto |
| --- | --- | --- |
| `Clase 13 (1).html`: Evaluación de la conectividad a los distintos productos | Directa: latencia, percentiles, throughput, errores, recursos, benchmarking, caché, índices y conexiones. | Tomar la metodología de medición y las familias de optimizaciones. Apache JMeter aparece como herramienta general de carga. |
| Clase 14: Monitoreo con Prometheus y Grafana | Complementaria: separación de métricas, recolección y visualización. Su sección final corresponde expresamente al Hito 13. | Reutilizar conceptos para interpretar las mediciones. Preparar datos que luego puedan servir para monitoreo. |

La clase 13 adjunta trata conectividad, aunque el PDF del hito también exige analizar grandes volúmenes, Data Mart y alternativa relacional. Las dos clases adjuntas no desarrollan suficientemente estos últimos temas: el plan se limita a lo que pide explícitamente la consigna. No se atribuyen a esas clases contenidos que no aparecen allí.

Los valores “típicos”, objetivos y resultados ilustrativos de las clases no son mediciones de este proyecto ni metas obligatorias. Tampoco se copian literalmente sus ejemplos de JavaScript al backend Python.

Para completar el Hito 12 no hace falta construir un Data Warehouse, instalar una base SQL para medirla, incorporar un frontend, conectar seis fuentes por request, ni implementar Prometheus y Grafana. La comparación relacional puede ser conceptual si se identifica como tal. El entregable solicitado es el repositorio con scripts, documentación y evidencia; no una presentación o video.

## 2. Flujo elegido y punto de partida comprobado

**Flujo propuesto: espectadores consultando el fixture antes de los partidos, mediante `GET /fixture`.**

En el backend vecino `idd-2-backend` ya existen:

- Ruta en `app/routes/fixture.py` y servicio en `app/services/fixture_service.py`.
- Lectura de `partidos` en MongoDB, proyección de campos y orden por `fecha_hora` y `_id`.
- Caché Redis de la respuesta completa: clave `fixture:v1:todos`, TTL predeterminado de 5 segundos y reconstrucción desde MongoDB ante ausencia o fallo de caché.
- Seed reproducible de 127 partidos, validación, recarga e invalidación mediante `scripts/cargar_fixture.py`.
- Creación del índice `idx_partidos_fecha_codigo` en ese cargador.
- Logs de duración por request y por operación de adaptador, vinculados por `X-Request-Id`.
- Laboratorio MongoDB/Redis y documentación de preparación en `docs/fixture.md`.

Por eso, ni agregar “una caché” ni crear ese índice pueden presentarse como optimizaciones nuevas sin comprobar primero el estado real de la línea base. No se quitarán mejoras existentes para fabricar una comparación favorable.

Este flujo integra API, Redis y MongoDB, sin depender del resto de los motores para responder. `/ready` sigue evaluando las seis fuentes; no se usará su resultado como único criterio para habilitar esta prueba. Se verificará la conectividad de MongoDB/Redis y la respuesta del endpoint seleccionado.

La prueba principal será de lecturas: 100% `GET /fixture`, sin escrituras durante la ventana medida. Las comprobaciones de actualización e invalidación se harán aparte. Esto estudia frecuencia y concurrencia sobre un volumen pequeño; no demuestra ingesta masiva ni capacidad sobre grandes históricos.

## 3. Etapa 1: preparar un laboratorio reproducible

1. Crear `hito-12/` en el repositorio de la materia, con configuración, scripts y documentación. Documentar también cómo localizar y preparar el backend vecino.
2. Reutilizar las instrucciones y contenedores de MongoDB/Redis del laboratorio, con base y Redis dedicados a esta prueba. La clave de caché es fija: separar solamente la base MongoDB no alcanza para aislar Redis.
3. Validar y cargar los 127 partidos con el generador existente. Registrar conteos por estado, distribución temporal, tamaño del dataset y huella de sus archivos.
4. Registrar versión o commit de ambos repositorios, cambios locales relevantes, versiones efectivamente ejecutadas de API, drivers, motores y generador, recursos de la notebook y recursos asignados a Docker.
5. Mantener idéntica la instrumentación durante línea base y optimización. Conservar la salida sin URI ni credenciales.

El backend inspeccionado contiene cambios locales: antes de medir habrá que fijar una versión reproducible o guardar un parche sin secretos con su huella. Un commit por sí solo no identifica archivos sin versionar.

**Criterio de cierre:** otra persona puede levantar el laboratorio, cargar los datos y verificar una respuesta correcta siguiendo el README.

## 4. Etapa 2: definir y automatizar la carga

Usar **Apache JMeter en ejecución sin interfaz**, por ser una herramienta de carga de aplicaciones mencionada en la Clase 13. Registrar la versión elegida al implementar. Los siguientes parámetros son una propuesta inicial de laboratorio, no cifras indicadas por la cátedra ni capacidad comprobada:

| Parámetro | Propuesta |
| --- | --- |
| Datos | Los mismos 127 partidos del Mundial de la demo. |
| Operación | Lectura completa del fixture; una clave caliente en Redis. |
| Perfiles | 1, 10 y 30 usuarios virtuales; ejecuciones separadas. |
| Modelo de carga | Cada usuario espera la respuesta y luego 1 segundo antes de la siguiente consulta. La tasa efectiva se mide; no se confunde usuarios con requests/s. |
| Calentamiento | 30 segundos fuera de las estadísticas principales. |
| Rampa | 30 segundos hasta la concurrencia objetivo. |
| Sostenimiento | 120 segundos con concurrencia objetivo; ventana principal de comparación. |
| Repeticiones | Tres por perfil y versión; guardar cada corrida, sin ocultar variación. |
| Timeout | 10 segundos por request; sin reintentos automáticos en el generador. |
| Caché | Borrar solamente la clave del laboratorio antes del calentamiento; mismo procedimiento en ambas versiones. |
| Finalización | Fin de la ventana y espera acotada de requests pendientes; registrar las que no terminan. |
| Interrupción | Manual disponible; detener si el equipo deja de responder, aparece presión sostenida de memoria o los errores superan el 10% durante 30 segundos. Registrar el motivo. |

Primero hacer un piloto de baja carga. Si la notebook no sostiene estos perfiles, ajustar y fijar los parámetros **antes** de generar la línea base definitiva. Una vez fijados, repetirlos sin cambios en la versión optimizada. La prueba no necesita llegar a la saturación para ser válida.

No aumentar artificialmente el número de partidos del Mundial para simular volumen. Explicar que el volumen proyectado de este listado es acotado y que el crecimiento estudiado es el acceso concurrente. Si luego se elige estudiar volumen de tracking o comentarios, eso requiere otro flujo, dataset y experimento expresamente documentados.

**Criterio de cierre:** el mismo plan de carga puede ejecutarse por configuración contra las dos versiones, con fases y límites explícitos.

## 5. Etapa 3: medir y conservar la línea base

| Capa | Qué registrar | Evidencia |
| --- | --- | --- |
| Generador | Operaciones iniciadas/terminadas, éxitos, fallos de contenido, errores HTTP, timeouts, latencia y throughput. CPU/memoria del propio generador. | Resultados de JMeter y resumen por corrida/fase. |
| API | Duración registrada por request, estado y correlación. | Logs existentes con `X-Request-Id`. |
| Adaptadores | Cantidad y duración de lecturas MongoDB, lecturas/escrituras Redis y fallos. | Logs del decorador `observe`; agregar conteos explícitos de aciertos/fallos de caché si hacen falta, antes de la línea base. |
| Motores | CPU/memoria de contenedores, conexiones y estadísticas disponibles. Para MongoDB, revisar el plan de consulta por separado. | Muestras de recursos y diagnósticos con fecha. |
| Entorno | CPU/memoria, presión de recursos y límites de Docker. | Registro de la notebook y muestreo durante la corrida. |

No equiparar el tiempo del adaptador con tiempo interno del motor: incluye cliente y comunicación. El log HTTP existente tampoco representa por sí solo todo el tiempo observado por el consumidor. Documentar cada frontera y las métricas no disponibles.

Reportar mínimo, mediana, p95, p99 y cantidad de observaciones de la ventana sostenida. Calcular throughput de respuestas exitosas por segundo y tasa de error con denominador explícito. Mostrar errores por tipo. Separar rampa y calentamiento. Los percentiles con pocas muestras se informan con esa limitación.

**Criterio de cierre:** cada número puede asociarse a datos crudos, versión, configuración, volumen, fase y entorno; no solamente a una captura.

## 6. Etapa 4: formular una hipótesis y aplicar una mejora

La optimización definitiva depende de la línea base. Examinar qué capa consume tiempo o recursos y proponer un cambio por vez.

**Primera candidata, condicionada a evidencia:** para el flujo previo al partido, evaluar TTL de 5 a 15 segundos, únicamente si el equipo acepta esa frescura y se observan reconstrucciones frecuentes de caché con costo relevante en MongoDB/API.

- Hipótesis: conservar más tiempo una respuesta reutilizada reduce reconstrucciones y consultas a MongoDB.
- Cambio: configuración de TTL en el laboratorio, conservando endpoint, dataset y escenario de lectores.
- Evidencia esperada: comparar consultas a MongoDB por request, aciertos de caché, latencias, errores y recursos. No prometer una mejora del p95: podría no cambiar.
- Costo: una respuesta puede permanecer desactualizada durante más tiempo si no se invalida; verificar expiración e invalidación con una actualización controlada, fuera de la carga principal.
- Alcance: no extrapolar la tolerancia de frescura de una consulta previa a un partido al seguimiento en vivo.

Si esa hipótesis no está respaldada, no cambiar el TTL por cumplir una receta. Revisar, según la evidencia, tamaño de datos transferidos, consulta real, uso del índice, serialización o espera por conexiones. Índices, proyecciones y pools son familias tratadas en la Clase 13 y admitidas por la consigna; un cambio concreto necesita diagnóstico. El listado actual ya tiene índice y proyección.

Registrar para cada intento: problema observado, hipótesis previa, cambio, archivos/configuración, costo, prueba posterior, resultado y decisión. Si el cambio no mejora o produce regresiones, conservar ese resultado y evaluar otra hipótesis. No terminar con una promesa de optimización pendiente de medir.

**Criterio de cierre:** al menos una optimización implementada, justificada y probada, con sus costos y resultados reales.

## 7. Etapa 5: repetición, comparación e integridad

Repetir los perfiles y las tres corridas con el mismo dataset, recursos, workers, timeouts, instrumentación y procedimiento de caché. Cambiar solamente la variable bajo análisis. Si hay diferencias inevitables, registrarlas y limitar la comparación.

Producir una tabla por perfil con latencias, throughput, éxitos, errores, consultas MongoDB, proporción de aciertos de caché y CPU/memoria. Mostrar variación entre repeticiones. Comparar cada métrica respetando su unidad y dirección; una disminución de latencia no implica necesariamente un aumento de throughput en este modelo de carga.

Validación de integridad para este flujo de lectura:

1. Antes y después, verificar que MongoDB conserva los 127 códigos únicos, estados, resultados y fechas esperados. Comparar una representación canónica ordenada de los campos relevantes.
2. Comprobar que una respuesta exitosa contiene los 127 partidos, sin duplicados, con contenido y orden correctos. No basta con HTTP 200. Registrar cómo se validan las respuestas y mantener ese costo igual en ambas versiones.
3. Conciliar operaciones iniciadas con respuestas correctas, respuestas incorrectas, errores y operaciones sin respuesta. No informar “registros insertados por la carga”: la carga principal no escribe.
4. Fuera de la ventana medida, modificar de forma controlada un estado/resultado de laboratorio, invalidar la caché y comprobar la nueva lectura. Probar también expiración sin invalidación y registrar la demora observada. Restaurar la instantánea antes de otra corrida.
5. Verificar que una recarga del dataset no duplica partidos y que la limpieza toca únicamente datos y claves del laboratorio.

**Criterio de cierre:** comparación verificable antes/después y comprobación de que respuestas y fuente mantienen la integridad.

## 8. Etapa 6: propuesta de Data Mart

**Pregunta propuesta:** ¿cuántos partidos jugó y cuántos goles a favor y en contra acumuló cada selección por fase, considerando partidos finalizados?

Es un análisis separado del listado operacional. No se agrega a cada request de `/fixture` ni se afirma que ya existe en el backend.

| Elemento | Diseño propuesto |
| --- | --- |
| Fuentes | MongoDB `partidos` para equipos, fase, estado y resultado; `equipos` para atributos descriptivos, cuando sus identificadores coincidan. Redis no es fuente histórica. |
| Grano | Una fila por partido finalizado y selección participante: dos filas por encuentro. |
| Clave | `(codigo_partido, codigo_equipo)`. |
| Atributos y medidas | Fecha, fase, condición local/visitante, partidos jugados = 1, goles a favor y en contra. |
| Transformación | Filtrar finalizados y desdoblar cada partido en sus dos participantes; invertir goles para la fila visitante. Resolver nombres por código y conservar procedencia. |
| Actualización | Lote propuesto cada 5 minutos; documentar tiempo de ejecución y retraso efectivo. No es una frecuencia exigida por la cátedra. |
| Frescura | Objetivo propuesto: disponibilidad dentro de 5 minutos más el tiempo del lote después del cierre/corrección. Debe aceptarse explícitamente para este uso analítico. |
| Duplicados y correcciones | Reemplazar filas por su clave; reprocesar ambos participantes cuando se corrige un resultado. Retirar o reconstruir filas si el partido deja de estar finalizado. |
| Fallos parciales | Preparar y validar una nueva versión antes de publicarla; conservar la última versión completa si falla el lote. Reintentar sin sumar dos veces. |
| Faltantes | No convertir un resultado faltante en 0–0. Registrar el partido pendiente/rechazado; preservar su código para revisar la causa. |
| Validación | Para N partidos completos hay 2N filas; claves únicas; suma global de goles a favor igual a goles en contra; totales por equipo contrastados con la fuente. |

Validar cómo distingue el dataset los goles de juego de una tanda antes de incluir partidos con penales. Si no los distingue, declarar esa limitación y no inventar la separación.

El escenario demo tiene pocos finalizados: sirve para comprobar transformaciones, no para probar rendimiento analítico masivo. Se pueden generar instantáneas sintéticas adicionales de estados/resultados sobre los mismos 127 partidos para validar el diseño, identificándolas como tales.

El entregable mínimo será la propuesta documentada con ejemplo de entrada/salida y validaciones. Construir un pipeline completo o medir esta proyección sería trabajo adicional, no requisito asumido del plan.

## 9. Etapa 7: comparación relacional del mismo caso

Documentar una alternativa conceptual con tablas `equipos` y `partidos`, claves de equipo local/visitante, resultado y un índice para el orden del fixture. Explicar la consulta con dos relaciones hacia equipos cuando los nombres estén normalizados, y la posibilidad de una proyección si se decide duplicar esos atributos.

Comparar concretamente:

- MongoDB conserva en cada partido los datos del listado; la alternativa normalizada resuelve relaciones y centraliza la actualización de atributos de equipos.
- Ambas necesitan resolver orden, acceso concurrente y actualización consistente del resultado. Redis podría cachear cualquiera de las dos; el efecto de la caché no prueba superioridad de un modelo de base.
- En la alternativa relacional, claves foráneas y transacciones pueden expresar integridad entre filas; especificar cuáles se necesitarían, sin atribuir al laboratorio actual garantías distribuidas que no se midieron.
- Para la vista analítica, describir cómo las filas partido/selección permitirían agregaciones por fase y equipo, frente a recalcular desde documentos operacionales.
- Condicionar conveniencia a patrón de acceso, cambios de atributos, volumen, concurrencia, garantías y costo de mantener proyecciones.

Marcar toda esta sección como **análisis conceptual sin benchmark SQL**. No asignar latencias, TPS ni porcentajes inventados. No concluir que una alternativa es universalmente más rápida.

## 10. Organización propuesta de entrega

```text
hito-12/
  README.md
  config/
    escenario.json
    entorno.env.example
  scripts/
    preparar_datos.py
    ejecutar_carga.sh
    recolectar_recursos.py
    validar_integridad.py
    comparar_resultados.py
    limpiar_datos_de_prueba.py
  carga/
    fixture.jmx
  docs/
    flujo_y_escenario_de_carga.md
    linea_base.md
    hipotesis_y_optimizacion.md
    comparacion_antes_despues.md
    integracion_data_mart.md
    comparacion_relacional.md
    integridad_y_limitaciones.md
  evidencia/
    linea_base/<id-corrida>/
    optimizada/<id-corrida>/
```

Cada corrida conserva manifiesto sin secretos, resultados crudos, recursos, validación y resumen. El README incluye requisitos, preparación de ambos repositorios, orden de ejecución y limpieza acotada. No se borran volúmenes indiscriminadamente ni se publican `.env`, credenciales o dumps innecesarios.

Los cambios funcionales de la API se implementarán en el backend. Si afectan el contrato público, sus instrucciones requieren sincronizar OpenAPI, Postman y documentación. La entrega del hito debe enlazar la versión exacta de ese backend y quedar versionada en GitHub al completarse.

## 11. Lista de cierre y trazabilidad

| Trabajo | Requisitos principales |
| --- | --- |
| Flujo, escenario y dataset | RF1–RF3; RNF6, RNF7, RNF9. |
| Línea base y separación de mediciones | RF4–RF6; RNF2, RNF5. |
| Hipótesis y cambio aplicado | RF7–RF8. |
| Repetición, comparación y trade-off | RF9–RF11; RNF3. |
| Propuesta analítica y actualización | RF12–RF13; RNF12. |
| Alternativa relacional | RF14. |
| Integridad y evidencia | RF15–RF16; RNF4, RNF14. |
| README, scripts, limpieza y GitHub | RNF1, RNF8, RNF10, RNF11, RNF13. |

El hito queda completo cuando otra persona puede reproducir la comparación, verificar la integridad, entender el costo del cambio y distinguir mediciones, hipótesis y propuesta analítica. Prometheus/Grafana pueden continuarse en el Hito 13 sin convertirlos en dependencia de esta entrega.
