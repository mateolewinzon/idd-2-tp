#!/usr/bin/env bash
# Ejecuta el CRUD de demostracion y guarda su salida como evidencia.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p evidencia

{
  echo "============================================================"
  echo " Evidencia de CRUD - $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "============================================================"
  docker compose exec -T neo4j cypher-shell -u neo4j -p password123 < queries/crud.cypher
} | tee evidencia/crud.txt

echo "CRUD completo. Salida guardada en evidencia/crud.txt"
