# Comparación medida antes/después

Resultados de HTTP real con MongoDB/Redis reales. Ventana sostenida de 60 s por corrida; tres repeticiones por perfil. Línea base: TTL 5 s. Optimizada: TTL 15 s.

| Lectores | Versión | Requests | Errores | p95 medio de corridas (rango), ms | p99 medio, ms | Éxitos/s medios | Consultas MongoDB (3 corridas) | Aciertos medios |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | baseline | 177 | 0 | 30.00 (26–35) | 49.67 | 0.983 | 36 | 79.66% |
| 1 | optimized | 177 | 0 | 27.67 (22–33) | 67.33 | 0.983 | 12 | 93.22% |
| 10 | baseline | 1757 | 0 | 26.00 (23–28) | 63.00 | 9.761 | 36 | 97.95% |
| 10 | optimized | 1750 | 0 | 22.67 (17–28) | 69.67 | 9.722 | 23 | 98.69% |
| 30 | baseline | 5304 | 0 | 30.33 (26–33) | 51.67 | 29.467 | 123 | 97.68% |
| 30 | optimized | 5303 | 0 | 23.33 (21–25) | 46.67 | 29.461 | 22 | 99.59% |

Los percentiles se calculan dentro de cada corrida por rango más cercano. La tabla muestra su media y rango entre repeticiones: no son percentiles de una mezcla de todas las corridas. La pausa de un segundo por usuario limita deliberadamente la tasa; el throughput no representa la capacidad máxima del sistema.

## Operaciones evitadas y variación de latencia

- 1 lectores: consultas MongoDB 36 → 12 (66.7% menos); cambio del p95 medio: -7.8%.
- 10 lectores: consultas MongoDB 36 → 23 (36.1% menos); cambio del p95 medio: -12.8%.
- 30 lectores: consultas MongoDB 123 → 22 (82.1% menos); cambio del p95 medio: -23.1%.

## Recursos por corrida

| Versión / corrida | CPU MongoDB media % | RAM MongoDB % límite | CPU Redis media % | RAM Redis % límite | RSS API MiB | RSS Java MiB |
| --- | --- | --- | --- | --- | --- | --- |
| baseline / r1-u1 | 1.22 | 15.92 | 0.71 | 7.74 | 47.22 | 61.82 |
| baseline / r1-u10 | 1.49 | 17.45 | 0.88 | 7.92 | 55.45 | 81.50 |
| baseline / r1-u30 | 1.55 | 21.76 | 0.96 | 8.12 | 81.71 | 88.15 |
| baseline / r2-u1 | 1.02 | 22.03 | 0.71 | 8.09 | 48.47 | 62.18 |
| baseline / r2-u10 | 0.69 | 22.20 | 0.80 | 8.10 | 71.02 | 87.35 |
| baseline / r2-u30 | 1.01 | 22.37 | 1.03 | 8.36 | 85.37 | 102.27 |
| baseline / r3-u1 | 1.13 | 22.61 | 0.75 | 8.17 | 48.37 | 60.58 |
| baseline / r3-u10 | 1.05 | 22.98 | 0.93 | 8.16 | 54.71 | 82.33 |
| baseline / r3-u30 | 1.02 | 23.51 | 1.10 | 8.27 | 75.99 | 92.66 |
| optimized / r1-u1 | 1.14 | 24.03 | 0.80 | 8.20 | 41.31 | 60.19 |
| optimized / r1-u10 | 1.47 | 24.35 | 0.78 | 8.12 | 70.02 | 82.41 |
| optimized / r1-u30 | 0.81 | 24.40 | 0.98 | 8.29 | 81.02 | 105.12 |
| optimized / r2-u1 | 1.02 | 24.71 | 0.81 | 8.18 | 47.99 | 62.45 |
| optimized / r2-u10 | 0.94 | 25.13 | 0.86 | 8.09 | 75.26 | 95.58 |
| optimized / r2-u30 | 0.78 | 25.20 | 1.02 | 8.34 | 82.47 | 107.98 |
| optimized / r3-u1 | 0.85 | 25.64 | 0.73 | 8.19 | 47.16 | 74.68 |
| optimized / r3-u10 | 0.94 | 25.75 | 0.93 | 8.16 | 63.96 | 86.20 |
| optimized / r3-u30 | 1.00 | 26.15 | 1.04 | 8.30 | 84.09 | 162.11 |

Recursos muestreados aproximadamente cada 5 s más la demora del recolector. CPU de contenedores es la reportada por Docker; `%CPU` de `ps` es un promedio del proceso, no una medición instantánea ni CPU de toda la notebook. RSS Java incluye la JVM de JMeter; sus límites son 256–512 MiB de heap, no de RSS. En `resources.jsonl` también se guardan red, I/O acumulados y `vm_stat` de macOS; no se atribuyen exclusivamente a una operación.

## Separación API/adaptadores

| Versión / corrida | API p95 ms | Logs API | MongoDB adaptador media ms | Redis GET adaptador media ms |
| --- | --- | --- | --- | --- |
| baseline / r1-u1 | 22.70 | 59.00 | 10.28 | 3.22 |
| baseline / r1-u10 | 22.10 | 584.00 | 8.73 | 3.70 |
| baseline / r1-u30 | 25.30 | 1770.00 | 19.00 | 3.19 |
| baseline / r2-u1 | 32.50 | 59.00 | 10.59 | 2.76 |
| baseline / r2-u10 | 23.90 | 586.00 | 9.05 | 3.69 |
| baseline / r2-u30 | 29.80 | 1764.00 | 13.39 | 3.04 |
| baseline / r3-u1 | 27.00 | 59.00 | 11.37 | 3.02 |
| baseline / r3-u10 | 17.50 | 587.00 | 10.72 | 2.88 |
| baseline / r3-u30 | 22.20 | 1770.00 | 12.59 | 3.01 |
| optimized / r1-u1 | 26.40 | 59.00 | 12.32 | 4.17 |
| optimized / r1-u10 | 18.30 | 584.00 | 9.56 | 2.91 |
| optimized / r1-u30 | 18.20 | 1770.00 | 9.82 | 2.95 |
| optimized / r2-u1 | 23.50 | 59.00 | 13.28 | 2.83 |
| optimized / r2-u10 | 15.00 | 582.00 | 7.00 | 2.77 |
| optimized / r2-u30 | 21.20 | 1763.00 | 9.53 | 2.71 |
| optimized / r3-u1 | 19.20 | 59.00 | 10.12 | 2.87 |
| optimized / r3-u10 | 21.80 | 584.00 | 15.56 | 2.77 |
| optimized / r3-u30 | 17.90 | 1770.00 | 8.90 | 2.54 |

Los logs API/adaptadores se seleccionan por fin de operación; JMeter por inicio. La media del adaptador MongoDB corresponde sólo a las consultas que ocurrieron. Sus tiempos incluyen driver y comunicación: no son tiempo interno puro del motor.

## Integridad y límites

Las 18 corridas verificaron los mismos 127 códigos únicos y contenido igual a MongoDB antes/después. Requests medidos: 14468; errores medidos: 0.

La línea base se ejecutó antes de la versión optimizada, sin aleatorizar el orden. Ambas comparten notebook con otros procesos y contenedores; los cambios pequeños de latencia pueden deberse al entorno. El ahorro de consultas no acredita capacidad mundial ni ingesta masiva. Ver `hipotesis_y_optimizacion.md`, `integridad_y_limitaciones.md` y los archivos crudos de cada corrida.
