# Integración analítica y Data Mart

## Pregunta y procedencia

**Pregunta:** ¿cuántos partidos jugó y cuántos goles a favor y en contra acumuló cada selección por fase, considerando sólo partidos finalizados?

La fuente operacional utilizada por el prototipo es MongoDB `fixture2030_hito12.partidos`. Los códigos/nombres de equipos ya están embebidos en esos documentos por el seed, a partir de `equipos.csv` y `participaciones.csv`. El prototipo no simula una lectura de la colección `equipos`: esa colección no se carga en este laboratorio. Si se añadieran atributos de `equipos`, habría que validar explícitamente la correspondencia por código. Redis contiene una respuesta derivada y con vencimiento; no alimenta el histórico analítico.

No se integran motores ajenos a la pregunta. La integración aquí consiste en transformar partidos, participantes y resultados operacionales en una proyección de hechos por selección; no se sostiene que el prototipo sea una integración multifuente MongoDB/InfluxDB.

## Estructura propuesta

Grano: una fila por partido finalizado y selección participante, dos por partido completo. Clave `(partido, equipo)`.

| Atributo/medida de la proyección | Origen / transformación |
| --- | --- |
| partido | `_id` operacional. |
| equipo / nombre_equipo | `local.codigo/nombre` o `visitante.codigo/nombre`. |
| fase / fecha_hora | Campos del partido; conservar UTC en la extracción. |
| condicion | Local o visitante, según el participante. |
| partidos_jugados | Constante 1 para cada participación válida en partido finalizado. |
| goles_favor | `resultado.goles_local` para local; `resultado.goles_visitante` para visitante. |
| goles_contra | El campo opuesto al de goles a favor. |
| source_collection / source_id | `partidos` e identificador original, para procedencia. |

Los goles de `resultado.penales` no se agregan a los goles del partido: el contrato sí distingue esa tanda. La prueba unitaria incluye empate 2–2 con tanda 4–3 y verifica que cada fila conserve 2 a favor y 2 en contra.

La proyección agrupa las filas por `(equipo, fase)` y suma las tres medidas. La entrada está conservada en `evidencia/data_mart_source.json`; las filas, totales y controles se publican en `evidencia/data_mart.json`. El ejemplo real usa la instantánea de la demo: P-001, Uruguay 2–1 Arabia Saudita, produce una fila URU (1 partido, 2 goles a favor y 1 en contra) y otra KSA (1 partido, 1 gol a favor y 2 en contra). Son resultados sintéticos del escenario, no del Mundial oficial. Las pruebas sintéticas no se presentan como partidos realmente jugados ni como benchmark analítico.

## Extracción, transformación y publicación

Implementación mínima ejecutable: `scripts/data_mart.py`, fuera de la API.

1. Extraer los partidos del laboratorio y guardar una instantánea con huella SHA-256.
2. Rechazar identificadores repetidos; ignorar estados todavía no finalizados.
3. Verificar participantes distintos, resultado completo y goles enteros no negativos. Un dato faltante no se convierte en cero.
4. Transformar cada finalizado en sus dos filas; agregar medidas por selección/fase.
5. Comprobar claves únicas, 2N filas, igualdad global de goles a favor/en contra y totales contra un cálculo separado desde la fuente.
6. Si hay partidos finalizados inválidos, abortar la publicación y conservar la última salida completa. La función de transformación produce la lista de rechazos; el fallo del comando señala que la fuente necesita corrección.
7. Escribir en un archivo temporal del mismo directorio y publicar mediante reemplazo atómico local. Un reintento reemplaza la instantánea, no incrementa sus totales.

El prototipo se ejecuta manualmente. **Propuesta de actualización:** lote cada 5 minutos, con retraso esperado de hasta 5 minutos más el tiempo del lote desde que un cierre/corrección es visible en la fuente. Es un objetivo de diseño para esta pregunta analítica, no un retraso medido ni una tarea programada instalada.

Reprocesar la instantánea completa permite incluir datos tardíos y correcciones, y retirar filas cuando un encuentro deja de estar finalizado. Para 127 partidos es una regla simple y verificable. Si creciera la fuente, el equipo debería medir el costo y diseñar una extracción incremental con controles adicionales; este trabajo no afirma haberla construido.

## Fallas y consistencia

El reemplazo atómico protege la publicación de un archivo parcial; no proporciona una transacción distribuida ni una instantánea transaccional de toda la fuente MongoDB. En la demo y las pruebas de carga la fuente permanece estática durante la extracción. Con escrituras concurrentes habría que definir una frontera de versión o consistencia de lectura y verificar que el lote represente un estado coherente.

Un fallo de lectura o validación conserva la última publicación. Si cambia la fuente entre el registro de extracción y la publicación, la huella identifica qué entrada produjo la salida, pero no elimina el retraso. Esa frescura debe comunicarse con `extracted_at` y la versión de los datos.

## Validaciones ejecutables

`test_data_mart.py` cubre: exclusión de goles de tanda, reintento sin duplicación, corrección tardía, retirada al reabrir un encuentro, rechazo de duplicados, resultado faltante, participantes repetidos y conservación del archivo anterior si falla una actualización.

La comparación operacional/analítica es conceptual: el endpoint devuelve el listado y aprovecha caché; la proyección permite sumar medidas ya transformadas por fase/equipo sin recalcular la participación desde cada partido. No se midió el rendimiento de consultas sobre un Data Mart grande ni se instaló una plataforma BI o un almacén dimensional completo.
