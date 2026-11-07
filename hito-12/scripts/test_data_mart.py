"""Pruebas de corrección/reintento, penales y publicación ante fallos."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from data_mart import publish, transform


def game():
    return dict(_id='P-001',estado='finalizado',fase='Final',fecha_hora='2030-07-20T18:00:00Z',
        local=dict(codigo='ARG',nombre='Argentina'),visitante=dict(codigo='BRA',nombre='Brasil'),
        resultado=dict(goles_local=2,goles_visitante=2,penales=dict(goles_local=4,goles_visitante=3)))

class MartTests(unittest.TestCase):
    def test_penalties_not_added_to_goals(self):
        result=transform([game()])
        self.assertEqual([(r['goles_favor'],r['goles_contra']) for r in result['facts']],[(2,2),(2,2)])
        self.assertEqual(result['validation']['fact_count'],2)

    def test_late_correction_and_retry_replace(self):
        with tempfile.TemporaryDirectory() as tmp:
            out=Path(tmp)/'mart.json';d=game()
            first=publish([d],out);second=publish([d],out)
            self.assertEqual(first['data_sha256'],second['data_sha256'])
            d['resultado']['goles_local']=3
            corrected=publish([d],out)
            self.assertEqual(len(corrected['facts']),2)
            self.assertEqual(corrected['totals'][0]['goles_favor'],3)
            d['estado']='en_vivo'
            self.assertEqual(publish([d],out)['facts'],[])

    def test_duplicate_extraction_is_rejected(self):
        with self.assertRaises(ValueError): transform([game(),game()])

    def test_missing_score_is_not_zero(self):
        d=game();d['resultado']=None
        result=transform([d])
        self.assertEqual(result['facts'],[])
        self.assertEqual(result['validation']['rejected'],1)

    def test_failed_refresh_preserves_previous_snapshot(self):
        with tempfile.TemporaryDirectory() as tmp:
            out=Path(tmp)/'mart.json';publish([game()],out);previous=out.read_bytes()
            d=game();d['visitante']=None
            with self.assertRaises(ValueError): publish([d],out)
            self.assertEqual(out.read_bytes(),previous)

    def test_team_identity_cannot_repeat(self):
        d=game();d['visitante']=copy.deepcopy(d['local'])
        self.assertEqual(transform([d])['validation']['rejected'],1)

if __name__=='__main__': unittest.main()
