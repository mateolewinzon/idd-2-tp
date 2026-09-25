# Protocolo y Evaluación de Rendimiento — Subsistema de Comentarios Masivos (Hito 6)

## Plataforma del Fixture del Mundial 2030 — Ingeniería de Datos II

---

## 1. Definición del Experimento y Objetivo de Medición

El propósito de la prueba de carga del Hito 6 es evaluar la capacidad de ingestión y la estabilidad de Apache Cassandra frente al escenario operacional más exigente del Mundial 2030: la ráfaga de comentarios masivos durante los momentos culminantes de los encuentros deportivos.

- **Objetivo técnico de diseño:** Alcanzar o aproximar un régimen de **10.000 escrituras por segundo** concurrentes de forma sostenida.
- **Operación evaluada:** Inserción concurrente de filas en la tabla principal `comentarios_feed` respetando la estructura del modelo tabular definitivo:
  - Clave de partición compuesta: `((partido_id, bloque_temporal))`.
  - Ventana temporal: bloques de **5 minutos**.
  - Columna de clustering: `comentario_id` de tipo `timeuuid` (orden descendente).
  - Configuración de almacenamiento: TTL de 14 días y compactación TWCS.
- **Nivel de consistencia utilizado en la prueba:** `LOCAL_ONE` (equivalente a `ONE` en entorno mononodo local).

---

## 2. Generación de Datos Sintéticos y Distribución de Carga

En consonancia con las buenas prácticas implementadas en el Hito 4 (MongoDB) y el Hito 5 (Neo4j), los datos de prueba no se generan de forma uniforme ni se concentran artificialmente en un único registro ficticio, sino que reproducen fielmente la **asimetría y el sesgo observados en torneos reales**:

### 2.1. Criterios de Distribución del Conjunto Sintético
1. **Distribución entre Partidos (Sesgo de Audiencia):**
   - En lugar de concentrar 1.000.000 de comentarios en un solo partido aislado, la carga se reparte entre un conjunto representativo de encuentros:
     - **Partido A (Alta Audiencia / Final):** Concentra aproximadamente el **50%** de la muestra total (~500.000 comentarios).
     - **Partidos B y C (Partidos Destacados / Clásicos):** Concentran el **20%** cada uno (~200.000 comentarios por partido).
     - **Partidos D a G (Fase de Grupos Periférica):** Concentran el **10%** restante, dispersos en volúmenes de 20.000 a 50.000 comentarios cada uno.
2. **Distribución Temporal y Ventanas de Bloque:**
   - Los instantes de emisión abarcan una ventana simulada de 150 minutos por encuentro. Los timestamps se generan de forma continua y se agrupan en ventanas discretas de 5 minutos, garantizando que el generador distribuya la carga sobre múltiples particiones temporales rotativas a lo largo del tiempo.
3. **Distribución Lingüística Informativa:**
   - El perfil de estrés genera cinco valores sintéticos distintos para `idioma`. La carga de rendimiento mide cardinalidad y tamaño de los datos, no reproduce etiquetas literales ni porcentajes de negocio. La carga exacta posterior sí aplica la distribución 40/30/15/10/5; `carga_muestra.cql` valida además las etiquetas literales.
4. **Estados de Moderación:**
   - El perfil genera tres valores sintéticos con una distribución sesgada. La carga exacta aplica 98% `'VISIBLE'`, 1,5% `'PENDIENTE'` y 0,5% `'REPORTADO'`; sus operaciones se verifican con la carga de muestra. El benchmark evita agregar lógica de aplicación que distorsione la medición de escritura.

La materialización final se realiza con `generar_millon.py` y `carga_millon.sh`. A diferencia del perfil de estrés, este generador produce exactamente 1.000.000 de claves `timeuuid` distintas, conserva siete partidos y treinta bloques de cinco minutos por partido, y aplica explícitamente las proporciones de audiencia, idioma y moderación descriptas arriba.

### 2.2. Valor Metodológico de la Muestra Sesgada
Esta estructura de datos permite demostrar empíricamente:
- Que las particiones temporales de 5 minutos en partidos calientes absorben el flujo masivo de escrituras rotando los tokens periódicamente en el anillo.
- Que se generan 210 particiones diferentes para `((partido_id, bloque_temporal))`. En el laboratorio mononodo todas pertenecen al mismo nodo; la distribución física entre nodos sólo puede validarse en una topología multinodo.
- Que la consulta de feed responde con latencia uniforme sin sufrir contención entre partidos de distinta envergadura ni requerir consultas distribuidas por idioma.

---

## 3. Protocolo de Ejecución de la Prueba de Carga

La prueba se ejecuta mediante el script de estrés (`scripts/rendimiento.sh`) que interactúa contra el nodo Cassandra expuesto en el puerto 9042, utilizando una herramienta de benchmarking estándar (como `cassandra-stress` nativo de la imagen oficial o un cliente concurrente en Python/Go con el driver DataStax).

Se separan dos mediciones para no confundir semánticas:

1. **Benchmark online:** `rendimiento.sh` ejecuta un millón de operaciones preparadas de una fila con `cassandra-stress` y registra throughput y percentiles de latencia. Debido a la selección aleatoria de claves, algunas operaciones son upserts sobre una clave ya visitada.
2. **Carga física exacta:** `carga_millon.sh` genera un CSV determinista, lo importa mediante `COPY FROM` y reexporta solamente las claves primarias para comprobar que quedaron exactamente 1.000.000 de comentarios diferentes. Esta ruta mide throughput batch y no informa percentiles por fila.

### Parámetros de Configuración del Benchmark:
- **Concurrencia de Clientes:** Múltiples hilos concurrentes (ej. 50 a 200 workers simultáneos).
- **Mecanismo de Conexión:** Protocolo nativo binario CQL v4/v5 con multiplexación de canales.
- **Preparación previa:** 50.000 operaciones de calentamiento, descartadas mediante `TRUNCATE` antes de la medición, para permitir la compilación JIT y el llenado de buffers.
- **Medición efectiva:** Ingestión sostenida registrando throughput (ops/seg) y latencias percentilares (p50, p95, p99).

---

## 4. Registro de Evidencia Empírica de Rendimiento

> **Instrucciones para el Evaluador y el Equipo:**
> Los valores siguientes provienen de la ejecución real de `./scripts/rendimiento.sh`.
> La salida completa, sin valores simulados, se conserva en `evidencia/`.

### 4.1. Ficha Técnica del Entorno de Prueba
- **Fecha y Hora de Ejecución:** 2026-09-25, de 17:17:46 a 17:20:16 (ART, UTC-03).
- **Versión Observada de Cassandra (`SHOW VERSION`):** Cassandra 5.0.9, `cqlsh` 6.2.0, CQL spec 3.4.7 y Native protocol v5.
- **Sistema Operativo Host:** macOS 26.5.2 sobre arquitectura ARM64.
- **Recursos Asignados al Contenedor Docker:**
  - CPUs asignadas: 10 CPU lógicas.
  - Memoria RAM asignada: 8.321.712.128 bytes (aprox. 7,75 GiB).
  - Parámetros de JVM Heap: máximo observado de 3.968 MB.
  - Memoria RAM del host: 17.179.869.184 bytes (16 GiB).
  - Tipo de almacenamiento: bind mount de Docker Desktop sobre `~/docker/data/cassandra`.
  - Imagen: `cassandra:latest`, ID local `sha256:ee178b38a2746a8e15a115bd038ad1f864391d04a84162a018cb0dd79511709a`.
  - Generador: `cassandra-stress`, 100 threads, 50.000 operaciones de calentamiento y consistencia `LOCAL_ONE`.

### 4.2. Resultados Obtenidos de Throughput y Latencia

| Métrica Evaluada | Objetivo Teórico | Resultado Observado en el Ambiente | Cumplimiento |
| :--- | :--- | :--- | :--- |
| **Throughput online promedio (`cassandra-stress`)** | **10.000 ops/seg** | **6.860 ops/seg** | **PARCIAL / limitado por el entorno local** |
| **Throughput Pico Registrado** | N/A | **10.757 ops/seg** en un intervalo de 5 segundos | Objetivo alcanzado en ráfaga, no sostenido |
| **Carga batch exacta (`COPY FROM`)** | **10.000 filas/seg** | **97.942 filas/seg**, 1.000.000 importadas y 0 omitidas | **SÍ** |
| **Latencia Percentil 50 (Mediana)** | $< 5\text{ ms}$ | **1,9 ms** | **SÍ** |
| **Latencia Percentil 95 (p95)** | $< 15\text{ ms}$ | **24,7 ms** | **NO** |
| **Latencia Percentil 99 (p99)** | $< 30\text{ ms}$ | **54,3 ms** | **NO** |
| **Tasa de Errores / Timeouts** | $0\%$ | **0 errores sobre 1.000.000 de operaciones (0%)** | **SÍ** |

El benchmark online completó **1.000.000 de operaciones de inserción** en **2 minutos y 25 segundos**. `cassandra-stress` informó 1.000.000 de particiones operadas y cero errores. La selección aleatoria dejó 633.146 claves físicas distintas; por eso ese resultado se interpreta como un millón de escrituras/upserts, no como el conteo final de comentarios únicos.

La carga exacta posterior comenzó a las 17:25:01 ART y terminó a las 17:25:11 ART. Importó **1.000.000 de comentarios únicos en 10,210 segundos**, sin omisiones. Una exportación paginada posterior contó exactamente **1.000.000 de claves primarias**. Luego del `flush`, `nodetool tablestats` confirmó 210 particiones físicas y aproximadamente 24,8 MB de espacio vivo comprimido.

La verificación inicial mediante `COUNT(*)` global excedió el `read_request_timeout` del servidor. Esto confirma que un agregado global sin clave de partición no es un patrón de acceso adecuado para Cassandra. La verificación definitiva se hizo con `COPY TO` paginado, que sí recorrió las filas sin bloquear al coordinador. Ambas evidencias se conservan en `evidencia/conteo_final.txt` y `evidencia/verificacion_millon.txt`.

---

## 5. Análisis de Cuellos de Botella y Limitaciones del Entorno Local

En caso de que el entorno de ejecución no alcance la meta estricta de las 10.000 escrituras por segundo, la evaluación académica contempla el rigor del diagnóstico y la comprensión de los factores limitantes del hardware:

### 5.1. Factores Limitantes Típicos en Nodo Único Local:
1. **Contención de I/O por fsync y CommitLog:**
   - En un nodo único, el proceso que genera la carga compite por el mismo bus de disco e interfaces I/O que el demonio de Cassandra que escribe sincrónicamente el `CommitLog` en `~/docker/data/cassandra`.
2. **Sobrecarga de Virtualización y Puentes de Red en Docker:**
   - La capa de traducción de red virtual de Docker Desktop (especialmente en macOS y Windows) introduce latencia en la pila TCP al multiplexar miles de conexiones concurrentes en el puerto 9042.
3. **Pausas de Recolección de Basura de la JVM (GC Pauses):**
   - Con heaps locales acotados (1 a 2 GB), la rápida rotación de objetos en memoria ante 10.000 ops/seg puede disparar pausas frecuentes de Stop-The-World del recolector G1GC, incrementando la latencia en el percentil 99.
4. **Competencia CPU entre Generador y Base:**
   - Si el cliente de prueba corre en la misma máquina host que el contenedor de Cassandra, ambos compiten por los mismos núcleos de CPU para serialización/deserialización y hashing.

---

## 6. Propuestas de Optimización y Escalabilidad Productiva

Para escalar el subsistema y garantizar holgadamente más de 10.000 escrituras por segundo en producción, se establecen las siguientes recomendaciones de arquitectura:

1. **Separación de Discos para CommitLog y Datos:**
   - Configurar discos dedicados de estado sólido (NVMe) exclusivos para el `commitlog_directory`, aislándolo del `data_file_directories` para eliminar la contención entre escrituras secuenciales y compactaciones de SSTables.
2. **Escalabilidad Horizontal del Anillo (Cluster Multi-Nodo):**
   - Cassandra exhibe una curva de escalabilidad lineal. Si un único nodo en hardware dedicado alcanza ~3.500 ops/seg, un cluster de 3 a 5 nodos por datacenter superará holgadamente las 15.000 a 20.000 ops/seg, dispersando los tokens de los bloques de 5 minutos en paralelo.
3. **Ajuste de Concurrencia en Clientes y Drivers:**
   - Utilizar pools de conexiones asincrónicas no bloqueantes en los drivers cliente, configurando `execute_async` con control de contrapresión (*backpressure*) para maximizar la saturación del pipeline sin agotar la memoria del cliente.
4. **Sintonización de la JVM:**
   - Migrar a Java 17/21 con el recolector de basura ZGC (*Z Garbage Collector*) o Shenandoah en producción, reduciendo las pausas de GC a menos de 1 milisegundo independientemente del tamaño del heap.
