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
   - La columna regular `idioma` replica la curva de mercado asumida en la plataforma (Español 40%, Inglés 30%, Portugués 15%, Francés 10%, Árabe 5%). Al no ser parte de la clave primaria, se demuestra empíricamente la viabilidad de recuperar el feed global y resolver el filtrado lingüístico en la capa de consumo.
4. **Estados de Moderación:**
   - La gran mayoría de los mensajes se inicializan en estado `'VISIBLE'` (98%), reservando un 1,5% para estado `'PENDIENTE'` y un 0,5% para estado `'REPORTADO'` para habilitar la verificación de la cola de moderación.

### 2.2. Valor Metodológico de la Muestra Sesgada
Esta estructura de datos permite demostrar empíricamente:
- Que las particiones temporales de 5 minutos en partidos calientes absorben el flujo masivo de escrituras rotando los tokens periódicamente en el anillo.
- Que el hash Murmur3 reparte uniformemente los tokens generados por `((partido_id, bloque_temporal))` entre los diferentes nodos del cluster.
- Que la consulta de feed responde con latencia uniforme sin sufrir contención entre partidos de distinta envergadura ni requerir consultas distribuidas por idioma.

---

## 3. Protocolo de Ejecución de la Prueba de Carga

La prueba se ejecuta mediante el script de estrés (`scripts/rendimiento.sh`) que interactúa contra el nodo Cassandra expuesto en el puerto 9042, utilizando una herramienta de benchmarking estándar (como `cassandra-stress` nativo de la imagen oficial o un cliente concurrente en Python/Go con el driver DataStax).

### Parámetros de Configuración del Benchmark:
- **Concurrencia de Clientes:** Múltiples hilos concurrentes (ej. 50 a 200 workers simultáneos).
- **Mecanismo de Conexión:** Protocolo nativo binario CQL v4/v5 con multiplexación de canales.
- **Preparación previa:** Calentamiento previo de la JVM (*warmup*) de 30 segundos para permitir la compilación JIT y el llenado de buffers.
- **Medición efectiva:** Ingestión sostenida registrando throughput (ops/seg) y latencias percentilares (p50, p95, p99).

---

## 4. Registro de Evidencia Empírica de Rendimiento

> **Instrucciones para el Evaluador y el Equipo:**
> Los campos delimitados con corchetes `[ ... ]` corresponden a los registros que deben completarse con la salida real obtenida tras ejecutar `./scripts/rendimiento.sh` en la máquina anfitriona. No se introducen valores simulados para no falsear la medición técnica.

### 4.1. Ficha Técnica del Entorno de Prueba
- **Fecha y Hora de Ejecución:** `[ Registrar fecha y hora exacta, ej: 2026-09-24 11:30:00 ]`
- **Versión Observada de Cassandra (`SHOW VERSION`):** `[ Registrar salida exacta de versión, ej: Cassandra 5.0.0 / CQL spec 3.4.7 / Native protocol v5 ]`
- **Sistema Operativo Host:** `[ Registrar OS host, ej: macOS 15.0 Apple Silicon M-Series / Linux Kernel 6.x ]`
- **Recursos Asignados al Contenedor Docker:**
  - CPUs asignadas: `[ ej: 4 vCPUs ]`
  - Memoria RAM asignada: `[ ej: 6 GB RAM ]`
  - Parámetros de JVM Heap (MAX_HEAP_SIZE): `[ ej: 2048M ]`
  - Tipo de Almacenamiento: `[ ej: SSD NVMe local sobre ~/docker/data/cassandra ]`

### 4.2. Resultados Obtenidos de Throughput y Latencia

| Métrica Evaluada | Objetivo Teórico | Resultado Observado en el Ambiente | Cumplimiento |
| :--- | :--- | :--- | :--- |
| **Throughput de Escritura (Promedio)** | **10.000 ops/seg** | `[ COMPLETAR: ej. XXXX ops/seg ]` | `[ SÍ / PARCIAL / LIMITADO POR HARDWARE ]` |
| **Throughput Pico Registrado** | N/A | `[ COMPLETAR: ej. XXXX ops/seg ]` | N/A |
| **Latencia Percentil 50 (Mediana)** | $< 5\text{ ms}$ | `[ COMPLETAR: ej. X.X ms ]` | `[ COMPLETAR ]` |
| **Latencia Percentil 95 (p95)** | $< 15\text{ ms}$ | `[ COMPLETAR: ej. X.X ms ]` | `[ COMPLETAR ]` |
| **Latencia Percentil 99 (p99)** | $< 30\text{ ms}$ | `[ COMPLETAR: ej. X.X ms ]` | `[ COMPLETAR ]` |
| **Tasa de Errores / Timeouts** | $0\%$ | `[ COMPLETAR: ej. 0.0% ]` | `[ COMPLETAR ]` |

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
