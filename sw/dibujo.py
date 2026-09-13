# El muñeco y los colores, ver docs/diseño/APP_PC.md
# Se dibuja a partir de los intentos que reportó la FPGA, la app no cuenta nada por su cuenta.

import os
import sys

MUNECO = [ # TODO: Revisar que esto sirva (JOE)
    ["  ┌────┐ ", "  │      ", "  │      ", "  │      ", "  │      ", "──┴──    "],
    ["  ┌────┐ ", "  │    │ ", "  │      ", "  │      ", "  │      ", "──┴──    "],
    ["  ┌────┐ ", "  │    │ ", "  │    o ", "  │      ", "  │      ", "──┴──    "],
    ["  ┌────┐ ", "  │    │ ", "  │    o ", "  │    │ ", "  │      ", "──┴──    "],
    ["  ┌────┐ ", "  │    │ ", "  │    o ", "  │   /│ ", "  │      ", "──┴──    "],
    ["  ┌────┐ ", "  │    │ ", "  │    o ", "  │   /│\\", "  │      ", "──┴──    "],
    ["  ┌────┐ ", "  │    │ ", "  │    o ", "  │   /│\\", "  │   / \\", "──┴──    "],
]

COLORES = {
    "rojo": "\x1b[31m",
    "verde": "\x1b[32m",
    "amarillo": "\x1b[33m",
    "azul": "\x1b[34m",
    "gris": "\x1b[90m",
    "fuerte": "\x1b[1m",
}
NORMAL = "\x1b[0m"


def hay_color():
    return sys.stdout.isatty() and "NO_COLOR" not in os.environ


def pintar(texto, color):
    if not hay_color():
        return texto
    return "%s%s%s" % (COLORES[color], texto, NORMAL)


def muneco(intentos):
    return MUNECO[min(intentos, len(MUNECO) - 1)]
