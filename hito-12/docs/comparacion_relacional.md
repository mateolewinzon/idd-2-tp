# Alternativa relacional: análisis conceptual del mismo flujo

Esta sección no contiene un benchmark SQL. Se compara el patrón de acceso de `GET /fixture` y su derivación analítica, con los mismos datos de partidos, equipos, estados y resultados. Ningún valor de JMeter se atribuye a una base relacional no ejecutada.

## Modelo posible y operaciones

Una alternativa normalizada tendría:

- `equipos(codigo PK, nombre)`.
- `partidos(codigo PK, fecha_hora, fase, grupo, local_codigo FK nullable, visitante_codigo FK nullable, estado, goles_local, goles_visitante, penales_local, penales_visitante)`.
- Índice de partidos por `(fecha_hora, codigo)` para el orden del listado.

Las plazas no resueltas se representan con FK nula. Restricciones de estado y marcador deben expresar que un próximo no tiene resultado, mientras un encuentro en vivo/finalizado tiene goles enteros no negativos. Las claves foráneas verifican referencias cuando están resueltas. Las reglas precisas y su aplicación dependen del motor/configuración elegidos; no se afirma que este esquema se haya desplegado.

Una lectura del fixture podría ser:

```sql
SELECT p.codigo, p.fecha_hora, p.fase, p.grupo, p.estado,
       p.local_codigo, l.nombre AS nombre_local,
       p.visitante_codigo, v.nombre AS nombre_visitante,
       p.goles_local, p.goles_visitante, p.penales_local, p.penales_visitante
FROM partidos AS p
LEFT JOIN equipos AS l ON l.codigo = p.local_codigo
LEFT JOIN equipos AS v ON v.codigo = p.visitante_codigo
ORDER BY p.fecha_hora, p.codigo;
```

`LEFT JOIN` preserva partidos cuyas plazas todavía no están resueltas. La aplicación reconstruiría el mismo contrato JSON. No se presupone que un join sea lento: se necesitarían mediciones de ese motor, índices y cardinalidad para afirmarlo.

Para actualizar un marcador se haría un `UPDATE` por código dentro de la transacción local requerida. Si se actualizan varias filas que deben representar un único cambio, la transacción y el aislamiento se elegirían según esa garantía. La invalidación de una caché externa seguiría siendo un problema adicional; la transacción SQL por sí sola no incluye Redis.

## Comparación condicionada

| Aspecto | Implementación documental probada | Alternativa relacional conceptual |
| --- | --- | --- |
| Lectura del listado | Documento por partido, con referencias descriptivas embebidas; consulta con proyección y orden. | Partidos más dos relaciones a equipos si se normalizan los nombres; mismo orden y proyección equivalente. |
| Cambio de nombre de equipo | Puede exigir actualizar las copias embebidas y caché. | La tabla de equipos centraliza ese atributo; la lectura lo obtiene por join. |
| Resultado/estado | En un documento, con validador y actualizaciones por `_id`. | Campos en fila, restricciones y transacciones locales según el caso. |
| Caché | Redis evita consultas mientras la copia es válida. | Puede aplicarse la misma caché y enfrentar la misma invalidez temporal. |
| Crecimiento de lecturas | Depende de aciertos, serialización, red y recursos; se midió sólo hasta 30 lectores. | Dependería del mismo patrón de respuestas, plan de joins y recursos; no se midió. |
| Crecimiento de datos | El listado completo requiere transferir más datos si cambia su alcance. | Lo mismo; no desaparece el costo de devolver el listado por normalizarlo. |
| Consistencia de referencias | Se conserva una copia descriptiva al cargar; no se probó actualización distribuida de equipos/partidos. | FK y transacciones podrían expresar integridad entre tablas en un motor local. |
| Analítica | Desdoblar partidos en participaciones y materializar medidas por equipo/fase. | Hechos de participación y dimensiones, con agregaciones SQL; también exige diseñar actualización y procedencia. |

MongoDB puede resultar conveniente si las lecturas consumen un documento autocontenido de estructura flexible y se acepta mantener atributos embebidos. Un modelo relacional puede resultar conveniente si predominan relaciones normalizadas, cambios centralizados de atributos e integridad entre varias tablas. Para este listado pequeño, la elección no se puede decidir a partir de una afirmación general de velocidad.

Si se quisiera un benchmark futuro, habría que fijar datos, garantía de respuesta, consultas equivalentes, hardware, caché, duraciones y concurrencia comparables. No enfrentar una lectura Redis de la variante NoSQL contra una consulta SQL sin caché y atribuir la diferencia al modelo. Quedan sin medir SQL, ingestión masiva, escalado horizontal, replicación y fallas regionales.
