# Hito 12 — Pruebas de carga y optimización del Fixture 2030

Experimento HTTP real sobre `GET /fixture` con FastAPI, MongoDB y Redis. Se compara la configuración existente (caché de 5 s) con una variante de laboratorio de 15 s para consultas previas al partido. Las cifras se generan a partir de archivos crudos; no se usan resultados ilustrativos de las clases.

- [Conclusiones y decisión](docs/conclusiones.md).
- [Escenario y método](docs/flujo_y_escenario_de_carga.md).
- [Línea base](docs/linea_base.md).
- [Hipótesis, cambio y costo](docs/hipotesis_y_optimizacion.md).
- [Resultados medidos antes/después](docs/comparacion_antes_despues.md).
- [Propuesta y prototipo de Data Mart](docs/integracion_data_mart.md).
- [Alternativa relacional conceptual](docs/comparacion_relacional.md).
- [Integridad, limitaciones y trazabilidad](docs/integridad_y_limitaciones.md).

## Resultado de esta entrega

18 corridas con 14.468 respuestas correctas medidas, 0 errores y conservación de los 127 partidos. Cambiar TTL de 5 a 15 s redujo las consultas MongoDB de 195 a 57 (70,8%). El p99 empeoró con 1 y 10 lectores; la mayor antigüedad de caché se comprobó en las pruebas de actualización. La variante de 15 s se limita al experimento previo al partido, y el backend conserva 5 s por defecto.

Validación adicional: 123 tests unitarios del backend, 6 de integración real y 6 del Data Mart; control negativo del generador y auditoría de las 18 corridas aprobados. Ver [validación final](docs/validacion_final.md).

## Requisitos y versiones

Python 3.12 con las dependencias de `requirements.lock` del backend, Docker Compose, Java 21 y Apache JMeter 5.6.3. No se necesitan Cassandra, Neo4j, InfluxDB ni IRIS en ejecución para este flujo. El backend conserva sus seis módulos; sólo se somete a carga uno de los flujos existentes.

El backend de trabajo está en [manumam/idd-2-backend](https://github.com/manumam/idd-2-backend). Como la medición parte de un checkout con cambios locales, `evidencia/backend-source.tar.gz` conserva **la fuente exacta necesaria**, incluyendo el seed y los CSV. `source_manifest.json` identifica commit de origen, modificaciones y SHA-256 por archivo; la copia no contiene `.env`, `.git`, entornos virtuales ni datos de otros laboratorios.

Revisar `evidencia/environment.json` para hardware, Docker y versiones observadas. El override `compose.lock.yaml` fija las imágenes observadas para arm64; en otra arquitectura hay que registrar la imagen compatible y declarar la diferencia de entorno. El checksum SHA-512 oficial de JMeter está en `evidencia/jmeter-5.6.3.sha512`. No se versiona su distribución de 83 MB.

## Preparación desde la copia medida

Desde la raíz de este repositorio, extraer el backend en una ubicación de laboratorio vacía. Los comandos de ejemplo lo sitúan en `/tmp/hito12-repro`:

```bash
mkdir -p /tmp/hito12-repro
tar -xzf hito-12/evidencia/backend-source.tar.gz -C /tmp/hito12-repro
python3.12 -m venv /tmp/hito12-repro/idd-2-backend/.venv
/tmp/hito12-repro/idd-2-backend/.venv/bin/python -m pip install \
  -r /tmp/hito12-repro/idd-2-backend/requirements.lock
```

También se puede usar el checkout original mediante `--backend`; el orquestador verifica que su fuente coincida con el manifiesto de la evidencia seleccionada. No usar un backend con `.env` de producción: el laboratorio usa configuración local propia. Los puertos 57017, 56379 y 58000 deben estar libres.

JMeter se puede extraer en `/tmp`, sin instalación global, desde la distribución de Apache:

```bash
curl --fail --location https://archive.apache.org/dist/jmeter/binaries/apache-jmeter-5.6.3.tgz \
  -o /tmp/apache-jmeter-5.6.3.tgz
curl --fail --location https://archive.apache.org/dist/jmeter/binaries/apache-jmeter-5.6.3.tgz.sha512 \
  -o /tmp/apache-jmeter-5.6.3.tgz.sha512
cd /tmp
shasum -a 512 -c apache-jmeter-5.6.3.tgz.sha512
tar -xzf apache-jmeter-5.6.3.tgz
# Volver a la raíz de este repositorio antes de continuar.
```

## Ejecutar el experimento

Todos los comandos siguientes se ejecutan desde la raíz del repositorio de la materia. `H12_BACKEND` es una variable de este experimento; ajustar su valor si se usa otro checkout.

```bash
export H12_BACKEND=/tmp/hito12-repro/idd-2-backend
export H12_PYTHON="$H12_BACKEND/.venv/bin/python"
docker compose -f hito-12/compose.yaml -f hito-12/compose.lock.yaml up -d
"$H12_PYTHON" hito-12/scripts/esperar_servicios.py --backend "$H12_BACKEND"

# Preparar y comprobar el generador, sin sobrescribir la evidencia entregada.
"$H12_PYTHON" hito-12/scripts/experimento.py pilot --backend "$H12_BACKEND" \
  --output /tmp/hito12-repro/resultados

# 9 corridas por versión; alrededor de 13 minutos por versión, incluido inicio/JVM.
"$H12_PYTHON" hito-12/scripts/experimento.py baseline --backend "$H12_BACKEND" \
  --output /tmp/hito12-repro/resultados

# Revisar los summary.json de la línea base y registrar la hipótesis antes del cambio.
"$H12_PYTHON" hito-12/scripts/experimento.py optimized --backend "$H12_BACKEND" \
  --output /tmp/hito12-repro/resultados
```

El argumento `--jmeter /ruta/bin/jmeter` cambia la ubicación del ejecutable. El programa inicia/cierra su propia API, hace recargas idempotentes del dataset, limpia sólo la clave de caché del laboratorio y conserva cada corrida por separado. No requiere tocar `.env`. No ejecutar dos orquestadores simultáneos sobre estos mismos puertos y clave.

Para regenerar las tablas de **la evidencia entregada**, sin ejecutar nueva carga:

```bash
"$H12_PYTHON" hito-12/scripts/comparar_resultados.py
"$H12_PYTHON" hito-12/scripts/cerrar_informe.py
```

Para generar tablas de una reproducción en otra carpeta:

```bash
"$H12_PYTHON" hito-12/scripts/comparar_resultados.py \
  --evidence /tmp/hito12-repro/resultados --docs /tmp/hito12-repro/informe
```

Las corridas ya terminadas con `summary.json` se omiten al reanudar. Una corrida incompleta se conserva para diagnóstico: mover esa carpeta a otro nombre antes de repetirla. No mezclar corridas de escenarios o fuentes diferentes en la misma carpeta de salida.

## Integridad y análisis fuera de la carga

Ejecutar cuando el orquestador haya terminado, para que los controles de recarga e invalidación no interfieran con la medición:

```bash
"$H12_PYTHON" hito-12/scripts/diagnostico.py --backend "$H12_BACKEND"
"$H12_PYTHON" hito-12/scripts/validar_frescura.py --backend "$H12_BACKEND"
"$H12_PYTHON" hito-12/scripts/data_mart.py --backend "$H12_BACKEND"
"$H12_PYTHON" hito-12/scripts/test_data_mart.py -v
"$H12_PYTHON" hito-12/scripts/verificar_generador.py --output /tmp/hito12-repro/generador_negativo
"$H12_PYTHON" hito-12/scripts/verificar_entrega.py
```

Estos comandos escriben sus controles en `hito-12/evidencia/`; para conservar la entrega original, trabajar en una copia del repositorio. El Data Mart es un prototipo local por lotes ejecutado manualmente, no un servicio programado.

## Detener y limpiar

```bash
# Conserva todos los datos y volúmenes.
docker compose -f hito-12/compose.yaml -f hito-12/compose.lock.yaml stop

# Opcional, con el laboratorio iniciado: elimina sólo partidos de fixture2030_hito12
# y la clave fixture:v1:todos del Redis exclusivo en 56379.
"$H12_PYTHON" hito-12/scripts/experimento.py clean --backend "$H12_BACKEND"
```

No se usa `down -v`, `FLUSHALL` ni borrados generales. Ctrl+C permite interrumpir el orquestador: su bloque `finally` detiene API/JMeter; los resultados parciales quedan identificados por ausencia de resumen. Los recursos están acotados en `compose.yaml` y en la duración/concurrencia del generador.

## Qué aportan las clases

La Clase 13 adjunta aporta benchmarking, latencia, percentiles, throughput, errores, recursos y familias de optimización. Los números típicos de sus diapositivas no se trasladan al informe. La Clase 14 aporta conceptos de observabilidad; sus requisitos de Prometheus, Grafana y tres fuentes corresponden al Hito 13 y no se agregan a esta entrega. El Data Mart y la comparación relacional se desarrollan siguiendo las secciones 5.6 y 5.7 del PDF del Hito 12.
