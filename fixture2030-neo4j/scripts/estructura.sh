#!/usr/bin/env bash
# Aplica restricciones (constraints) e índices definidos en queries/estructura.cypher sobre Neo4j.
set -euo pipefail

# Posicionar la terminal en el directorio raíz del módulo (fixture2030-neo4j)
cd "$(dirname "$0")/.."

mkdir -p evidencia

echo "==> Aplicando restricciones e índices en Neo4j..."

# Ejecutar el archivo Cypher a través de cypher-shell y registrar el catálogo resultante como evidencia
{
  echo "============================================================"
  echo " Evidencia de Estructura - $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "============================================================"
  echo ""
  echo "==> 1. Aplicando queries/estructura.cypher..."
  docker compose exec -T neo4j cypher-shell -u neo4j -p password123 < queries/estructura.cypher
  echo "OK."
  echo ""
  echo "==> 2. Constraints creados en el grafo:"
  docker compose exec -T neo4j cypher-shell -u neo4j -p password123 "SHOW CONSTRAINTS YIELD name, type, entityType, labelsOrTypes, properties;"
  echo ""
  echo "==> 3. Índices activos en el grafo:"
  docker compose exec -T neo4j cypher-shell -u neo4j -p password123 "SHOW INDEXES YIELD name, state, type, entityType, labelsOrTypes, properties;"
} | tee evidencia/estructura.txt

echo ""
echo "Estructura (constraints e índices) aplicada y verificada correctamente."
echo "Salida guardada en evidencia/estructura.txt"
