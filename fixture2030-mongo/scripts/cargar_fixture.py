#!/usr/bin/env python3
"""Carga validada del fixture. Ejecutar con el Python del entorno del backend."""
import argparse
import csv
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
CACHE_KEY = "fixture:v1:todos"


def read_csv(path):
    with path.open(encoding="utf-8", newline="") as stream:
        return list(csv.DictReader(stream))


def indexed(rows):
    result = {}
    for row in rows:
        if row["id"] in result:
            raise ValueError(f"Identificador duplicado: {row['id']}")
        result[row["id"]] = row
    return result


def validar_resultado(estado, resultado):
    if estado not in ("proximo", "en_vivo", "finalizado"):
        raise ValueError("Estado inválido")
    if estado == "proximo":
        if resultado is not None:
            raise ValueError("Un partido próximo no tiene resultado")
        return
    def marcador(value, keys):
        if not isinstance(value, dict) or not {'goles_local', 'goles_visitante'} <= value.keys() or value.keys() - keys:
            raise ValueError("Marcador incompleto o con campos desconocidos")
        if any(type(value[k]) is not int or value[k] < 0 for k in ('goles_local', 'goles_visitante')):
            raise ValueError("Los goles deben ser enteros no negativos")
    marcador(resultado, {'goles_local', 'goles_visitante', 'penales'})
    if resultado.get('penales') is not None:
        marcador(resultado['penales'], {'goles_local', 'goles_visitante'})


def preparar(import_dir, calendario, escenario=None):
    """No accede a las bases: rechaza todo el lote antes de escribir."""
    partidos = indexed(read_csv(import_dir / "partidos.csv"))
    equipos = indexed(read_csv(import_dir / "equipos.csv"))
    sedes = indexed(read_csv(import_dir / "sedes.csv"))
    config = json.loads(calendario.read_text())["partidos"]
    if config.keys() != partidos.keys():
        raise ValueError("El calendario debe cubrir exactamente los partidos del CSV")
    overrides = json.loads(escenario.read_text())["partidos"] if escenario else {}
    if overrides.keys() - partidos.keys():
        raise ValueError("El escenario referencia partidos inexistentes")
    participaciones = {codigo: {} for codigo in partidos}
    for p in read_csv(import_dir / "participaciones.csv"):
        codigo, condicion, equipo = p['partido_id'], p['condicion'], p['equipo_id']
        if codigo not in partidos or condicion not in ('Local', 'Visitante') or equipo not in equipos:
            raise ValueError(f"Participación inválida: {p}")
        if condicion in participaciones[codigo]:
            raise ValueError(f"Condición duplicada: {codigo}/{condicion}")
        participaciones[codigo][condicion] = equipo
    docs = []
    for codigo, p in partidos.items():
        c = {**config[codigo], **overrides.get(codigo, {})}
        if not re.fullmatch(r'P-[0-9]{3}', codigo) or not p['fase']:
            raise ValueError(f"Código o fase inválido: {codigo}")
        fecha = datetime.fromisoformat(c['fecha_hora'].replace('Z', '+00:00'))
        if fecha.tzinfo is None or fecha.utcoffset() is None:
            raise ValueError(f"Horario sin zona: {codigo}")
        fecha = fecha.astimezone(timezone.utc)
        if fecha.date().isoformat() != p['fecha']:
            raise ValueError(f"Fecha distinta al CSV: {codigo}")
        if p['grupo'] and not re.fullmatch('[A-P]', p['grupo']):
            raise ValueError(f"Grupo inválido: {codigo}")
        validar_resultado(c['estado'], c['resultado'])
        slots = participaciones[codigo]
        pendientes = c.get('plazas_pendientes', [])
        if not isinstance(pendientes, list) or len(set(pendientes)) != len(pendientes) or set(pendientes) - {'Local', 'Visitante'}:
            raise ValueError(f"Plazas pendientes inválidas: {codigo}")
        if set(slots) & set(pendientes) or set(slots) | set(pendientes) != {'Local', 'Visitante'}:
            raise ValueError(f"Faltan participaciones o plazas pendientes explícitas: {codigo}")
        if len(set(slots.values())) != len(slots):
            raise ValueError(f"Equipos repetidos: {codigo}")
        def referencia(condicion):
            eq = slots.get(condicion)
            if eq is None:
                return None
            if not re.fullmatch('[A-Z]{3}', eq) or not equipos[eq]['nombre']:
                raise ValueError(f"Equipo inválido: {eq}")
            return {'codigo': eq, 'nombre': equipos[eq]['nombre']}
        sede = sedes.get(p['sede_id'])
        if not sede or not all(sede[k] for k in ('id', 'nombre', 'ciudad')):
            raise ValueError(f"Sede inexistente o inválida: {codigo}")
        docs.append(dict(_id=codigo, fecha_hora=fecha, fase=p['fase'], grupo=p['grupo'] or None,
                         local=referencia('Local'), visitante=referencia('Visitante'),
                         sede=dict(codigo=sede['id'], nombre=sede['nombre'], ciudad=sede['ciudad']),
                         estado=c['estado'], resultado=c['resultado']))
    return docs


def cargar(db, docs, reiniciar=False):
    """Upserts sin borrados; una recarga conserva el estado deportivo."""
    from pymongo import UpdateOne
    validator = json.loads((ROOT / 'datos/partidos-validator.json').read_text())
    options = dict(validator=validator, validationLevel='strict', validationAction='error')
    if 'partidos' in db.list_collection_names():
        db.command('collMod', 'partidos', **options)
    else:
        db.create_collection('partidos', **options)
    db.partidos.create_index([('fecha_hora', 1), ('_id', 1)], name='idx_partidos_fecha_codigo')
    ops = []
    now = datetime.now(timezone.utc)
    for doc in docs:
        calendar = {k: v for k, v in doc.items() if k not in ('_id', 'estado', 'resultado')}
        initial = {k: doc[k] for k in ('estado', 'resultado')}
        if reiniciar:
            calendar.update(initial)
            initial = {}
        calendar['actualizado_en'] = now
        update = {'$set': calendar}
        if initial:
            update['$setOnInsert'] = initial
        ops.append(UpdateOne({'_id': doc['_id']}, update, upsert=True))
    if not ops:
        return dict(insertados=0, actualizados=0, rechazados=0)
    result = db.partidos.bulk_write(ops, ordered=True)
    return dict(insertados=result.upserted_count, actualizados=result.modified_count, rechazados=0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--import-dir', type=Path, default=ROOT.parent / 'fixture2030-neo4j/import')
    parser.add_argument('--calendario', type=Path, default=ROOT / 'datos/fixture-calendario.json')
    parser.add_argument('--escenario', type=Path)
    parser.add_argument('--reiniciar-escenario', action='store_true')
    parser.add_argument('--solo-validar', action='store_true')
    args = parser.parse_args()
    if args.escenario and not args.reiniciar_escenario:
        parser.error('--escenario requiere --reiniciar-escenario')
    docs = preparar(args.import_dir, args.calendario, args.escenario)
    if args.solo_validar:
        print(json.dumps(dict(validados=len(docs), rechazados=0)))
        return
    from pymongo import MongoClient
    from redis import Redis
    from redis.exceptions import RedisError
    with MongoClient(os.getenv('MONGO_URI', 'mongodb://localhost:27017'), serverSelectionTimeoutMS=5000,
                     connectTimeoutMS=5000, socketTimeoutMS=5000) as client:
        try:
            result = cargar(client[os.getenv('MONGO_DATABASE', 'fixture2030')], docs, args.reiniciar_escenario)
        finally:
            # También ante escritura parcial: no conservar una copia anterior por éxito aparente.
            try:
                with Redis(host=os.getenv('REDIS_HOST', 'localhost'), port=int(os.getenv('REDIS_PORT', '6380')),
                           db=int(os.getenv('REDIS_DB', '0')), password=os.getenv('REDIS_PASSWORD') or None,
                           socket_connect_timeout=2, socket_timeout=2) as cache:
                    cache.delete(CACHE_KEY)
            except RedisError:
                print('Advertencia: invalidación Redis fallida; esperar el TTL configurado.', file=sys.stderr)
        print(json.dumps(result))


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        # Evitar exponer URIs, credenciales o mensajes de los drivers.
        if isinstance(exc, (ValueError, KeyError)):
            print(f'Validación rechazada antes de escribir: {exc}', file=sys.stderr)
        else:
            print(f'Carga incompleta: {type(exc).__name__}; revisar conectividad y datos.', file=sys.stderr)
        sys.exit(1)
