#!/bin/sh
set -eu

# $system.OBJ.Load y la sesión IRIS siguen el flujo de Clase 10.
# El método Ejecutar contiene los bloques ObjectScript para que IRIS los compile como clase.
docker exec -i fixture2030-iris iris session IRIS <<'IRIS'
// encontrado en documentación oficial: Import carga y compila varios archivos .cls del directorio.
Do $system.OBJ.Import("/scripts","ck/extensions=cls",.seleccionados,.errores,.importados)
Do ##class(Fixture.Demo).Ejecutar()
Halt
IRIS
