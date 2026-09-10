#!/usr/bin/env python3
# Terminal remota del ahorcado, ver docs/diseño/APP_PC.md
# Toda la lógica del juego vive en la FPGA, acá solo se manda la tecla y se pinta lo que llega.

import argparse
import sys

import enlace
import protocolo


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
    print("Escuchando %s a %d baudios, Ctrl-C para salir." % (puerto.port, args.baudios))
    decodificador = protocolo.Decodificador()
    while True:
        datos = puerto.read(64)
        for evento in decodificador.alimentar(datos):
            print(evento)


if __name__ == "__main__":
    sys.exit(main())
