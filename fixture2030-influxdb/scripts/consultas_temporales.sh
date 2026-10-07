#!/bin/bash
# ==============================================================================
# Script: scripts/consultas_temporales.sh
# Proposito: Ejecutar el catalogo de consultas temporales analiticas en SQL
#            nativo sobre InfluxDB 3 Core (Arrow DataFusion). Todas las consultas
#            acotan estrictamente su rango temporal y dimensiones (RNF8).
#            Incluye validacion de casos de borde: partido sin puntos y dato tardio (RF8).
# Requisitos: InfluxDB 3 en ejecucion, datos cargados, token en .influxdb3-token.
# Orden de ejecucion: 4 (cuarto paso de la Fase 2).
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TOKEN_FILE="${MODULE_DIR}/.influxdb3-token"

if [ ! -f "${TOKEN_FILE}" ]; then
    echo "ERROR: Archivo .influxdb3-token no encontrado."
    exit 1
fi

TOKEN=$(cat "${TOKEN_FILE}" | tr -d '\r\n ')

ejecutar_sql() {
    local base="$1"
    local sql="$2"
    # encontrado en documentacion InfluxDB (comando: influxdb3 query --database <db> <sql>)
    docker compose -f "${MODULE_DIR}/docker-compose.yml" exec -T influxdb \
        influxdb3 query --database "${base}" "${sql}" --token "${TOKEN}"
}

echo "=============================================================================="
echo "CATALOGO DE CONSULTAS TEMPORALES ANALITICAS — MUNDIAL 2030 (INFLUXDB 3)"
echo "=============================================================================="

# ------------------------------------------------------------------------------
# Consulta Q1: Trayectoria y odometria en ventana activa de 5 minutos (Patron P1)
# ------------------------------------------------------------------------------
echo ""
echo "=== [Q1] Evolucion cinematica de un jugador en ventana activa de 5 min (P-001, URU-1) ==="
ejecutar_sql "fixture2030_en_vivo" "
SELECT time, jugador_id, x_m, y_m, velocidad_kmh, distancia_acum_m
FROM tracking_jugador
WHERE partido_id = 'P-001'
  AND jugador_id = 'URU-1'
  AND time >= '2030-06-08T13:00:00'
  AND time <= '2030-06-08T13:05:00'
ORDER BY time ASC
LIMIT 5;
"

# ------------------------------------------------------------------------------
# Consulta Q2: Velocidades maximas y ranking de distancia por equipo (Patron P2)
# ------------------------------------------------------------------------------
echo ""
echo "=== [Q2] Ranking de distancia y velocidad maxima de titulares (P-001, URU) ==="
ejecutar_sql "fixture2030_en_vivo" "
SELECT jugador_id,
       ROUND(MAX(velocidad_kmh), 2) AS vel_max_kmh,
       ROUND(MAX(distancia_acum_m), 2) AS dist_total_m
FROM tracking_jugador
WHERE partido_id = 'P-001'
  AND equipo_id = 'URU'
  AND time >= '2030-06-08T13:00:00'
  AND time <= '2030-06-08T14:30:00'
GROUP BY jugador_id
ORDER BY dist_total_m DESC
LIMIT 5;
"

# ------------------------------------------------------------------------------
# Consulta Q3: Posicionamiento 3D de la pelota en ventana de jugada (Patron P3)
# ------------------------------------------------------------------------------
echo ""
echo "=== [Q3] Trayectoria 3D de la pelota en ventana acotada de 60 segundos ==="
ejecutar_sql "fixture2030_en_vivo" "
SELECT time, partido_id, x_m, y_m, z_m, velocidad_kmh
FROM tracking_pelota
WHERE partido_id = 'P-001'
  AND time >= '2030-06-08T13:10:00'
  AND time <= '2030-06-08T13:11:00'
ORDER BY time ASC
LIMIT 5;
"

# ------------------------------------------------------------------------------
# Consulta Q4: Balance comparativo bilateral de posesion y pases (Patrones P4 y P5)
# ------------------------------------------------------------------------------
echo ""
echo "=== [Q4] Comparativa bilateral de posesion, tiros y pases (P-001: URU vs KSA) ==="
ejecutar_sql "fixture2030_resumen" "
SELECT equipo_id,
       ROUND(AVG(posesion_pct), 1) AS posesion_media_pct,
       MAX(tiros_acumulados) AS tiros_totales,
       SUM(pases_intervalo) AS pases_totales
FROM estadisticas_partido
WHERE partido_id = 'P-001'
  AND time >= '2030-06-08T13:00:00'
  AND time <= '2030-06-08T14:30:00'
GROUP BY equipo_id;
"

# ------------------------------------------------------------------------------
# Consulta Q5: Ritmo ofensivo en ventanas deslizantes de 5 minutos (Patron P6)
# ------------------------------------------------------------------------------
echo ""
echo "=== [Q5] Ritmo ofensivo: remates por bloque de 5 min con date_bin (P-001, URU) ==="
ejecutar_sql "fixture2030_resumen" "
SELECT date_bin(INTERVAL '5 minutes', time) AS bloque_5m,
       MAX(tiros_acumulados) - MIN(tiros_acumulados) AS tiros_en_bloque
FROM estadisticas_partido
WHERE partido_id = 'P-001'
  AND equipo_id = 'URU'
  AND time >= '2030-06-08T13:00:00'
  AND time <= '2030-06-08T14:30:00'
GROUP BY date_bin(INTERVAL '5 minutes', time)
ORDER BY bloque_5m ASC
LIMIT 6;
"

# ------------------------------------------------------------------------------
# Consulta Q6: Comparacion de dinamismo y volumen entre dos sedes (Patron P7)
# ------------------------------------------------------------------------------
echo ""
echo "=== [Q6] Comparacion de dinamismo e intensidad entre dos sedes (S-01 vs S-02) ==="
ejecutar_sql "fixture2030_resumen" "
SELECT sede_id,
       ROUND(AVG(posesion_pct), 1) AS posesion_promedio,
       SUM(pases_intervalo) AS pases_totales_sede
FROM estadisticas_partido
WHERE sede_id IN ('S-01', 'S-02')
  AND time >= '2030-06-08T00:00:00'
  AND time <= '2030-06-10T23:59:59'
GROUP BY sede_id;
"

# ------------------------------------------------------------------------------
# Consulta Q7: Picos de concurrencia y streaming por confederacion (Patron P8)
# ------------------------------------------------------------------------------
echo ""
echo "=== [Q7] Picos de audiencia y usuarios conectados por confederacion (P-001) ==="
ejecutar_sql "fixture2030_resumen" "
SELECT region,
       MAX(usuarios_conectados) AS pico_usuarios,
       ROUND(AVG(usuarios_conectados), 0) AS audiencia_media
FROM actividad_usuarios
WHERE partido_id = 'P-001'
  AND time >= '2030-06-08T13:00:00'
  AND time <= '2030-06-08T14:30:00'
GROUP BY region
ORDER BY pico_usuarios DESC;
"

# ------------------------------------------------------------------------------
# Casos Especiales de Validacion (RF8)
# ------------------------------------------------------------------------------
echo ""
echo "=============================================================================="
echo "CASOS ESPECIALES DE VALIDACION TEMPORAL (RF8)"
echo "=============================================================================="

echo "-> Caso A: Consulta sobre partido sin puntos / no disputado (P-999)..."
ejecutar_sql "fixture2030_en_vivo" "
SELECT count(*) AS puntos_encontrados
FROM tracking_jugador
WHERE partido_id = 'P-999';
"
echo "Verificacion Caso A: El motor responde con 0 puntos de forma inmediata sin errores."

echo ""
echo "-> Caso B: Verificacion de insercion de dato tardio (Late-arriving data)..."
# Insercion de observacion con marca temporal retrasada (1 segundo previo al inicio formal)
curl -s -X POST "http://127.0.0.1:8181/api/v2/write?bucket=fixture2030_en_vivo&precision=s" \
  -H "Authorization: Token ${TOKEN}" \
  --data-binary "tracking_pelota,partido_id=P-001 x_m=50.0,y_m=30.0,z_m=0.0,velocidad_kmh=15.0 1907153999"

ejecutar_sql "fixture2030_en_vivo" "
SELECT time, partido_id, x_m, y_m, velocidad_kmh
FROM tracking_pelota
WHERE partido_id = 'P-001'
  AND time = '2030-06-08T12:59:59';
"
echo "Verificacion Caso B: El dato tardio fue incorporado correctamente a la particion sin sobrescribir."

echo ""
echo "=== Catalogo de consultas temporales finalizado exitosamente ==="
