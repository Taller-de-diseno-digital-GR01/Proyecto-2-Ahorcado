# Pintado de la pantalla, ver docs/diseño/APP_PC.md
# Todo lo que se muestra sale de lo que la FPGA ya mandó, salvo la resta de intentos restantes.

import dibujo
import partida
import protocolo

LIMPIAR = "\x1b[2J\x1b[H"

MODOS = {protocolo.MODO_FACIL: "FACIL", protocolo.MODO_DIFICIL: "DIFICIL"}

RESULTADOS = {
    protocolo.ACIERTO: ("correcta", "verde"),
    protocolo.FALLO: ("no está", "rojo"),
    protocolo.REPETIDA: ("repetida", "amarillo"),
}

FINALES = {
    protocolo.GANO: ("GANASTE", "verde"),
    protocolo.PERDIO_INTENTOS: ("PERDISTE, se acabaron los intentos", "rojo"),
    protocolo.PERDIO_TIEMPO: ("PERDISTE, se acabó el tiempo", "rojo"),
}


def dibujar(juego):
    print(LIMPIAR + "\n".join(_lineas(juego)))


def _lineas(juego):
    cabecera = dibujo.pintar("  A H O R C A D O", "fuerte")
    if juego.modo is not None:
        cabecera += "   " + dibujo.pintar(MODOS.get(juego.modo, "?"), "azul")
    lineas = ["", cabecera, ""]
    if juego.fase == partida.ESPERANDO:
        lineas += _espera()
    else:
        lineas += _tablero(juego)
    lineas.append("")
    lineas.append(dibujo.pintar("  una tecla A-Z para jugar, ESC para salir", "gris"))
    return lineas


def _espera():
    return ["  Esperando a que arranque la partida.",
            "",
            dibujo.pintar("  Elegí el modo con el botón Seleccionar y confirmá con el botón OK en la tarjeta.", "gris")]


def _tablero(juego):
    derecha = _panel(juego)
    muneco = dibujo.muneco(juego.intentos)
    lineas = []
    for indice in range(max(len(muneco), len(derecha))):  # el panel puede ser más alto que el muñeco
        izquierda = muneco[indice] if indice < len(muneco) else " " * len(muneco[0])
        texto = derecha[indice] if indice < len(derecha) else ""
        lineas.append(("   %s     %s" % (izquierda, texto)).rstrip())
    return lineas


def _panel(juego):
    palabra = " ".join(juego.patron)
    gastados = "✕" * juego.intentos + "·" * juego.restantes
    filas = ["", dibujo.pintar(palabra, "fuerte"), "",
             "intentos  %s  %d de %d" % (gastados, juego.intentos, protocolo.MAX_INTENTOS)]
    if juego.erradas:
        filas.append("erradas   " + dibujo.pintar(" ".join(juego.erradas), "rojo"))
    if juego.ultima and juego.ultima[0] is not None:
        letra, resultado = juego.ultima
        texto, color = RESULTADOS.get(resultado, ("?", "gris"))
        filas.append("última    %s, %s" % (letra, dibujo.pintar(texto, color)))
    if juego.fase == partida.TERMINADA:
        texto, color = FINALES.get(juego.causa, ("fin de partida", "gris"))
        filas.append("")
        filas.append(dibujo.pintar(texto, color))
    return filas
