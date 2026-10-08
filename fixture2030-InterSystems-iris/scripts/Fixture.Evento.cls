Class Fixture.Evento Extends %Persistent
{
Property Tipo As %String [Required];
Property Minuto As %Integer [Required];
Relationship Partido As Fixture.Partido
    [ Cardinality = parent, Inverse = Eventos ];

Index idxPartido On Partido;
}
