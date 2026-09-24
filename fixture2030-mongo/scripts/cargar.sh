#!/usr/bin/env bash
# Setup + carga de equipos + carga de jugadores. Seguro de repetir: es idempotente.
set -euo pipefail

cd "$(dirname "$0")/.."

mkdir -p evidencia

ejecutar() {
  docker compose exec -T mongo mongosh --quiet --file "/scripts/$1"
}

# La salida se acumula en lugar de sobrescribirse: la evidencia de RF8 son las
# corridas consecutivas juntas, la primera insertando y la segunda sin hacer
# nada. `./scripts/reset.sh` limpia el archivo.
{
  echo ""
  echo "#############################################################"
  echo "# Corrida del $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "#############################################################"
  ejecutar 01-setup-colecciones.js
  ejecutar 02-carga-equipos.js
  ejecutar 03-carga-jugadores.js
} | tee -a evidencia/carga.txt

echo "Salida agregada a evidencia/carga.txt"
echo "Siguiente paso: ./scripts/verificar.sh"
