Class Fixture.Partido Extends %Persistent
{
Property Codigo As %String [Required];
Property Estado As %String [Required];
Relationship Eventos As Fixture.Evento
    [ Cardinality = children, Inverse = Partido ];

ClassMethod AgregarEvento(partido As Fixture.Partido, evento As Fixture.Evento) As %Boolean
{
    If '$IsObject(partido) {
        Quit 0
    }
    If '$IsObject(evento) {
        Quit 0
    }
    If partido.Estado = "Finalizado" {
        If evento.Minuto = 0 {
            Quit 0
        }
    }
    Do partido.Eventos.Insert(evento)
    Quit 1
}
}
