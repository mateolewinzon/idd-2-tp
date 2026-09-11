#!/usr/bin/env bash
# Carga el grafo desde los CSV de import/ (queries/carga.cypher) y registra la
# evidencia de idempotencia (RNF4): conteos antes de cargar, despues de la primera
# carga y despues de repetirla. Las dos ultimas tienen que ser identicas.
#
# Requiere Neo4j levantado (./scripts/levantarDocker.sh) y las restricciones
# aplicadas (./scripts/estructura.sh). Es seguro de repetir.
set -euo pipefail

# Posicionar la terminal en el directorio raiz del modulo (fixture2030-neo4j)
cd "$(dirname "$0")/.."

mkdir -p evidencia

# Ejecuta un archivo Cypher con cypher-shell dentro del contenedor.
ejecutar() {
  docker compose exec -T neo4j cypher-shell -u neo4j -p password123 < "$1"
}

{
  echo "============================================================"
  echo " Evidencia de Carga - $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "============================================================"
  echo ""
  echo "==> 1. Conteos antes de cargar (queries/verificacion.cypher)"
  ejecutar queries/verificacion.cypher
  echo ""
  echo "==> 2. Primera carga (queries/carga.cypher) y conteos"
  ejecutar queries/carga.cypher
  primera="$(ejecutar queries/verificacion.cypher)"
  echo "$primera"
  echo ""
  echo "==> 3. Segunda carga sobre el mismo grafo y conteos"
  ejecutar queries/carga.cypher
  segunda="$(ejecutar queries/verificacion.cypher)"
  echo "$segunda"
  echo ""
  if [ "$primera" = "$segunda" ]; then
    echo "Conteos identicos despues de repetir la carga: no se duplicaron nodos ni relaciones (RNF4)."
  else
    echo "ERROR: los conteos cambiaron al repetir la carga."
    exit 1
  fi
} | tee evidencia/carga.txt

echo ""
echo "Carga completa. Salida guardada en evidencia/carga.txt"
