#!/bin/bash
# ==============================================================================
# Script: scripts/agregaciones.sh
# Proposito: Ejecutar el catalogo de agregaciones temporales por semantica (RF5, RF9)
#            y materializar el downsampling por minuto desde tracking_jugador
#            (base en_vivo) hacia tracking_resumen_minuto (base resumen).
# Requisitos: InfluxDB 3 en ejecucion, datos cargados, token en .influxdb3-token.
# Orden de ejecucion: 5 (quinto paso de la Fase 2).
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TOKEN_FILE="${MODULE_DIR}/.influxdb3-token"
TEMP_DOWNSAMPLE_CSV="/tmp/downsample_raw_$$.csv"
TEMP_DOWNSAMPLE_LP="/tmp/downsample_$$.lp"

if [ ! -f "${TOKEN_FILE}" ]; then
    echo "ERROR: Archivo .influxdb3-token no encontrado."
    exit 1
fi

TOKEN=$(cat "${TOKEN_FILE}" | tr -d '\r\n ')

cleanup() {
    rm -f "${TEMP_DOWNSAMPLE_CSV}" "${TEMP_DOWNSAMPLE_LP}"
}
trap cleanup EXIT

ejecutar_sql() {
    local base="$1"
    local sql="$2"
    # encontrado en documentacion InfluxDB (comando: influxdb3 query --database <db> <sql>)
    docker compose -f "${MODULE_DIR}/docker-compose.yml" exec -T influxdb \
        influxdb3 query --database "${base}" "${sql}" --token "${TOKEN}"
}

echo "=============================================================================="
echo "CATALOGO DE AGREGACIONES TEMPORALES POR SEMANTICA (RF5, RF9)"
echo "=============================================================================="

# ------------------------------------------------------------------------------
# 1. Agregacion de Muestras Instantaneas (AVG, MAX)
# ------------------------------------------------------------------------------
echo ""
echo "=== [1/4] Agregacion de Muestras (AVG y MAX en velocidad y posesion) ==="
echo "Justificacion: Las muestras instantaneas no se suman (SUM distorsionaria la magnitud fisica)."
ejecutar_sql "fixture2030_en_vivo" "
SELECT jugador_id,
       ROUND(AVG(velocidad_kmh), 2) AS vel_promedio_kmh,
       ROUND(MAX(velocidad_kmh), 2) AS vel_maxima_kmh
FROM tracking_jugador
WHERE partido_id = 'P-001'
  AND time >= '2030-06-08T13:00:00'
  AND time <= '2030-06-08T13:15:00'
GROUP BY jugador_id
ORDER BY vel_maxima_kmh DESC
LIMIT 5;
"

# ------------------------------------------------------------------------------
# 2. Agregacion de Contadores Acumulados (MAX, MAX - MIN)
# ------------------------------------------------------------------------------
echo ""
echo "=== [2/4] Agregacion de Contadores Acumulados (MAX y delta de ventana) ==="
echo "Justificacion: distancia_acum_m y tiros_acumulados son contadores monotonos; SUM inflaria exponencialmente."
ejecutar_sql "fixture2030_en_vivo" "
SELECT jugador_id,
       ROUND(MAX(distancia_acum_m) - MIN(distancia_acum_m), 2) AS distancia_recorrida_ventana_m,
       ROUND(MAX(distancia_acum_m), 2) AS odometro_total_partido_m
FROM tracking_jugador
WHERE partido_id = 'P-001'
  AND equipo_id = 'URU'
  AND time >= '2030-06-08T13:00:00'
  AND time <= '2030-06-08T13:30:00'
GROUP BY jugador_id
LIMIT 5;
"

# ------------------------------------------------------------------------------
# 3. Agregacion de Metricas de Intervalo y Gauges
# ------------------------------------------------------------------------------
echo ""
echo "=== [3/4] Agregacion de Intervalos (SUM pases) y Gauges (MAX/AVG usuarios) ==="
echo "Justificacion: pases_intervalo es un delta de 5s (SUM acumula el total); usuarios es un gauge instantaneo."
ejecutar_sql "fixture2030_resumen" "
SELECT equipo_id,
       SUM(pases_intervalo) AS pases_totales_primer_tiempo
FROM estadisticas_partido
WHERE partido_id = 'P-001'
  AND time >= '2030-06-08T13:00:00'
  AND time <= '2030-06-08T13:45:00'
GROUP BY equipo_id;
"

# ------------------------------------------------------------------------------
# 4. Proceso de Downsampling a Base Resumen (1 s -> 1 min)
# ------------------------------------------------------------------------------
echo ""
echo "=============================================================================="
echo "PROCESO DE DOWNSAMPLING (fixture2030_en_vivo -> fixture2030_resumen)"
echo "=============================================================================="
echo "Extrayendo agregados por minuto de tracking_jugador para el partido P-001..."

# Consulta SQL con date_bin a 1 minuto exportada a CSV
# encontrado en documentacion InfluxDB (opcion --format csv en influxdb3 query)
docker compose -f "${MODULE_DIR}/docker-compose.yml" exec -T influxdb \
    influxdb3 query --database fixture2030_en_vivo "
SELECT date_bin(INTERVAL '1 minute', time) AS time,
       partido_id,
       equipo_id,
       jugador_id,
       ROUND(AVG(velocidad_kmh), 2) AS velocidad_prom,
       ROUND(MAX(velocidad_kmh), 2) AS velocidad_max,
       ROUND(MAX(distancia_acum_m) - MIN(distancia_acum_m), 2) AS distancia_minuto_m
FROM tracking_jugador
WHERE partido_id = 'P-001'
  AND time >= '2030-06-08T13:00:00'
  AND time <= '2030-06-08T14:30:00'
GROUP BY date_bin(INTERVAL '1 minute', time), partido_id, equipo_id, jugador_id
ORDER BY time ASC, jugador_id ASC
" --format csv --token "${TOKEN}" > "${TEMP_DOWNSAMPLE_CSV}"

echo "Transformando agregados a Line Protocol para fixture2030_resumen..."
# encontrado en documentacion Python (conversion de CSV a Line Protocol con epoch)
python3 -c "
import csv
from datetime import datetime, timezone

csv_in = '${TEMP_DOWNSAMPLE_CSV}'
lp_out = '${TEMP_DOWNSAMPLE_LP}'

with open(csv_in, 'r', encoding='utf-8') as f_in, open(lp_out, 'w', encoding='utf-8') as f_out:
    reader = csv.DictReader(f_in)
    count = 0
    for row in reader:
        time_str = row['time']
        # Convertir ISO a timestamp en segundos
        dt = datetime.fromisoformat(time_str).replace(tzinfo=timezone.utc)
        ts_sec = int(dt.timestamp())
        
        lp = (
            f\"tracking_resumen_minuto,partido_id={row['partido_id']},equipo_id={row['equipo_id']},jugador_id={row['jugador_id']} \"
            f\"velocidad_prom={row['velocidad_prom']},velocidad_max={row['velocidad_max']},distancia_minuto_m={row['distancia_minuto_m']} {ts_sec}\n\"
        )
        f_out.write(lp)
        count += 1
    print(f'Puntos agregados generados para downsampling: {count}')
"

echo "Ingestando tracking_resumen_minuto en la base fixture2030_resumen..."
curl -s -o /dev/null -w "Respuesta HTTP ingesta downsampling: %{http_code}\n" -X POST \
    "http://127.0.0.1:8181/api/v2/write?bucket=fixture2030_resumen&precision=s" \
    -H "Authorization: Token ${TOKEN}" \
    --data-binary @"${TEMP_DOWNSAMPLE_LP}"

echo ""
echo "Verificando puntos persistidos en la tabla downsampleada 'tracking_resumen_minuto' (base resumen):"
ejecutar_sql "fixture2030_resumen" "
SELECT time, jugador_id, velocidad_prom, velocidad_max, distancia_minuto_m
FROM tracking_resumen_minuto
WHERE partido_id = 'P-001' AND jugador_id = 'URU-1'
ORDER BY time ASC
LIMIT 5;
"

echo ""
echo "=== Agregaciones y Downsampling completados con exito ==="
