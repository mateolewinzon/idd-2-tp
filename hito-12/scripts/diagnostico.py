#!/usr/bin/env python3
"""Diagnóstico de consulta y controles de la preparación (ejecutar sin carga)."""
import argparse
from collections import Counter
from pathlib import Path
from experimento import ROOT, connect, prepare, source, digest, canonical, write

p=argparse.ArgumentParser(description=__doc__);p.add_argument('--backend',type=Path,required=True);args=p.parse_args()
mongo,db,redis=connect(args.backend)
try:
    before=digest(canonical(source(db)))
    count_before=db.partidos.count_documents({})
    reloaded=prepare(args.backend,db,redis)
    after=digest(canonical(source(db)))
    assert count_before==127==db.partidos.count_documents({}) and before==after
    assert reloaded['insertados']==0
    projection={k:1 for k in ('_id','fecha_hora','fase','grupo','local','visitante','estado','resultado')}
    explanation=db.command('explain',{'find':'partidos','filter':{},'projection':projection,'sort':{'fecha_hora':1,'_id':1}},verbosity='executionStats')
    docs=source(db)
    write(ROOT/'evidencia/diagnostico.json',dict(reload=reloaded,unchanged=before==after,
        source_sha256=after,records=len(docs),states=dict(Counter(d['estado'] for d in docs)),
        mongo_version=db.command('buildInfo')['version'],redis_version=redis.info('server')['redis_version'],
        indexes=list(db.partidos.list_indexes()),explain=explanation))
    print('Consulta real, índice, versiones y recarga validados.')
finally: mongo.close();redis.close()
