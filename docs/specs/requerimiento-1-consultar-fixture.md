# Plan de implementación — Requerimiento 1: consultar el fixture

**Fecha:** 6 de noviembre de 2026.

**Estado:** implementado el endpoint, seed y caché; ver la guía `fixture2030-mongo/README.md` y `idd-2-backend/docs/fixture.md` para reproducción. La sección de situación actual conserva el diagnóstico previo al cambio.

**Interpretación:** corresponde al caso de uso 1 de [Casos de uso — Fixture Mundial 2030](../casos-de-uso-fixture.md), no a la numeración de los casos del backend del Hito 10.

## Objetivo y alcance

Un visitante puede consultar los partidos del Mundial 2030 ordenados por fecha y horario, con sus equipos, fase, estado y resultado disponible. La entrega es una API sin login ni frontend, según los [lineamientos](../lineamientos-entrega-demo.md) y el [modelo técnico](../modelo-tecnico-demo.md).

Esta implementación incorpora `GET /fixture`, la persistencia mínima de partidos en MongoDB, una carga reproducible y caché en Redis. No requiere InfluxDB. Quedan para otros incrementos el detalle de partido, las alineaciones, los eventos, la clasificación, la resolución de playoffs y el simulador. Tampoco incluye retirar los adaptadores anteriores: las rutas existentes continúan funcionando durante esta transición.

## Situación actual verificada

- El backend está en `/Users/mateolewinzon/code/mateo/idd-2-backend`, separado de este repositorio de datos y documentación.
- Su arquitectura ya separa rutas, schemas, servicios y adaptadores. `app/adapters/mongo_adapter.py` consulta equipos y jugadores; `app/adapters/redis_adapter.py` opera sesiones y todavía no ofrece caché de respuestas.
- `app/routes/partidos.py` publica el detalle y los eventos desde Neo4j; no existe una ruta `/fixture`. Su schema de detalle usa `fecha` de tipo fecha, sin horario, estado ni resultado.
- En este repositorio, `fixture2030-mongo/mongo/01-setup-colecciones.js` crea equipos y jugadores, pero no partidos.
- `fixture2030-neo4j/import/partidos.csv` aporta `id`, `fase`, `grupo`, `fecha` y `sede_id`. Los equipos y su condición salen de `participaciones.csv`; los nombres se resuelven con `equipos.csv` y `sedes.csv`.
- Ese CSV no aporta horario, estado ni marcador. No se deben deducir estados por comparación con la fecha del sistema ni presentar resultados desconocidos como 0–0.
- El backend convierte entradas inválidas en HTTP 400 y usa un formato de error común con `requestId`; el nuevo endpoint debe conservarlo.

## Contrato propuesto

### Consulta

`GET /fixture` devuelve el fixture completo en una única respuesta. Para el tamaño acotado del dataset de esta demo no se agrega paginación. Los filtros `equipo_id`, `fecha` y `fase` propuestos por el modelo técnico se dejan para el incremento de consultas filtradas; no son necesarios para el caso 1.

Orden ascendente por `fecha_hora`, con desempate por código de partido. La fecha y hora se transportan en UTC con sufijo `Z`. Una interfaz futura podrá convertirlas a la zona del visitante.

```json
{
  "items": [
    {
      "codigo": "P-002",
      "fecha_hora": "2030-06-09T18:00:00Z",
      "fase": "Grupos",
      "grupo": "J",
      "local": {"codigo": "ARG", "nombre": "Argentina"},
      "visitante": {"codigo": "JOR", "nombre": "Jordania"},
      "estado": "proximo",
      "resultado": null
    }
  ]
}
```

El horario del ejemplo es ilustrativo: debe cargarse expresamente como dato simulado, sin atribuirlo al calendario oficial de 2030.

| Campo | Regla |
| --- | --- |
| `codigo` | Identificador estable existente, formato `P-NNN`. |
| `fecha_hora` | Instante completo obligatorio, con zona horaria; nunca completar silenciosamente con medianoche. |
| `fase` | Nombre de la fase según el dataset de la demo. |
| `grupo` | Código del grupo o `null` en eliminatorias. |
| `local`, `visitante` | Referencias con código y nombre. Si una plaza aún no está resuelta, su referencia es `null`; no inventar un equipo. La descripción del origen de plazas corresponde al futuro contrato de playoffs. |
| `estado` | Enum `proximo`, `en_vivo`, `finalizado`. Es un estado persistido, controlado por la carga o por la futura ingesta. |
| `resultado` | `null` antes de jugar. En vivo o finalizado: objeto con `goles_local`, `goles_visitante` y `penales` opcional/nulo; la tanda se mantiene separada de los goles de juego. |

Respuestas: 200 con `items` ordenados, incluso cuando la colección está vacía; 503 si MongoDB no está disponible y no hay caché válida; 504 para timeout de MongoDB conforme al manejo vigente. No hay 404 para una colección vacía. Los errores conservan `code`, `message`, `requestId` y `X-Request-Id`. Una caché válida puede responder aunque MongoDB esté caído.

## Persistencia y preparación del dataset

Crear `partidos` en MongoDB con `_id` como código, `fecha_hora` como BSON Date, fase, grupo, referencias mínimas de equipos, sede, estado, resultado y `actualizado_en`. Usar referencias embebidas con código y nombre para resolver el listado en una consulta, sin una consulta adicional por cada partido. La sede se conserva para futuros casos, aunque el listado mínimo no la devuelve.

Agregar validación estricta de tipos, estados, identificadores y marcadores enteros no negativos. El cargador valida también que un partido próximo tenga resultado nulo y que uno en vivo o finalizado tenga marcador. Un índice compuesto `{fecha_hora: 1, _id: 1}` soporta el orden; `_id` ya garantiza unicidad. Los índices por selección se incorporarán al implementar sus filtros.

Preparar una fuente complementaria versionada en `fixture2030-mongo/datos/` que asigne horarios simulados, estados iniciales y resultados explícitos. Mantener inicialmente todos los partidos como próximos es válido para la carga base; un escenario de prueba separado debe incluir los tres estados. Validar referencias, una sola participación por condición y equipos distintos; cualquier plaza no resuelta debe estar declarada como tal. Informar inconsistencias antes de escribir.

La carga debe:

1. Leer partidos, participaciones, equipos y sedes desde los CSV existentes sin requerir un servidor Neo4j.
2. Combinar esos datos con la fuente complementaria y validar el conjunto completo antes de persistirlo.
3. Crear o actualizar la colección y sus índices, reutilizando la estructura de scripts de MongoDB.
4. Insertar o actualizar por `_id`, sin duplicados al ejecutar dos veces. La recarga ordinaria actualiza datos del calendario y preserva estado y marcador ya modificados por una simulación; el reinicio explícito del escenario de demo restaura esos valores. No eliminar partidos ajenos a la carga ni borrar colecciones.
5. Invalidar la caché tras una carga exitosa y mostrar cantidades de registros insertados, actualizados y rechazados. No informar éxito si la carga queda incompleta.

Mantener los CSV donde están durante este incremento; documentar la dependencia. Su traslado se hará al retirar la carpeta de Neo4j del entregable.

## Lectura y caché

Flujo: ruta → servicio de fixture → Redis → MongoDB ante ausencia de caché → serialización y almacenamiento con TTL → respuesta.

- Clave propuesta: `fixture:v1:todos`. El prefijo versiona el contrato y evita colisiones con sesiones.
- TTL inicial configurable de **5 segundos**, una propuesta a medir, porque la respuesta completa puede contener partidos en vivo. Los TTL largos del fixture estático se pueden evaluar más adelante si se separan las respuestas dinámicas.
- Guardar únicamente el cuerpo de respuesta validado; no cachear encabezados o identificadores de request, errores ni fallos de origen.
- Redis caído o payload inválido: tratarlo como fallo de caché, registrar el problema y consultar MongoDB. Un fallo al guardar en Redis no convierte una lectura exitosa en error.
- No devolver entradas vencidas mediante un mecanismo adicional de datos obsoletos en esta versión.
- Invalidar la clave después de confirmar cambios de horario, equipos, fase, estado o marcador en MongoDB. El futuro simulador debe invocar el mismo mecanismo en inicio, goles, cierre y correcciones.
- Si una invalidación falla, el TTL limita la antigüedad. Una lectura concurrente puede repoblar un valor anterior: en este incremento se acepta esa ventana de hasta el TTL, también al actualizar el marcador. No se promete invalidación atómica entre las bases ni lectura monótona.

Hasta que exista una ingesta en vivo, las transiciones se verifican mediante datos de integración y el reinicio explícito del escenario, sin agregar endpoints públicos de escritura solo para la demo.

## Secuencia de implementación

| Paso | Repositorio / archivos previstos | Resultado verificable |
| --- | --- | --- |
| 1. Preparar datos | Este repositorio: `fixture2030-mongo/datos/`, scripts de carga y README. | Dataset con horarios explícitos y referencias validadas; escenario con los tres estados. |
| 2. Persistir partidos | Este repositorio: extender `fixture2030-mongo/mongo/01-setup-colecciones.js` y agregar carga de partidos sin renumerar scripts existentes. | Validadores e índice creados; dos cargas no duplican partidos ni reinician una simulación. |
| 3. Definir respuesta | Backend: nuevo `app/schemas/fixture.py`. | Schema de listado y resultado, con ejemplos para los tres estados y plazas pendientes. Reutilizar `EquipoRef` si conserva su contrato. |
| 4. Consultar MongoDB | Backend: extender `app/adapters/mongo_adapter.py`. | Método de listado con proyección mínima y orden estable; traducción de errores y observación existentes. |
| 5. Implementar caché | Backend: extender `app/adapters/redis_adapter.py` y `app/config/settings.py`; documentar TTL en `.env.example`. | Lectura, escritura con expiración e invalidación de la clave; degradación a MongoDB ante fallos de Redis. |
| 6. Exponer el caso de uso | Backend: nuevos `app/services/fixture_service.py`, `app/routes/fixture.py` y registro en `app/main.py`. | `GET /fixture` aplica el flujo completo y los errores comunes. |
| 7. Sincronizar contratos | Backend: OpenAPI, Postman, README y documentación afectada. | Contratos coherentes con la ruta implementada y ejemplos ejecutables. |
| 8. Verificar y registrar evidencia | Ambos repositorios: pruebas pertinentes y guía de ejecución. | Evidencia reproducible de carga, consulta, caché e indisponibilidad. |

Los pasos 3 a 6 deben seguir las convenciones de importación y dependencias del backend. No reemplazar el servicio de partidos de Neo4j como efecto secundario de agregar el listado.

## Pruebas y criterios de aceptación

- **Contenido y orden:** aparecen todos los partidos cargados; fechas y horas ordenadas ascendentemente, con desempate estable. Equipos y fase coinciden con las fuentes.
- **Estados y resultados:** representar próximo sin marcador, en vivo con marcador parcial y finalizado con resultado final; separar tanda y goles de juego. Verificar plazas pendientes sin equipos ficticios.
- **Vacío:** una base sin partidos produce 200 y `items: []`.
- **Integridad de carga:** rechazar horario sin zona, referencia rota, condición duplicada, estado inválido y marcador negativo antes de persistir. Dos cargas mantienen las mismas identidades y preservan un marcador actualizado; el reinicio explícito sí lo restaura.
- **Caché:** primera consulta accede a MongoDB; la siguiente dentro del TTL obtiene el mismo cuerpo sin consultarlo. Verificar TTL, expiración e invalidación después de una carga o actualización controlada.
- **Fallos:** Redis detenido permite consultar MongoDB; MongoDB detenido con caché válida permite responder; sin caché válida devuelve 503 o 504 según la causa, con el formato común. Una respuesta de error no queda cacheada.
- **Regresión:** ejecutar las pruebas existentes que cubren contratos, adaptadores y manejo de fallos, además de las nuevas pruebas focalizadas del fixture. Las rutas previas conservan su comportamiento.
- **Consulta real:** registrar `explain` del listado y comprobar el uso del índice para el orden. Registrar latencia con caché fría y caliente como evidencia local; no afirmar que esto demuestra los objetivos globales de concurrencia o P95.
- **Contrato publicado:** regenerar `openapi/openapi.yaml` con `python scripts/exportar_openapi.py` usando el entorno del backend; agregar la operación a `postman_collection.json`, conservando `baseUrl`, y verificar que ambos artefactos coincidan en operaciones y parámetros.

Las pruebas de servicio pueden usar dobles para contar accesos a los adaptadores; las de integración deben usar MongoDB y Redis reales para comprobar tipos de fecha, validadores, orden, TTL y fallos. No hacen falta Neo4j ni InfluxDB para la nueva consulta, aunque la suite general pueda requerirlos por sus casos existentes.

## Condición de cierre

El incremento está completo cuando una instalación documentada permite cargar el dataset y consultar `GET /fixture` con los campos acordados, los tres estados tienen cobertura, funcionan la caché y su degradación, pasan las verificaciones relevantes y los contratos del backend están sincronizados según su `AGENTS.md`. La entrega debe registrar los horarios como simulados y la antigüedad posible del listado como acotada por el TTL configurado.
