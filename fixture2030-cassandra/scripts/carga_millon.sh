#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/.." && pwd)"
evidence_dir="${project_dir}/evidencia"
total="${TOTAL_COMENTARIOS:-1000000}"
container_csv="/tmp/fixture2030-comentarios.csv"
container_verify="/tmp/fixture2030-comentarios-pk.csv"

if [[ ! "${total}" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: TOTAL_COMENTARIOS debe ser un entero positivo." >&2
  exit 2
fi

mkdir -p "${evidence_dir}"
cd "${project_dir}"

cleanup() {
  docker compose exec -T cassandra rm -f "${container_csv}" "${container_verify}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Generando ${total} comentarios deterministas dentro del contenedor..."
docker compose exec -T cassandra bash -c \
  "python3 /scripts/generar_millon.py --total ${total} > ${container_csv}"

generated_rows="$(docker compose exec -T cassandra wc -l "${container_csv}" | awk '{print $1}')"
if [[ "${generated_rows}" != "${total}" ]]; then
  echo "ERROR: se generaron ${generated_rows} filas en lugar de ${total}." >&2
  exit 1
fi

docker compose exec -T cassandra /opt/cassandra/bin/cqlsh \
  -u cassandra -p cassandra \
  -e "TRUNCATE fixture2030_comentarios.comentarios_feed"

{
  echo "# CARGA EXACTA DE COMENTARIOS ÚNICOS"
  echo "fecha_inicio=$(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "filas_csv=${generated_rows}"
  docker compose exec -T cassandra /opt/cassandra/bin/cqlsh \
    -u cassandra -p cassandra \
    -e "COPY fixture2030_comentarios.comentarios_feed (partido_id, bloque_temporal, comentario_id, idioma, usuario_id, nombre_usuario, texto, estado_moderacion) FROM '${container_csv}' WITH HEADER = FALSE AND NUMPROCESSES = 8 AND CHUNKSIZE = 5000 AND MAXBATCHSIZE = 20;"
  echo "fecha_fin=$(date '+%Y-%m-%d %H:%M:%S %Z')"
} 2>&1 | tee "${evidence_dir}/carga_millon.txt"

docker compose exec -T cassandra /opt/cassandra/bin/nodetool flush \
  fixture2030_comentarios comentarios_feed

{
  docker compose exec -T cassandra bash -c \
    "/opt/cassandra/bin/cqlsh -u cassandra -p cassandra -e \"COPY fixture2030_comentarios.comentarios_feed (partido_id, bloque_temporal, comentario_id) TO '${container_verify}' WITH HEADER = FALSE AND PAGESIZE = 1000 AND PAGETIMEOUT = 30;\""
  verified_rows="$(docker compose exec -T cassandra wc -l "${container_verify}" | awk '{print $1}')"
  echo "filas_fisicas_verificadas=${verified_rows}"
  if [[ "${verified_rows}" != "${total}" ]]; then
    echo "ERROR: Cassandra contiene ${verified_rows} filas, se esperaban ${total}." >&2
    exit 1
  fi
} 2>&1 | tee "${evidence_dir}/verificacion_millon.txt"

docker compose exec -T cassandra /opt/cassandra/bin/nodetool tablestats \
  fixture2030_comentarios.comentarios_feed \
  | tee "${evidence_dir}/tablestats_carga_millon.txt"

echo "Carga exacta verificada: ${total} comentarios físicos."
