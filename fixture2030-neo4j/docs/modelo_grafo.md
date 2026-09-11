1. El problema relacional

    Para evidenciar la necesidad de un modelo de grafos, nos basamos en las siguientes preguntas:
    1. Quién fue el maximo goleador de un equipo?
    2. Qué equipo tiene la mayor cantidad de goles anotados?
    3. Qué jugadores titulares recibieron asistencias de jugadores que ingresaron desde el banco en un mismo estadio?
    4. Qué sede actuó como el 'hub' principal del torneo, albergando la mayor cantidad de equipos distintos?

2. Inventario de Nodos y Propiedades

    * Equipo
        * id -> código FIFA al igual que en la base de Mongo.
        * nombre -> Nombre del equipo.
    
    * Jugador
        * id -> codigo FIFA + dorsal del jugador al igual que en la base de Mongo.
        * apellido -> Apellido del jugador.
    
    * Partido
        * id -> P-XXX (Ej: P-001)
        * fase -> Fase del torneo (ej: Fase de Grupos)
        * fecha -> Fecha del partido (ej: 2030-07-21)
            
    * Sede
        * id -> S-XX (Ej: S-01)
        * nombre -> Nombre de la sede (ej: Estadio Azteca)
        * ciudad -> Ciudad donde se encuentra la sede (ej: Ciudad de México)
    
    * Evento
        * id -> E-XXXX (Ej: E-0001)
        * tipo -> Tipo de evento (ej: Gol, Asistencia, Tarjeta Amarilla, Tarjeta Roja)
        * minuto -> Minuto en el que ocurrio el evento

3. Inventario de Relaciones y Propiedades

| Nodo Origen | Relación (Cypher) | Nodo Destino | Cardinalidad | Propiedades en la Relación | Justificación (RF4) |
| :---         | :---               | :---         | :---         | :---                         | :---                |
| `(Jugador)`  | `[:PERTENECE_A]`   | `(Equipo)`   | Muchos a Uno | N/A                          | Expresa la pertenencia de jugadores a equipos. |
| `(Equipo)`   | `[:PARTICIPA_EN]`  | `(Partido)`  | Muchos a Muchos | `condicion` (Local / Visitante) | Expresa la participación de equipos en partidos. |
| `(Partido)`  | `[:SE_DISPUTA_EN]` | `(Sede)`     | Muchos a Uno | N/A                          | Expresa la programación de partidos en una sede. |
| `(Evento)`   | `[:OCURRE_EN]`     | `(Partido)`  | Muchos a Uno | N/A                          | Expresa la vinculación de eventos con el partido correspondiente. |
| `(Jugador)`  | `[:PROTAGONIZA]`   | `(Evento)`   | Uno a Muchos | N/A                          | Conecta al jugador con su acción (necesario para buscar goleadores y asistentes). |

