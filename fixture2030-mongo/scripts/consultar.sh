#!/usr/bin/env bash
# ==============================================================================
# scripts/consultar.sh - Punto 4: Operaciones y Consultas (1 a 7)
#
# Ejecuta las 7 operaciones documentales obligatorias sin formateos intermediarios,
# volcando la salida BSON/JSON cruda devuelta por MongoDB en evidencia/operaciones.txt.
# ==============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

mkdir -p evidencia
archivo_salida="evidencia/operaciones.txt"

echo "================================================================================"
echo "                   HITO 4: OPERACIONES Y CONSULTAS (PUNTO 4)                    "
echo "================================================================================"
echo ""
echo "JUSTIFICACION DE PAGINACION EN INTERFAZ:"
echo "En una aplicacion web de fixture deportivo con mas de 1.600 jugadores, solicitar"
echo "la totalidad de la coleccion en una sola peticion HTTP satura el ancho de banda,"
echo "aumenta el tiempo hasta el primer renderizado (FCP) y degrada la memoria en cliente."
echo "La paginacion mediante cursor acotado (limit + skip) combinada con sort asegura:"
echo "  1. Transferencias ligeras y predecibles en cada vista/pantalla de la UI."
echo "  2. Navegacion estable y determinista entre paginas sucesivas."
echo "  3. Resolucion en el motor de base de datos sin sobrecargar memoria del cliente,"
echo "     apoyandose en el indice compuesto de busqueda."
echo ""
echo "Ejecutando operaciones en MongoDB (fixture2030)..."
echo "La salida se registrara en: $archivo_salida"

{
  echo "################################################################################"
  echo "# EVIDENCIA DE OPERACIONES Y CONSULTAS - $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "################################################################################"
  echo ""
  docker compose exec -T mongo mongosh fixture2030 --quiet --file "/scripts/05-operaciones-consultas.js"
} | tee "$archivo_salida"

echo ""
echo "Operaciones completadas exitosamente. Evidencia guardada en $archivo_salida."
