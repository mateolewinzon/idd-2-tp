#!/usr/bin/env bash
# ==============================================================================
# scripts/rendimiento.sh - Punto 5: Analisis de Rendimiento (Operacion 8)
#
# Ejecuta explain("executionStats") antes de indexar, crea el indice con
# createIndex() y repite explain("executionStats"), guardando la salida en
# evidencia/rendimiento.txt.
# ==============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

mkdir -p evidencia
archivo_salida="evidencia/rendimiento.txt"

echo "================================================================================"
echo "               HITO 4: ANALISIS DE RENDIMIENTO (PUNTO 5)                        "
echo "================================================================================"
echo ""
echo "OBJETIVO:"
echo "Demostrar con evidencia de explain('executionStats') el impacto de crear un indice"
echo "compuesto sobre campos dejados deliberadamente sin indexar en el diseno inicial:"
echo "  Consulta: { club: 'Real Madrid' }, ordenado por { fecha_nacimiento: 1 }."
echo "  Indice aplicado: { club: 1, fecha_nacimiento: 1 }"
echo ""
echo "Ejecutando analisis de rendimiento en MongoDB..."
echo "La salida se guardara en: $archivo_salida"

{
  echo "################################################################################"
  echo "# EVIDENCIA DE ANALISIS DE RENDIMIENTO - $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "################################################################################"
  echo ""
  docker compose exec -T mongo mongosh fixture2030 --quiet --file "/scripts/06-analisis-rendimiento.js"
} | tee "$archivo_salida"

echo ""
echo "Analisis completado. Evidencia guardada en $archivo_salida."
