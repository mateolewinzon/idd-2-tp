# Hito 9 — InterSystems IRIS

Implementación didáctica de entidades complejas del Fixture 2030 mediante clases persistentes. Los objetos de Jugador, Partido y Evento creados en esta instancia son demostraciones aisladas: MongoDB mantiene Jugadores y Neo4j mantiene Partidos y Eventos como fuentes de verdad, según los hitos anteriores. IRIS no replica ni reemplaza esas bases.

## Modelo

El diagrama de clases, propiedades obligatorias, relaciones e identificadores se describe en [`docs/modelo_de_objetos.md`](docs/modelo_de_objetos.md). Las reglas de integridad y su evidencia se detallan en [`docs/matriz_de_integridad.md`](docs/matriz_de_integridad.md).

- `Persona` es la clase persistente base de `Jugador` y `Arbitro`.
- `Partido` contiene `Evento` mediante una relación bidireccional padre-hijo.
- `Evento.Partido` tiene un índice en el extremo hijo.
- `Partido.AgregarEvento()` rechaza un evento en minuto 0 si el partido está `Finalizado`.
- `Fixture.Demo.Ejecutar()` crea objetos, guarda el árbol desde el Partido, navega en ambas direcciones, consulta la proyección SQL, comprueba el borrado en cascada y presenta el caso de propiedad requerida omitida.

## Requisitos previos

Docker y Docker Compose instalados. La imagen declarada por Compose es `intersystems/iris-community:latest-cd`. El volumen Durable %SYS se monta desde `~/docker/data/iris`; los archivos `.cls` se montan en `/scripts` en solo lectura.

## Ejecución

Desde esta carpeta:

```sh
docker compose up -d
./scripts/demo_objetos.sh
```

El script usa `$system.OBJ.Import` para cargar y compilar en conjunto los archivos `.cls` de `/scripts`, abre la sesión `iris session IRIS` y ejecuta el método `Fixture.Demo.Ejecutar()`. La Clase 10 muestra `$system.OBJ.Load` para una clase, pero no cubre la importación y compilación de varias clases relacionadas; por eso se usa `Import` con el calificador `compile` y selección de extensión `.cls`.

> encontrado en documentación oficial: la invocación de `$system.OBJ.Import()` y sus calificadores para un directorio se tomaron de la [referencia oficial de `%SYSTEM.OBJ`](https://docs.intersystems.com/irisforhealthlatest/csp/documatic/%25CSP.Documatic.cls?CLASSNAME=%25SYSTEM.OBJ) y la [referencia de calificadores](https://docs.intersystems.com/irislatest/csp/docbook/DocBook.UI.Page.cls/documatic/changes/history/history/DocBook.UI.Page.cls?KEY=RCOS_vsystem_flags_qualifiers); la nota también aparece junto al comando en `scripts/demo_objetos.sh`.

La consulta SQL se ejecuta desde ObjectScript con `$SYSTEM.SQL.Execute` y muestra una fila de la tabla proyectada `Fixture.Partido`.

> encontrado en documentación oficial: Clase 10 muestra un `SELECT` sobre clases persistentes, pero no explica cómo ejecutarlo desde ObjectScript/Terminal. La invocación de `$SYSTEM.SQL.Execute()` y `%Display()` se tomaron de [Using the SQL Shell Interface](https://docs.intersystems.com/irislatest/csp/docbook/DocBook.UI.Page.cls/documatic/changes/DocBook.UI.Page.cls?KEY=GSQL_shell), anotada también junto a la consulta en `Fixture.Demo.cls`. Esa página describe `RUN` para archivos SQL, pero la demo no necesita un archivo `.sql` separado.

La salida esperada incluye mensajes de guardado con ID, navegación `Partido → Evento` y `Evento → Partido`, una fila SQL, confirmación del borrado en cascada y rechazo del evento inválido. El guardado de Jugador sin `Nombre` devuelve un `%Status` de error esperado por `[Required]`.

Para repetir la demostración, ejecutar el mismo script. Cada ejecución crea nuevos objetos demostrativos en la base durable; no borra los registros creados por ejecuciones anteriores, salvo el Partido de prueba `P-BORRAR` y su Evento hijo.

## Evidencia

La transcripción de una ejecución se conserva en [`evidencia/ejecucion_demo.txt`](evidencia/ejecucion_demo.txt). [`evidencia/ambiente.txt`](evidencia/ambiente.txt) registra el contenedor levantado. [`evidencia/persistencia.txt`](evidencia/persistencia.txt) muestra una consulta del Partido luego de reiniciar el servicio. La evidencia refleja la instancia local y no constituye una medición de rendimiento.

## Estructura

- `docker-compose.yml`: servicio IRIS Community y volumen persistente local.
- `scripts/*.cls`: definiciones del dominio y método de demostración.
- `scripts/demo_objetos.sh`: carga y ejecución desde Terminal.
- `docs/`: modelo de objetos y matriz de integridad.
- `evidencia/`: salida textual de la ejecución local.
