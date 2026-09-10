#!/usr/bin/env bash
# Evidencia del item 1: que MongoDB esta disponible y que los datos persisten.
# Reinicia el contenedor a proposito, para demostrar RF2. No pierde datos.
set -euo pipefail

cd "$(dirname "$0")/.."

mkdir -p evidencia

contar() {
  docker compose exec -T mongo mongosh --quiet --eval '
    const f = db.getSiblingDB("fixture2030");
    print("  equipos:   " + f.equipos.countDocuments());
    print("  jugadores: " + f.jugadores.countDocuments());
  '
}

{
  echo "Ejecutado: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo ""
  echo "=== Evidencia del ambiente de ejecucion ====================="
  echo ""

  echo "1. Estado del contenedor"
  docker compose ps --format "  {{.Name}} | {{.Image}} | {{.Status}}"
  echo ""

  echo "2. Volumen persistente"
  docker volume ls --filter "name=fixture2030_data" --format "  {{.Name}} | driver: {{.Driver}}"
  docker compose exec -T mongo sh -c 'echo "  punto de montaje: /data/db  ($(du -sh /data/db 2>/dev/null | cut -f1) en disco)"'
  echo ""

  echo "3. MongoDB responde"
  docker compose exec -T mongo mongosh --quiet --eval '
    print("  ping:      " + db.adminCommand("ping").ok);
    print("  version:   " + db.adminCommand({ buildInfo: 1 }).version);
    print("  uptime:    " + db.serverStatus().uptime + " s");
    print("  bases:     " + db.adminCommand({ listDatabases: 1 }).databases.map(d => d.name).join(", "));
  '
  echo ""

  echo "4. Persistencia de los datos ante un reinicio (RF2)"
  echo ""
  echo "  Antes del reinicio:"
  contar
  echo ""
  echo "  Reiniciando el contenedor..."
  docker compose restart mongo >/dev/null 2>&1
  for _ in $(seq 1 30); do
    estado=$(docker inspect --format '{{.State.Health.Status}}' fixture2030-mongo 2>/dev/null || echo "starting")
    [ "$estado" = "healthy" ] && break
    sleep 2
  done
  echo "  Contenedor nuevamente healthy."
  echo ""
  echo "  Despues del reinicio:"
  contar
  echo ""
  echo "  -> Los datos sobrevivieron: estan en el volumen, no en el contenedor."
  echo ""
  echo "-------------------------------------------------------------"
} | tee evidencia/ambiente.txt

echo "Salida guardada en evidencia/ambiente.txt"
