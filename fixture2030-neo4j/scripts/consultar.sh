#!/usr/bin/env bash
# Ejecuta las consultas de grafo y guarda resultados interpretables (RF8-RF11).
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p evidencia

{
  echo "============================================================"
  echo " Evidencia de Consultas - $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "============================================================"
  docker compose exec -T neo4j cypher-shell -u neo4j -p password123 < queries/consultas_grafo.cypher
} | tee evidencia/consultas.txt

echo "Consultas completas. Salida guardada en evidencia/consultas.txt"
