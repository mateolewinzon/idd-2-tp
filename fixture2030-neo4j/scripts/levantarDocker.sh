#!/usr/bin/env bash
# Levanta el ambiente Neo4j con Docker Compose y espera a que el servicio esté disponible.
set -euo pipefail

# Posicionar la terminal en el directorio raíz del módulo (fixture2030-neo4j)
cd "$(dirname "$0")/.."

echo "==> Levantando el ambiente Neo4j con docker compose..."
docker compose up -d

echo "==> Esperando a que Neo4j responda..."
# Bucle de sondeo para esperar a que Neo4j esté listo para aceptar conexiones
for _ in $(seq 1 30); do
  # Verificar si cypher-shell puede autenticarse y responder
  if docker compose exec -T neo4j cypher-shell -u neo4j -p password123 "RETURN 1;" >/dev/null 2>&1; then
    echo ""
    echo "Neo4j disponible y listo para operar."
    echo ""
    echo "Siguiente paso: ./scripts/estructura.sh"
    exit 0
  fi
  printf "."
  sleep 2
done

echo ""
echo "ERROR: Neo4j no respondió a tiempo. Revisar 'docker compose logs neo4j'."
exit 1
