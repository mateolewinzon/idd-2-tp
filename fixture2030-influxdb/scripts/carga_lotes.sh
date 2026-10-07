#!/bin/bash
# ==============================================================================
# Script: scripts/carga_lotes.sh
# Proposito: Cargar masivamente los archivos Line Protocol (.lp) en InfluxDB 3
#            en lotes fijos de 10.000 lineas, con precision en segundos (s).
#            Ejecuta primero una prueba de humo con 1 partido y luego la carga total.
# Requisitos: InfluxDB 3 en ejecucion, token en .influxdb3-token, archivos .lp en data/lp/
# Orden de ejecucion: 3 (tercer paso de la Fase 2).
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TOKEN_FILE="${MODULE_DIR}/.influxdb3-token"
LP_DIR="${MODULE_DIR}/data/lp"
LOG_RECHAZADAS="${MODULE_DIR}/data/lineas_rechazadas.log"
CHUNK_DIR="/tmp/influx_chunks_$$"
LOTE_TAMANO=10000

if [ ! -f "${TOKEN_FILE}" ]; then
    echo "ERROR: Archivo .influxdb3-token no encontrado. Ejecute scripts/inicializacion.sh primero."
    exit 1
fi

TOKEN=$(cat "${TOKEN_FILE}" | tr -d '\r\n ')

if [ ! -d "${LP_DIR}" ]; then
    echo "ERROR: Directorio ${LP_DIR} no encontrado. Ejecute scripts/generacion_puntos.py primero."
    exit 1
fi

mkdir -p "${CHUNK_DIR}"
rm -f "${LOG_RECHAZADAS}"
touch "${LOG_RECHAZADAS}"

cleanup() {
    rm -rf "${CHUNK_DIR}"
}
trap cleanup EXIT

# ==============================================================================
# Funcion de Ingesta por Archivo en Lotes de 10.000 Lineas
# ==============================================================================
# encontrado en documentacion InfluxDB (endpoint nativo POST /api/v3/write_lp?db=<base>&precision=second)
cargar_archivo_lp() {
    local archivo="$1"
    local base_destino="$2"
    local nombre_archivo
    nombre_archivo=$(basename "${archivo}")

    # Dividir el archivo en lotes de 10.000 lineas (DEFAULT acordado)
    rm -rf "${CHUNK_DIR:?}"/*
    split -l "${LOTE_TAMANO}" "${archivo}" "${CHUNK_DIR}/chunk_"

    for chunk in "${CHUNK_DIR}"/chunk_*; do
        [ -f "${chunk}" ] || continue
        local intento=1
        local max_intentos=3
        local exito=0

        while [ "${intento}" -le "${max_intentos}" ]; do
            # Ingesta HTTP con precision en segundos (s)
            HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
                "http://127.0.0.1:8181/api/v3/write_lp?db=${base_destino}&precision=second" \
                -H "Authorization: Bearer ${TOKEN}" \
                --data-binary @"${chunk}")

            if [ "${HTTP_STATUS}" -eq 204 ]; then
                exito=1
                break
            else
                echo "AVISO: Intento ${intento} fallo con HTTP ${HTTP_STATUS} en ${nombre_archivo}. Reintentando..."
                sleep 1
                intento=$((intento + 1))
            fi
        done

        if [ "${exito}" -ne 1 ]; then
            echo "ERROR: Lote rechazado permanentemente en ${nombre_archivo} tras ${max_intentos} intentos (HTTP ${HTTP_STATUS})."
            echo "--- Chunk rechazado de ${nombre_archivo} ---" >> "${LOG_RECHAZADAS}"
            cat "${chunk}" >> "${LOG_RECHAZADAS}"
        fi
    done
}

# ==============================================================================
# 1. Prueba de Humo (1 Partido: P-001)
# ==============================================================================
echo "=== [1/2] Iniciando Prueba de Humo: 1 Partido (P-001) ==="
T_INICIO_HUMO=$(date +%s)

echo "-> Cargando tracking_pelota_P-001.lp en fixture2030_en_vivo..."
cargar_archivo_lp "${LP_DIR}/tracking_pelota_P-001.lp" "fixture2030_en_vivo"

echo "-> Cargando tracking_jugador_P-001.lp en fixture2030_en_vivo..."
cargar_archivo_lp "${LP_DIR}/tracking_jugador_P-001.lp" "fixture2030_en_vivo"

echo "-> Cargando estadisticas_partido_P-001.lp en fixture2030_resumen..."
cargar_archivo_lp "${LP_DIR}/estadisticas_partido_P-001.lp" "fixture2030_resumen"

echo "-> Cargando actividad_usuarios_P-001.lp en fixture2030_resumen..."
cargar_archivo_lp "${LP_DIR}/actividad_usuarios_P-001.lp" "fixture2030_resumen"

T_FIN_HUMO=$(date +%s)
DURACION_HUMO=$((T_FIN_HUMO - T_INICIO_HUMO))
echo "Prueba de humo completada con exito en ${DURACION_HUMO} s."

# ==============================================================================
# 2. Carga Masiva Completa (Restantes 126 Partidos)
# ==============================================================================
echo ""
echo "=== [2/2] Iniciando Carga Masiva Completa (Torneo Completo) ==="
T_INICIO_TOTAL=$(date +%s)

# Listar todos los archivos excluyendo P-001 ya cargado
total_partidos=127
partido_num=2

for pid in $(seq -f "P-%03g" 2 "${total_partidos}"); do
    echo -ne "Procesando partido ${partido_num}/${total_partidos} (${pid})...\r"

    [ -f "${LP_DIR}/tracking_pelota_${pid}.lp" ] && \
        cargar_archivo_lp "${LP_DIR}/tracking_pelota_${pid}.lp" "fixture2030_en_vivo"

    [ -f "${LP_DIR}/tracking_jugador_${pid}.lp" ] && \
        cargar_archivo_lp "${LP_DIR}/tracking_jugador_${pid}.lp" "fixture2030_en_vivo"

    [ -f "${LP_DIR}/estadisticas_partido_${pid}.lp" ] && \
        cargar_archivo_lp "${LP_DIR}/estadisticas_partido_${pid}.lp" "fixture2030_resumen"

    [ -f "${LP_DIR}/actividad_usuarios_${pid}.lp" ] && \
        cargar_archivo_lp "${LP_DIR}/actividad_usuarios_${pid}.lp" "fixture2030_resumen"

    partido_num=$((partido_num + 1))
done

echo ""
T_FIN_TOTAL=$(date +%s)
DURACION_TOTAL=$((T_FIN_TOTAL - T_INICIO_TOTAL))

echo ""
echo "=== Resumen de Ingesta Masiva ==="
echo "Duracion total de carga: ${DURACION_TOTAL} segundos"
if [ -s "${LOG_RECHAZADAS}" ]; then
    echo "ATENCION: Se registraron lineas rechazadas en ${LOG_RECHAZADAS}"
else
    echo "Lineas rechazadas: 0 (Carga limpia al 100%)"
fi
