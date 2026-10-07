#!/bin/bash
# ==============================================================================
# Script: scripts/validacion.sh
# Proposito: Validar exhaustivamente la integridad del almacenamiento en InfluxDB 3.
#            Verifica conteos de puntos efectivos por tabla vs lo proyectado/generado,
#            cardinalidad de series observadas vs estimadas en Fase 0/1, rangos temporales
#            y tipos de datos. Falla ruidosamente con exit code 1 ante discrepancias.
# Requisitos: InfluxDB 3 en ejecucion, datos cargados, token en .influxdb3-token.
# Orden de ejecucion: 6 (sexto paso de la Fase 2).
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

consultar_escalar() {
    local base="$1"
    local sql="$2"
    # encontrado en documentacion InfluxDB (consulta SQL con formato CSV extrayendo la fila de datos con awk)
    docker compose -f "${MODULE_DIR}/docker-compose.yml" exec -T influxdb \
        influxdb3 query --database "${base}" "${sql}" --format csv --token "${TOKEN}" | awk 'NR==2 {print $1}' | tr -d '\r\n'
}

echo "=============================================================================="
echo "AUDITORIA DE INTEGRIDAD Y VALIDACION — MUNDIAL 2030 (INFLUXDB 3)"
echo "=============================================================================="

ERRORES=0

# ------------------------------------------------------------------------------
# 1. Validacion de Conteos de Puntos por Tabla
# ------------------------------------------------------------------------------
echo ""
echo "=== [1/4] Validacion de Puntos Efectivos vs Estimacion ==="

PUNTOS_JUGADOR=$(consultar_escalar "fixture2030_en_vivo" "SELECT count(*) FROM tracking_jugador")
PUNTOS_PELOTA=$(consultar_escalar "fixture2030_en_vivo" "SELECT count(*) FROM tracking_pelota")
PUNTOS_ESTADISTICAS=$(consultar_escalar "fixture2030_resumen" "SELECT count(*) FROM estadisticas_partido")
PUNTOS_USUARIOS=$(consultar_escalar "fixture2030_resumen" "SELECT count(*) FROM actividad_usuarios")

ESPERADO_JUGADOR=15087600
ESPERADO_PELOTA_MIN=685800  # 685800 del fixture (+ puntos de tests de conectividad/dato tardio)
ESPERADO_ESTADISTICAS=274320
ESPERADO_USUARIOS=822960

echo "1.1 tracking_jugador (base en_vivo):"
echo "    Observado: ${PUNTOS_JUGADOR} | Esperado: ${ESPERADO_JUGADOR}"
if [ "${PUNTOS_JUGADOR}" -ne "${ESPERADO_JUGADOR}" ]; then
    echo "    [FALLO] El conteo de tracking_jugador no coincide con lo esperado."
    ERRORES=$((ERRORES + 1))
else
    echo "    [OK] Coincidencia exacta al 100%."
fi

echo "1.2 tracking_pelota (base en_vivo):"
echo "    Observado: ${PUNTOS_PELOTA} | Esperado: >= ${ESPERADO_PELOTA_MIN}"
if [ "${PUNTOS_PELOTA}" -lt "${ESPERADO_PELOTA_MIN}" ]; then
    echo "    [FALLO] El conteo de tracking_pelota es menor al esperado."
    ERRORES=$((ERRORES + 1))
else
    echo "    [OK] Puntos completos (incluye validacion de dato tardio y test)."
fi

echo "1.3 estadisticas_partido (base resumen):"
echo "    Observado: ${PUNTOS_ESTADISTICAS} | Esperado: ${ESPERADO_ESTADISTICAS}"
if [ "${PUNTOS_ESTADISTICAS}" -ne "${ESPERADO_ESTADISTICAS}" ]; then
    echo "    [FALLO] El conteo de estadisticas_partido no coincide con lo esperado."
    ERRORES=$((ERRORES + 1))
else
    echo "    [OK] Coincidencia exacta al 100%."
fi

echo "1.4 actividad_usuarios (base resumen):"
echo "    Observado: ${PUNTOS_USUARIOS} | Esperado: ${ESPERADO_USUARIOS}"
if [ "${PUNTOS_USUARIOS}" -ne "${ESPERADO_USUARIOS}" ]; then
    echo "    [FALLO] El conteo de actividad_usuarios no coincide con lo esperado."
    ERRORES=$((ERRORES + 1))
else
    echo "    [OK] Coincidencia exacta al 100%."
fi

TOTAL_PUNTOS=$((PUNTOS_JUGADOR + PUNTOS_PELOTA + PUNTOS_ESTADISTICAS + PUNTOS_USUARIOS))
echo ""
echo "Volumen total de observaciones verificado: ${TOTAL_PUNTOS} puntos."
if [ "${TOTAL_PUNTOS}" -lt 10000000 ]; then
    echo "[FALLO CRITICO] El volumen total es menor al objetivo de 10M puntos."
    ERRORES=$((ERRORES + 1))
else
    echo "[OK] Volumen total supera con creces el piso de 10 millones de puntos."
fi

# ------------------------------------------------------------------------------
# 2. Validacion de Cardinalidad y Series Temporales por Tabla
# ------------------------------------------------------------------------------
echo ""
echo "=== [2/4] Validacion de Cardinalidad de Series Temporales ==="

SERIES_JUGADOR=$(consultar_escalar "fixture2030_en_vivo" "SELECT count(*) FROM (SELECT DISTINCT partido_id, jugador_id, equipo_id FROM tracking_jugador)")
SERIES_PELOTA=$(consultar_escalar "fixture2030_en_vivo" "SELECT count(DISTINCT partido_id) FROM tracking_pelota WHERE partido_id LIKE 'P-%'")
SERIES_ESTADISTICAS=$(consultar_escalar "fixture2030_resumen" "SELECT count(*) FROM (SELECT DISTINCT partido_id, equipo_id, sede_id FROM estadisticas_partido)")
SERIES_USUARIOS=$(consultar_escalar "fixture2030_resumen" "SELECT count(*) FROM (SELECT DISTINCT partido_id, region FROM actividad_usuarios)")

echo "2.1 Series tracking_jugador:     ${SERIES_JUGADOR} (Estimado: 2.794)"
echo "2.2 Series tracking_pelota:      ${SERIES_PELOTA} (Estimado: 127)"
echo "2.3 Series estadisticas_partido: ${SERIES_ESTADISTICAS} (Estimado: 254)"
echo "2.4 Series actividad_usuarios:   ${SERIES_USUARIOS} (Estimado: 762)"

if [ "${SERIES_JUGADOR}" -ne 2794 ] || [ "${SERIES_PELOTA}" -ne 127 ] || \
   [ "${SERIES_ESTADISTICAS}" -ne 254 ] || [ "${SERIES_USUARIOS}" -ne 762 ]; then
    echo "[FALLO] La cardinalidad de series discrepa con el calculo teorico derivado de los CSV."
    ERRORES=$((ERRORES + 1))
else
    echo "[OK] Cardinalidad exacta: 3.937 series del torneo mundial."
fi

# ------------------------------------------------------------------------------
# 3. Validacion de Rangos Temporales y Cobertura de Partidos
# ------------------------------------------------------------------------------
echo ""
echo "=== [3/4] Validacion de Rango Temporal y Cobertura de Partidos ==="

FECHA_MIN=$(consultar_escalar "fixture2030_resumen" "SELECT min(time) FROM estadisticas_partido")
FECHA_MAX=$(consultar_escalar "fixture2030_resumen" "SELECT max(time) FROM estadisticas_partido")
PARTIDOS_DISTINTOS=$(consultar_escalar "fixture2030_resumen" "SELECT count(DISTINCT partido_id) FROM estadisticas_partido")

echo "3.1 Primer timestamp registrado: ${FECHA_MIN}"
echo "3.2 Ultimo timestamp registrado: ${FECHA_MAX}"
echo "3.3 Partidos cubiertos:          ${PARTIDOS_DISTINTOS} / 127"

if [ "${PARTIDOS_DISTINTOS}" -ne 127 ]; then
    echo "[FALLO] Cobertura incompleta de partidos."
    ERRORES=$((ERRORES + 1))
else
    echo "[OK] Cobertura completa del fixture oficial (127 partidos)."
fi

# ------------------------------------------------------------------------------
# 4. Validacion de Tipos de Datos y Rangos Fisicos
# ------------------------------------------------------------------------------
echo ""
echo "=== [4/4] Validacion de Tipos y Rangos Fisicos Plausibles ==="

VEL_MAX_JUG=$(consultar_escalar "fixture2030_en_vivo" "SELECT max(velocidad_kmh) FROM tracking_jugador")
DIST_MAX_JUG=$(consultar_escalar "fixture2030_en_vivo" "SELECT max(distancia_acum_m) FROM tracking_jugador")
ALTURA_MAX_PEL=$(consultar_escalar "fixture2030_en_vivo" "SELECT max(z_m) FROM tracking_pelota")

echo "4.1 Velocidad maxima de jugador observada: ${VEL_MAX_JUG} km/h (esperado: <= 36.0)"
echo "4.2 Odometro maximo acumulado observado:  ${DIST_MAX_JUG} m (esperado: >= 15000 y <= 30000)"
echo "4.3 Altura maxima de pelota observada:     ${ALTURA_MAX_PEL} m (esperado: <= 15.0)"

# Compara con awk (decimales) y suma un error si el rango no se cumple
verificar_rango() {
    local etiqueta="$1" valor="$2" minimo="$3" maximo="$4"
    if awk -v v="${valor}" -v a="${minimo}" -v b="${maximo}" 'BEGIN{exit !(v>=a && v<=b)}'; then
        echo "    [OK] ${etiqueta} dentro de rango."
    else
        echo "    [FALLO] ${etiqueta} fuera de rango (${valor})."
        ERRORES=$((ERRORES + 1))
    fi
}
verificar_rango "Velocidad maxima" "${VEL_MAX_JUG}" 0 36
verificar_rango "Odometro maximo" "${DIST_MAX_JUG}" 15000 30000
verificar_rango "Altura maxima" "${ALTURA_MAX_PEL}" 0 15

echo ""
echo "=============================================================================="
if [ "${ERRORES}" -eq 0 ]; then
    echo "RESULTADO FINAL: TODAS LAS VALIDACIONES SUPERADAS EXITOSAMENTE (0 ERRORES)"
    echo "=============================================================================="
    exit 0
else
    echo "RESULTADO FINAL: SE ENCONTRARON ${ERRORES} DISCREPANCIAS EN LA AUDITORIA"
    echo "=============================================================================="
    exit 1
fi
