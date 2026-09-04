#!/usr/bin/env bash
# Verifica volumen e integridad documental (RNF2 y RNF3). Solo lectura.
set -euo pipefail

cd "$(dirname "$0")/.."

mkdir -p evidencia

{
  echo "Ejecutado: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  docker compose exec -T mongo mongosh --quiet --file /scripts/04-verificar-integridad.js
} | tee evidencia/verificacion.txt

echo "Salida guardada en evidencia/verificacion.txt"
