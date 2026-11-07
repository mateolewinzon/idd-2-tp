#!/usr/bin/env python3
"""Prototipo de proyección analítica, separado del endpoint operacional."""
import argparse
from collections import defaultdict
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import tempfile
from experimento import ROOT, canonical, connect, digest, source, write


def transform(documents):
    seen=set(); facts=[]; rejected=[]; finished=0
    for doc in documents:
        code=doc['_id']
        if code in seen: raise ValueError('Partido duplicado en extracción: '+code)
        seen.add(code)
        if doc['estado']!='finalizado': continue
        finished+=1
        score=doc.get('resultado')
        if (not doc.get('local') or not doc.get('visitante') or
            doc['local']['codigo']==doc['visitante']['codigo'] or not isinstance(score,dict) or
            any(type(score.get(k)) is not int or score[k]<0 for k in ('goles_local','goles_visitante'))):
            rejected.append(dict(partido=code,cause='Participantes o resultado incompletos/inválidos'));continue
        for side,other in [('local','visitante'),('visitante','local')]:
            facts.append(dict(partido=code,equipo=doc[side]['codigo'],nombre_equipo=doc[side]['nombre'],
              fase=doc['fase'],fecha_hora=str(doc['fecha_hora']),condicion=side,partidos_jugados=1,
              goles_favor=score['goles_'+side],goles_contra=score['goles_'+other],
              source_collection='partidos',source_id=code))
    keys={(f['partido'],f['equipo']) for f in facts}
    assert len(keys)==len(facts)==2*(finished-len(rejected))
    assert sum(f['goles_favor'] for f in facts)==sum(f['goles_contra'] for f in facts)
    totals=defaultdict(lambda: dict(partidos_jugados=0,goles_favor=0,goles_contra=0))
    for f in facts:
        group=totals[(f['equipo'],f['fase'])]
        for metric in group: group[metric]+=f[metric]
    aggregate=[dict(equipo=key[0],fase=key[1],**value) for key,value in sorted(totals.items())]
    # Control independiente desde documentos para cada equipo/fase (no desde las filas proyectadas).
    for total in aggregate:
        played=gf=ga=0
        rejected_codes={r['partido'] for r in rejected}
        for d in documents:
            if d['estado']!='finalizado' or d['_id'] in rejected_codes or d['fase']!=total['fase']: continue
            for side,other in [('local','visitante'),('visitante','local')]:
                if d[side]['codigo']==total['equipo']:
                    played+=1;gf+=d['resultado']['goles_'+side];ga+=d['resultado']['goles_'+other]
        assert (played,gf,ga)==(total['partidos_jugados'],total['goles_favor'],total['goles_contra'])
    return dict(facts=sorted(facts,key=lambda f:(f['partido'],f['equipo'])),totals=aggregate,
        rejected=rejected,validation=dict(source_records=len(documents),finished=finished,fact_count=len(facts),
        rejected=len(rejected),unique_keys=True,goals_balanced=True,totals_match_source=True))


def publish(documents, output):
    result=transform(documents)
    if result['rejected']: raise ValueError('No se publica una proyección incompleta; ver registros rechazados')
    result.update(extracted_at=datetime.now(timezone.utc).isoformat(),source_sha256=digest(canonical(documents)),
          data_sha256=digest(canonical(result['facts'])),publication='snapshot completo con reemplazo atómico local')
    output.parent.mkdir(parents=True,exist_ok=True)
    # Una falla de transformación no toca el archivo anterior. Reintentar reemplaza, no incrementa.
    fd,temporary=tempfile.mkstemp(prefix='.mart-',suffix='.json',dir=output.parent)
    try:
        with os.fdopen(fd,'w') as stream:
            json.dump(result,stream,ensure_ascii=False,indent=2);stream.write('\n');stream.flush();os.fsync(stream.fileno())
        os.replace(temporary,output)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--backend',type=Path,required=True)
    parser.add_argument('--output',type=Path,default=ROOT/'evidencia/data_mart.json')
    args=parser.parse_args()
    mongo,db,redis=connect(args.backend)
    try:
        docs=source(db)
        write(args.output.with_name('data_mart_source.json'),docs)
        result=publish(docs,args.output)
        print(json.dumps(result['validation']))
    finally: mongo.close();redis.close()

if __name__=='__main__': main()
