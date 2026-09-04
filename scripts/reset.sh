#!/usr/bin/env bash
# DESTRUCTIVO: elimina el contenedor y el volumen de datos.
# Para detener sin perder datos, usar: docker compose stop
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Esto elimina el volumen 'fixture2030_data' y TODOS los datos cargados."
read -r -p "Escribir 'si' para continuar: " respuesta

if [ "$respuesta" != "si" ]; then
  echo "Cancelado. No se elimino nada."
  exit 0
fi

docker compose down -v
rm -f evidencia/ambiente.txt evidencia/carga.txt evidencia/verificacion.txt
echo "Ambiente y evidencia eliminados."
echo "Para reconstruirlo: ./scripts/levantar.sh && ./scripts/cargar.sh"
