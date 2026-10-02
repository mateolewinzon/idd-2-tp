#!/bin/sh
set -eu

mkdir -p docs/evidencia

docker compose exec -T redis redis-cli < scripts/inicializacion.redis > docs/evidencia/01_inicializacion.txt
docker compose exec -T redis redis-cli < scripts/carga_muestra.redis > docs/evidencia/02_carga_muestra.txt
docker compose exec -T redis redis-cli < scripts/sesiones.redis > docs/evidencia/03_sesiones.txt
docker compose exec -T redis redis-cli < scripts/cache.redis > docs/evidencia/04_cache.txt
./scripts/concurrencia.sh > docs/evidencia/05_concurrencia.txt
docker compose exec -T redis redis-benchmark --csv --dbnum 15 -n 10000 -c 50 -t set,get,incr > docs/evidencia/06_rendimiento.txt
docker compose exec -T redis redis-cli -n 15 FLUSHDB >/dev/null
docker compose exec -T redis redis-cli < scripts/metricas.redis > docs/evidencia/07_metricas.txt
docker compose exec -T redis redis-cli INFO server > docs/evidencia/08_ambiente.txt
./scripts/verificar_persistencia.sh > docs/evidencia/09_persistencia.txt

printf 'Evidencia generada en docs/evidencia/.\n'
