#!/bin/sh
set -eu

esperar_redis() {
  intentos=0
  until [ "$(docker compose exec -T redis redis-cli PING 2>/dev/null || true)" = "PONG" ]; do
    intentos=$((intentos + 1))
    if [ "$intentos" -ge 30 ]; then
      printf 'Redis no quedo disponible a tiempo.\n' >&2
      exit 1
    fi
    sleep 1
  done
}

docker compose up -d
esperar_redis

for script in inicializacion carga_muestra sesiones cache metricas; do
  printf '\n===== %s.redis =====\n' "$script"
  docker compose exec -T redis redis-cli < "scripts/$script.redis"
done

printf '\n===== concurrencia.sh =====\n'
./scripts/concurrencia.sh
