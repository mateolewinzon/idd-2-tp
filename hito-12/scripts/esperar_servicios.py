#!/usr/bin/env python3
"""Esperar como máximo 30 segundos por MongoDB y Redis del laboratorio."""
import argparse
from pathlib import Path
import time
from experimento import connect

p=argparse.ArgumentParser(description=__doc__);p.add_argument('--backend',type=Path,required=True);args=p.parse_args()
mongo,db,redis=connect(args.backend)
try:
    deadline=time.monotonic()+30
    while True:
        try:
            mongo.admin.command('ping');assert redis.ping();print('MongoDB y Redis disponibles.');break
        except Exception:
            if time.monotonic()>=deadline: raise RuntimeError('Los servicios no estuvieron disponibles en 30 s') from None
            time.sleep(.5)
finally: mongo.close();redis.close()
