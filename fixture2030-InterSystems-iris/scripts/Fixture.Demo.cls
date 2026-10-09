Class Fixture.Demo
{
ClassMethod Ejecutar()
{
    Set jugador = ##class(Fixture.Jugador).%New()
    Set jugador.Nombre = "Jugador Demo"
    Set jugador.Apellido = "Fixture"
    Set jugador.Numero = 99
    Set jugador.Posicion = "Delantero"
    Set sc = jugador.%Save()
    Write "Guardado de Jugador: ", sc, " — ID ", jugador.%Id(), !

    Set arbitro = ##class(Fixture.Arbitro).%New()
    Set arbitro.Nombre = "Arbitro Demo"
    Set arbitro.Rol = "Principal"
    Set arbitro.LicenciaFIFA = 1
    Set sc = arbitro.%Save()
    Write "Guardado de Arbitro: ", sc, " — ID ", arbitro.%Id(), !

    Set partido = ##class(Fixture.Partido).%New()
    Set partido.Codigo = "P-001"
    Set partido.Estado = "Finalizado"

    Set evento = ##class(Fixture.Evento).%New()
    Set evento.Tipo = "Gol"
    Set evento.Minuto = 15
    Set aceptado = ##class(Fixture.Partido).AgregarEvento(partido,evento)
    If 'aceptado {
        Write "Error: el evento valido fue rechazado", !
        Quit
    }

    Set sc = partido.%Save()
    Write "Guardado del Partido con su Evento: ", sc, " — Partido ", partido.%Id(), !
    Write "Evento vinculado: ", evento.%Id(), !
    Set recuperado = ##class(Fixture.Partido).%OpenId(partido.%Id())
    Set eventoRecuperado = recuperado.Eventos.GetAt(1)
    Write "Navegacion Partido a Evento: ", eventoRecuperado.Tipo, " minuto ", eventoRecuperado.Minuto, !
    Write "Navegacion Evento a Partido: ", eventoRecuperado.Partido.Codigo, !

    // encontrado en documentación oficial: $SYSTEM.SQL.Execute ejecuta SQL desde ObjectScript.
    Set resultadoSQL = $SYSTEM.SQL.Execute("SELECT TOP 1 Codigo, Estado FROM Fixture.Partido WHERE Codigo = 'P-001' ORDER BY ID DESC")
    Do resultadoSQL.%Display()

    Set partidoBorrado = ##class(Fixture.Partido).%New()
    Set partidoBorrado.Codigo = "P-BORRAR"
    Set partidoBorrado.Estado = "Programado"
    Set eventoBorrado = ##class(Fixture.Evento).%New()
    Set eventoBorrado.Tipo = "Tarjeta"
    Set eventoBorrado.Minuto = 20
    Do partidoBorrado.Eventos.Insert(eventoBorrado)
    Set sc = partidoBorrado.%Save()
    Set idEventoBorrado = eventoBorrado.%Id()
    Set sc = ##class(Fixture.Partido).%DeleteId(partidoBorrado.%Id())
    Set eventoLuegoDeBorrar = ##class(Fixture.Evento).%OpenId(idEventoBorrado)
    If '$IsObject(eventoLuegoDeBorrar) Write "Borrado en cascada confirmado para Evento subordinado", !

    Set eventoInvalido = ##class(Fixture.Evento).%New()
    Set eventoInvalido.Tipo = "Gol"
    Set eventoInvalido.Minuto = 0
    Set aceptado = ##class(Fixture.Partido).AgregarEvento(partido,eventoInvalido)
    If 'aceptado Write "Validacion correcta: evento rechazado para Partido Finalizado", !

    Set jugadorInvalido = ##class(Fixture.Jugador).%New()
    Set jugadorInvalido.Numero = 99
    Set jugadorInvalido.Posicion = "Delantero"
    Set sc = jugadorInvalido.%Save()
    Write "Validacion requerida al guardar Jugador sin Nombre:", !
    Do $System.Status.DisplayError(sc)
}
}
