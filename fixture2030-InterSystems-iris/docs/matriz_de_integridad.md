# Matriz de integridad — Hito 9 (IRIS)

| Regla | Garantía del modelo | Cómo se demostrará |
| --- | --- | --- |
| Campos requeridos | `Nombre` en Persona; `Numero` y `Posicion` en Jugador; `Rol` en Árbitro; `Codigo` y `Estado` en Partido; `Tipo` y `Minuto` en Evento deben cumplir sus declaraciones requeridas y tipadas. | Intentar guardar deliberadamente un objeto incompleto y conservar el error controlado en la evidencia, sin dejar el objeto parcial. |
| Herencia | Jugador y Árbitro extienden la clase persistente Persona y comparten sus datos personales. | Crear y recuperar instancias de ambos tipos; verificar que atributos heredados y propios coexisten. |
| Relación inversa | Partido declara su colección de Eventos y Evento señala a un Partido, con las propiedades inversas declaradas en ambos extremos. | Recorrer la colección desde Partido y la referencia desde Evento. |
| Índice del lado muchos | Evento incluye un índice sobre su propiedad relacional `Partido`. | Inspeccionar la definición compilada y documentar el índice en la evidencia de estructura. |
| Ciclo de vida padre-hijo | Un Evento depende de su Partido; al eliminar el padre, los eventos subordinados se eliminan en cascada. | Crear el árbol, eliminar el padre de prueba y mostrar que ya no quedan sus eventos. |
| Guardado del árbol | Un solo guardado del Partido coordina los objetos modificados alcanzables en el árbol. Si falla una validación, no debe quedar guardado parcialmente. | Crear Partido y Evento en memoria, guardar solo el padre y reabrir/navegar el resultado; repetir con una falla controlada. |
| Transición inválida | No se puede agregar un Evento en minuto 0 a un Partido con estado `Finalizado`. | Ejecutar la operación encapsulada con ese caso y mostrar el rechazo. |
| Fuentes de verdad del Fixture | Las instancias IRIS de Jugador, Partido y Evento son datos de demostración de Hito 9. MongoDB conserva Jugadores; Neo4j conserva Partidos y Eventos. | Usar IDs de negocio existentes y documentar que IRIS no es una migración ni sincronización de esos dominios. |

## Efecto de borrar el padre

La relación `Partido`–`Evento` usa el patrón padre-hijo de Clase 10: el hijo no sobrevive de forma independiente y la eliminación del padre elimina sus hijos subordinados. Esta cascada se limita a Eventos de ese Partido; no alcanza a Jugadores, Equipos ni a entidades de las demás bases.

## Atomicidad y errores

La prueba de guardado construye un árbol nuevo y persiste solo el Partido. Una salida exitosa debe permitir abrir el Partido y navegar a sus Eventos. La prueba de error omite una propiedad marcada como requerida o ejecuta la validación de minuto/estado; registra el estado devuelto por IRIS y verifica que no haya quedado persistido un árbol incompleto. No se declara verificada la atomicidad hasta que exista esa evidencia.
