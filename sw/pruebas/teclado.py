# Chequeo manual del teclado, no es unittest. Correr con make test-teclado desde una terminal normal.
import sys

import protocolo
import terminal


def main():
    if not sys.stdin.isatty():
        print("Ojo, la entrada no es una terminal, no va a haber tecleo.")
    print("Apretá teclas para ver el byte que saldría hacia la FPGA, ESC para salir.")
    with terminal.modo_crudo():
        while True:
            tecla = terminal.leer_tecla()
            if tecla in ("", terminal.ESCAPE, terminal.FIN_DE_ARCHIVO):
                return
            print("%r -> %s" % (tecla, protocolo.codificar_letra(tecla)))


if __name__ == "__main__":
    main()
