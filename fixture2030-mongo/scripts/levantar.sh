#!/usr/bin/env bash
# Levanta el ambiente MongoDB y espera a que este disponible.
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> Levantando el ambiente..."
docker compose up -d

echo "==> Esperando a que MongoDB responda..."
for _ in $(seq 1 30); do
  estado=$(docker inspect --format '{{.State.Health.Status}}' fixture2030-mongo 2>/dev/null || echo "starting")
  if [ "$estado" = "healthy" ]; then
    echo ""
    echo "MongoDB disponible."
    docker compose exec -T mongo mongosh --quiet --eval '
      const info = db.adminCommand({ buildInfo: 1 });
      print("  Version:   " + info.version);
      print("  Bases:     " + db.adminCommand({ listDatabases: 1 }).databases.map(d => d.name).join(", "));
    '
    echo ""
    echo "Siguiente paso: ./scripts/cargar.sh"
    exit 0
  fi
  printf "."
  sleep 2
done

echo ""
echo "ERROR: MongoDB no llego a estado healthy. Revisar 'docker compose logs mongo'."
exit 1
