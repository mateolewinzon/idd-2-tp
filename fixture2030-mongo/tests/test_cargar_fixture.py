"""Validación del seed sin dependencias ni bases de datos."""
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('cargar_fixture', ROOT / 'scripts/cargar_fixture.py')
loader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(loader)


class SeedTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.csv = self.root / 'import'
        shutil.copytree(ROOT.parent / 'fixture2030-neo4j/import', self.csv)
        self.calendar = self.root / 'calendar.json'
        shutil.copy(ROOT / 'datos/fixture-calendario.json', self.calendar)

    def mutate(self, function):
        config = json.loads(self.calendar.read_text())
        function(config['partidos'])
        self.calendar.write_text(json.dumps(config))

    def prepare(self, scenario=None):
        return loader.preparar(self.csv, self.calendar, scenario)

    def test_base_and_demo(self):
        docs = self.prepare()
        self.assertEqual(len(docs), 127)
        self.assertEqual(len({d['_id'] for d in docs}), 127)
        self.assertTrue(all(d['estado'] == 'proximo' and d['resultado'] is None for d in docs))
        self.assertTrue(all(d['fecha_hora'].tzinfo is not None for d in docs))
        docs = self.prepare(ROOT / 'datos/fixture-escenario-demo.json')
        self.assertEqual({d['estado'] for d in docs}, {'proximo', 'en_vivo', 'finalizado'})

    def test_no_timezone(self):
        self.mutate(lambda c: c['P-001'].update(fecha_hora='2030-06-08T18:00:00'))
        with self.assertRaisesRegex(ValueError, 'sin zona'):
            self.prepare()

    def test_invalid_states_and_results(self):
        for state, result in [('otro', None), ('en_vivo', None), ('proximo', {'goles_local': 0, 'goles_visitante': 0}),
                              ('finalizado', {'goles_local': -1, 'goles_visitante': 0}),
                              ('finalizado', {'goles_local': True, 'goles_visitante': 0})]:
            with self.subTest(state=state, result=result), self.assertRaises(ValueError):
                loader.validar_resultado(state, result)

    def test_duplicate_participation(self):
        with (self.csv / 'participaciones.csv').open('a') as f:
            f.write('P-001,URU,Local\n')
        with self.assertRaisesRegex(ValueError, 'duplicada'):
            self.prepare()

    def test_broken_reference(self):
        p = self.csv / 'participaciones.csv'
        p.write_text(p.read_text().replace('P-001,URU,Local', 'P-001,ZZZ,Local'))
        with self.assertRaisesRegex(ValueError, 'inválida'):
            self.prepare()

    def test_missing_calendar_row(self):
        self.mutate(lambda c: c.pop('P-001'))
        with self.assertRaisesRegex(ValueError, 'exactamente'):
            self.prepare()

    def test_explicit_unresolved_slot(self):
        p = self.csv / 'participaciones.csv'
        p.write_text(p.read_text().replace('P-001,URU,Local\n', ''))
        with self.assertRaisesRegex(ValueError, 'Faltan'):
            self.prepare()
        self.mutate(lambda c: c['P-001'].update(plazas_pendientes=['Local']))
        self.assertIsNone(self.prepare()[0]['local'])


if __name__ == '__main__':
    unittest.main()
