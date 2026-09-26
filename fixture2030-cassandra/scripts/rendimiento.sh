#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/.." && pwd)"
evidence_dir="${project_dir}/evidencia"

total_ops="${TOTAL_OPS:-1000000}"
warmup_ops="${WARMUP_OPS:-50000}"
threads="${THREADS:-200}"
cql_user="${CQL_USER:-cassandra}"
cql_password="${CQL_PASSWORD:-cassandra}"

mkdir -p "${evidence_dir}"
cd "${project_dir}"

compose_exec=(docker compose exec -T cassandra)
cqlsh=("${compose_exec[@]}" /opt/cassandra/bin/cqlsh -u "${cql_user}" -p "${cql_password}")
stress=("${compose_exec[@]}" /opt/cassandra/tools/bin/cassandra-stress)

wait_for_cassandra() {
  local attempt
  for attempt in $(seq 1 60); do
    if "${cqlsh[@]}" -e "SHOW VERSION" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  echo "ERROR: Cassandra no aceptó conexiones dentro de 120 segundos." >&2
  return 1
}

echo "Levantando Cassandra y esperando el puerto CQL..."
docker compose up -d
wait_for_cassandra

{
  echo "# AMBIENTE DE PRUEBA DE CASSANDRA"
  echo "fecha_inicio=$(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "host=$(hostname)"
  echo "sistema_operativo=$(sw_vers -productName 2>/dev/null || uname -s) $(sw_vers -productVersion 2>/dev/null || uname -r)"
  echo "arquitectura=$(uname -m)"
  echo "cpu_logicas=$(sysctl -n hw.logicalcpu 2>/dev/null || getconf _NPROCESSORS_ONLN)"
  echo "ram_host_bytes=$(sysctl -n hw.memsize 2>/dev/null || true)"
  echo "docker_cpus=$(docker info --format '{{.NCPU}}')"
  echo "docker_memoria_bytes=$(docker info --format '{{.MemTotal}}')"
  echo "imagen=$(docker inspect --format '{{.Config.Image}}' fixture2030-cassandra)"
  echo "imagen_id=$(docker inspect --format '{{.Image}}' fixture2030-cassandra)"
  echo "operaciones_medidas=${total_ops}"
  echo "operaciones_calentamiento=${warmup_ops}"
  echo "threads=${threads}"
  "${compose_exec[@]}" /opt/cassandra/bin/nodetool info | grep -E 'Heap Memory|Data Center|Rack|Uptime'
} | tee "${evidence_dir}/ambiente.txt"

"${compose_exec[@]}" /opt/cassandra/bin/nodetool status \
  | tee "${evidence_dir}/nodetool_status.txt"

"${cqlsh[@]}" -e "SHOW VERSION" 2>&1 \
  | tee "${evidence_dir}/cql_version.txt"

"${cqlsh[@]}" -f /scripts/esquema.cql 2>&1 \
  | tee "${evidence_dir}/estructura.txt"

echo "Calentamiento: ${warmup_ops} operaciones con ${threads} threads..."
"${cqlsh[@]}" -e "TRUNCATE fixture2030_comentarios.comentarios_feed"
"${stress[@]}" user profile=/scripts/stress-comentarios.yaml \
  "ops(insert=1)" n="${warmup_ops}" no-warmup cl=LOCAL_ONE \
  -node 127.0.0.1 \
  -mode user="${cql_user}" password="${cql_password}" port=9042 prepared \
  -rate threads="${threads}" \
  -log level=minimal interval=5s no-summary \
  >"${evidence_dir}/calentamiento.txt" 2>&1

echo "Prueba medida: ${total_ops} operaciones con ${threads} threads..."
"${cqlsh[@]}" -e "TRUNCATE fixture2030_comentarios.comentarios_feed"
{
  echo "fecha_inicio_prueba=$(date '+%Y-%m-%d %H:%M:%S %Z')"
  "${stress[@]}" user profile=/scripts/stress-comentarios.yaml \
    "ops(insert=1)" n="${total_ops}" no-warmup cl=LOCAL_ONE \
    -node 127.0.0.1 \
    -mode user="${cql_user}" password="${cql_password}" port=9042 prepared \
    -rate threads="${threads}" \
    -log level=normal interval=5s
  echo "fecha_fin_prueba=$(date '+%Y-%m-%d %H:%M:%S %Z')"
} 2>&1 | tee "${evidence_dir}/prueba_carga.txt"

"${compose_exec[@]}" /opt/cassandra/bin/nodetool flush fixture2030_comentarios comentarios_feed
"${compose_exec[@]}" /opt/cassandra/bin/nodetool tablestats fixture2030_comentarios.comentarios_feed \
  | tee "${evidence_dir}/tablestats.txt"

if ! "${cqlsh[@]}" --request-timeout=180 -e \
  "SELECT COUNT(*) AS filas_almacenadas FROM fixture2030_comentarios.comentarios_feed;" \
  2>&1 | tee "${evidence_dir}/conteo_final.txt"; then
  {
    echo
    echo "NOTA: el COUNT(*) global excedió el read_request_timeout del servidor."
    echo "La cantidad contractual se verifica con 'Total partitions' y 'Total errors'"
    echo "en prueba_carga.txt; COUNT(*) global no es un patrón recomendado en Cassandra."
  } | tee -a "${evidence_dir}/conteo_final.txt"
fi

grep -E \
  '^(Op rate|Partition rate|Row rate|Latency (mean|median|95th|99th|99.9th|max)|Total partitions|Total errors|Total operation time)' \
  "${evidence_dir}/prueba_carga.txt" >"${evidence_dir}/resumen_prueba.txt"

echo "Evidencia guardada en ${evidence_dir}"
