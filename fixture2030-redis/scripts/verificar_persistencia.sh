#!/bin/sh
set -eu

redis() {
  docker compose exec -T redis redis-cli "$@"
}

redis SET prueba:persistencia datos-conservados EX 300 >/dev/null
printf 'Valor antes del reinicio: %s\n' "$(redis GET prueba:persistencia)"

docker compose restart redis >/dev/null

intentos=0
until [ "$(redis PING 2>/dev/null || true)" = "PONG" ]; do
  intentos=$((intentos + 1))
  if [ "$intentos" -ge 30 ]; then
    printf 'ERROR: Redis no volvio a quedar disponible.\n' >&2
    exit 1
  fi
  sleep 1
done

valor="$(redis GET prueba:persistencia)"
ttl="$(redis TTL prueba:persistencia)"
printf 'Valor despues del reinicio: %s\n' "$valor"
printf 'TTL despues del reinicio: %s\n' "$ttl"

if [ "$valor" != "datos-conservados" ] || [ "$ttl" -le 0 ]; then
  printf 'ERROR: el valor o su TTL no sobrevivieron al reinicio.\n' >&2
  exit 1
fi

printf 'OK: el valor y su TTL sobrevivieron al reinicio del contenedor.\n'
redis DEL prueba:persistencia >/dev/null
