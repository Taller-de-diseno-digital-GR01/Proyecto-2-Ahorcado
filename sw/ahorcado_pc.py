#!/usr/bin/env python3
# Terminal remota del ahorcado, ver docs/diseño/APP_PC.md
# Toda la lógica del juego vive en la FPGA, acá solo se manda la tecla y se pinta lo que llega.

import argparse
import select
import sys

import enlace
import partida
import protocolo
import terminal
import vista


def opciones():
    cli = argparse.ArgumentParser(description="Terminal remota del ahorcado de la Basys 3")
    cli.add_argument("-p", "--puerto", help="puerto serial, si no se da se busca la tarjeta sola")
    cli.add_argument("-b", "--baudios", type=int, default=enlace.BAUDIOS)
    cli.add_argument("-l", "--lista", action="store_true", help="lista los puertos de la tarjeta y sale")
    return cli.parse_args()


def listar():
    puertos = enlace.puertos_de_la_tarjeta()
    if not puertos:
        print("No se detecta ninguna Basys 3.")
        return
    for puerto in puertos:
        print("%s  %s" % (puerto.device, puerto.description))


def jugar(puerto):
    decodificador = protocolo.Decodificador()
    juego = partida.Partida()
    with terminal.modo_crudo():
        vista.dibujar(juego)
        while True:
            listos, _, _ = select.select([sys.stdin, puerto], [], [])
            if sys.stdin in listos and not tecla(puerto, juego):
                return
            if puerto in listos:
                for evento in decodificador.alimentar(puerto.read(64)):
                    juego.aplicar(evento)
                vista.dibujar(juego)


def tecla(puerto, juego):
    """Manda la letra si viene al caso, y devuelve False cuando el jugador quiere salir."""
    pulsada = terminal.leer_tecla()
    if pulsada in ("", terminal.ESCAPE, terminal.FIN_DE_ARCHIVO):
        return False
    byte = protocolo.codificar_letra(pulsada)
    # fuera de partida la FPGA descarta el byte igual, mandarlo solo descuadraría la cola de enviadas
    if byte is not None and juego.fase == partida.JUGANDO:
        puerto.write(byte)
        juego.letra_enviada(pulsada.upper())
    return True


def main():
    args = opciones()
    if args.lista:
        listar()
        return 0
    try:
        puerto = enlace.abrir(args.puerto, args.baudios)
    except enlace.ErrorEnlace as error:
        print("Error, %s" % error, file=sys.stderr)
        return 1
    try:
        jugar(puerto)
    except KeyboardInterrupt:
        pass
    finally:
        puerto.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
