#!/usr/bin/env bash
# Genera los CSV de import/ a partir de la base MongoDB del Hito 4.
#
# Solo hace falta para REGENERAR los CSV: ya estan versionados en import/, asi que
# la carga en Neo4j no depende de MongoDB. Requiere el modulo fixture2030-mongo
# levantado y cargado (ver su README).
#
# Genera los ocho archivos dos veces y compara las dos pasadas: es la evidencia de
# que el generador es determinista.
set -euo pipefail

# Posicionar la terminal en el directorio raiz del modulo (fixture2030-neo4j)
cd "$(dirname "$0")/.."

CONTENEDOR_MONGO="fixture2030-mongo"
ARCHIVOS="equipos jugadores sedes partidos participaciones alineaciones eventos protagonistas"

if ! docker exec "$CONTENEDOR_MONGO" mongosh --quiet --eval "db.adminCommand('ping').ok" >/dev/null 2>&1; then
  echo "ERROR: MongoDB (contenedor $CONTENEDOR_MONGO) no responde."
  echo "Levantar y cargar primero el modulo fixture2030-mongo."
  exit 1
fi

# El contenedor de MongoDB no ve esta carpeta, asi que el generador se le pasa
# como texto con --eval, precedido de la variable ARCHIVO que indica que imprimir.
GENERADOR="$(cat scripts/generar-csv.js)"

generar() {
  docker exec "$CONTENEDOR_MONGO" mongosh --quiet fixture2030 --eval "const ARCHIVO = '$1'; ${GENERADOR}"
}

mkdir -p import evidencia

{
  echo "============================================================"
  echo " Evidencia de Generacion de CSV - $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "============================================================"
  echo ""
  echo "==> 1. Generando los CSV desde MongoDB..."
  for archivo in $ARCHIVOS; do
    # Primero se escribe un .tmp: si el generador aborta (codigo 1), se muestra el
    # motivo y el CSV anterior queda intacto.
    if ! generar "$archivo" > "import/${archivo}.csv.tmp"; then
      cat "import/${archivo}.csv.tmp"
      rm "import/${archivo}.csv.tmp"
      exit 1
    fi
    mv "import/${archivo}.csv.tmp" "import/${archivo}.csv"
  done
  generar resumen
  echo ""
  echo "==> 2. Segunda pasada: se regenera cada CSV y se compara con el primero..."
  for archivo in $ARCHIVOS; do
    if ! generar "$archivo" > "import/${archivo}.csv.tmp"; then
      cat "import/${archivo}.csv.tmp"
      rm "import/${archivo}.csv.tmp"
      exit 1
    fi
    # diff no imprime nada si son iguales; si difieren, se informa y se corta el script.
    if ! diff -q "import/${archivo}.csv" "import/${archivo}.csv.tmp"; then
      rm "import/${archivo}.csv.tmp"
      echo "ERROR: import/${archivo}.csv cambio entre las dos pasadas: la generacion no es determinista."
      exit 1
    fi
    rm "import/${archivo}.csv.tmp"
  done
  echo "  Los 8 CSV son identicos en las dos pasadas: la generacion es determinista."
} | tee evidencia/generacion.txt

echo ""
echo "CSV generados en import/. Salida guardada en evidencia/generacion.txt"
