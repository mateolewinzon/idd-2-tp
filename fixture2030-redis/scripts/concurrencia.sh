#!/bin/sh
set -eu

CLIENTES="${CLIENTES:-20}"
OPERACIONES="${OPERACIONES:-100}"
CLAVE_CONTADOR="prueba:concurrencia:visitas"
CLAVE_SESION="sesion:SES-CONCURRENCIA"

redis() {
  docker compose exec -T redis redis-cli "$@"
}

redis DEL "$CLAVE_CONTADOR" "$CLAVE_SESION" >/dev/null
redis HSET "$CLAVE_SESION" usuario_id U-CONC acciones 0 ultimo_acceso 2030-06-08T20:00:00Z >/dev/null
redis EXPIRE "$CLAVE_SESION" 1800 >/dev/null

worker() {
  indice=0
  while [ "$indice" -lt "$OPERACIONES" ]; do
    printf 'INCR %s\n' "$CLAVE_CONTADOR"
    indice=$((indice + 1))
  done | docker compose exec -T redis redis-cli --pipe >/dev/null
}

indice=0
pids=""
while [ "$indice" -lt "$CLIENTES" ]; do
  worker &
  pids="$pids $!"
  indice=$((indice + 1))
done

for pid in $pids; do
  wait "$pid"
done

esperado=$((CLIENTES * OPERACIONES))
obtenido="$(redis GET "$CLAVE_CONTADOR")"
redis EXPIRE "$CLAVE_CONTADOR" 604800 >/dev/null

printf 'Clientes concurrentes: %s\n' "$CLIENTES"
printf 'Operaciones por cliente: %s\n' "$OPERACIONES"
printf 'Resultado esperado: %s\n' "$esperado"
printf 'Resultado obtenido: %s\n' "$obtenido"

if [ "$obtenido" -ne "$esperado" ]; then
  printf 'ERROR: se perdieron actualizaciones\n' >&2
  exit 1
fi

printf 'OK: INCR preservo todas las actualizaciones concurrentes.\n'
redis TTL "$CLAVE_CONTADOR" | sed 's/^/TTL del contador: /'
redis DEL "$CLAVE_CONTADOR" "$CLAVE_SESION" >/dev/null
