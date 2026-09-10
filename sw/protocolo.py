# Codificación y decodificación de las tramas del enlace, ver docs/diseño/APP_PC.md
# El formato lo fija src/design/transmisor_uart.sv, si cambia allá hay que cambiarlo acá.
# Este archivo es puro, no toca el puerto ni la pantalla, y por eso se puede probar sin tarjeta.

from collections import namedtuple

CAB_INICIO = 0x49  # "I"
CAB_LETRA = 0x4C   # "L"
CAB_FIN = 0x46     # "F"

# Cuántos bytes trae cada trama detrás de la cabecera
CUERPOS = {CAB_INICIO: 2, CAB_LETRA: 4, CAB_FIN: 1}

FALLO = 0
ACIERTO = 1
REPETIDA = 2

MODO_FACIL = 0
MODO_DIFICIL = 1

GANO = 3
PERDIO_INTENTOS = 4
PERDIO_TIEMPO = 5

MAX_INTENTOS = 6

Inicio = namedtuple("Inicio", "modo largo")
Letra = namedtuple("Letra", "resultado intentos mascara")
Fin = namedtuple("Fin", "causa")


def _armar(cabecera, cuerpo):
    if cabecera == CAB_INICIO:
        return Inicio(modo=cuerpo[0], largo=cuerpo[1])
    if cabecera == CAB_LETRA:
        # la máscara viaja en dos bytes, el poco significativo primero
        return Letra(resultado=cuerpo[0], intentos=cuerpo[1],
                     mascara=cuerpo[2] | (cuerpo[3] << 8))
    return Fin(causa=cuerpo[0])


class Decodificador:
    """Máquina de estados sobre el flujo de bytes, porque las tramas son de largo variable."""

    def __init__(self):
        self.descartados = 0
        self._cabecera = None
        self._cuerpo = bytearray()

    def alimentar(self, datos):
        """Come los bytes que hayan llegado y devuelve las tramas completas que salieron."""
        eventos = []
        for byte in datos:
            evento = self._comer(byte)
            if evento is not None:
                eventos.append(evento)
        return eventos

    def _comer(self, byte):
        if self._cabecera is None:
            # Botar lo que no sea cabecera es lo que resincroniza la app cuando abre a media trama
            if byte not in CUERPOS:
                self.descartados += 1
                return None
            self._cabecera = byte
            self._cuerpo.clear()
            return None
        self._cuerpo.append(byte)
        if len(self._cuerpo) < CUERPOS[self._cabecera]:
            return None
        evento = _armar(self._cabecera, bytes(self._cuerpo))
        self._cabecera = None
        return evento

