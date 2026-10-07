#!/bin/bash
# ==============================================================================
# Script: scripts/inicializacion.sh
# Proposito: Inicializar el entorno Docker de InfluxDB 3 Core, gestionar el token
#            administrativo persistente y crear las bases de datos con su retencion.
# Requisitos: Docker daemon activo, carpeta ~/docker/data/influxdb con permisos.
# Orden de ejecucion: 1 (primer script de la Fase 2)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TOKEN_FILE="${MODULE_DIR}/.influxdb3-token"
HOST_DATA_DIR="${HOME}/docker/data/influxdb"
ADMIN_TOKEN_JSON="${HOST_DATA_DIR}/admin_token.json"

echo "=== [1/5] Gestionando token administrativo offline ==="
# encontrado en documentacion InfluxDB (comando: influxdb3 create token --admin --offline)
# En InfluxDB 3 Core, el token inicial de admin se crea offline antes del arranque inicial
# del catalogo y se carga al servidor mediante la variable INFLUXDB3_ADMIN_TOKEN_FILE.
mkdir -p "${HOST_DATA_DIR}"

if [ ! -f "${ADMIN_TOKEN_JSON}" ]; then
    echo "Generando token administrativo offline..."
    docker run --rm -v "${HOST_DATA_DIR}:/var/lib/influxdb3" influxdb:3-core \
        influxdb3 create token --admin --offline --output-file /var/lib/influxdb3/admin_token.json >/dev/null
fi

TOKEN=$(python3 -c "import json; print(json.load(open('${ADMIN_TOKEN_JSON}'))['token'])")
echo -n "${TOKEN}" > "${TOKEN_FILE}"
chmod 600 "${TOKEN_FILE}"
echo "Token administrativo disponible en .influxdb3-token (protegido fuera de git)."

echo "=== [2/5] Levantando servicio InfluxDB 3 Core con Docker Compose ==="
cd "${MODULE_DIR}"
docker compose up -d

echo "=== [3/5] Esperando a que el servicio este listo en el puerto 8181 ==="
MAX_RETRIES=30
RETRY_COUNT=0
# Comprobar la respuesta HTTP real en el puerto 8181 (evita error transitorio de conexión)
until docker compose exec -T influxdb influxdb3 show databases --token "${TOKEN}" >/dev/null 2>&1; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ "${RETRY_COUNT}" -ge "${MAX_RETRIES}" ]; then
        echo "ERROR: Tiempo de espera agotado para InfluxDB 3."
        docker compose logs
        exit 1
    fi
    sleep 1
done

echo "Servicio disponible. Version observada:"
docker compose exec -T influxdb influxdb3 --version

echo "=== [4/5] Creando base de datos 'fixture2030_en_vivo' (retencion 7d) ==="
# encontrado en documentacion InfluxDB (comando: influxdb3 create database <name> --retention-period <val>)
if docker compose exec -T influxdb influxdb3 show databases --token "${TOKEN}" | grep -q "fixture2030_en_vivo"; then
    echo "Base 'fixture2030_en_vivo' ya existe."
else
    docker compose exec -T influxdb influxdb3 create database fixture2030_en_vivo --retention-period 7d --token "${TOKEN}"
    echo "Base 'fixture2030_en_vivo' creada exitosamente con retencion de 7 dias."
fi

echo "=== [5/5] Creando base de datos 'fixture2030_resumen' (sin expiracion) ==="
if docker compose exec -T influxdb influxdb3 show databases --token "${TOKEN}" | grep -q "fixture2030_resumen"; then
    echo "Base 'fixture2030_resumen' ya existe."
else
    docker compose exec -T influxdb influxdb3 create database fixture2030_resumen --token "${TOKEN}"
    echo "Base 'fixture2030_resumen' creada exitosamente sin expiracion."
fi

echo ""
echo "Bases de datos configuradas en el servidor:"
docker compose exec -T influxdb influxdb3 show databases --token "${TOKEN}"

echo ""
echo "=== Inicializacion completada con exito ==="
