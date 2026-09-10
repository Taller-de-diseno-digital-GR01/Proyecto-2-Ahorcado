# Manejo del teclado en modo crudo, ver docs/diseño/APP_PC.md
# Sin esto habría que darle Enter a cada letra, y la FPGA responde tecla por tecla.

import sys
import termios
import tty
from contextlib import contextmanager

ESCAPE = "\x1b"
FIN_DE_ARCHIVO = "\x04"  # Ctrl-D


@contextmanager
def modo_crudo(flujo=sys.stdin):
    """Deja el teclado sin buffer de línea y sin eco, y lo devuelve como estaba al salir."""
    if not flujo.isatty():  # con la entrada redirigida no hay nada que configurar
        yield
        return
    guardado = termios.tcgetattr(flujo)
    try:
        tty.setcbreak(flujo.fileno())  # cbreak y no raw, así Ctrl-C sigue siendo Ctrl-C
        yield
    finally:
        termios.tcsetattr(flujo, termios.TCSADRAIN, guardado)


def leer_tecla(flujo=sys.stdin):
    return flujo.read(1)
