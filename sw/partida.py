# Espejo de lo que la FPGA ya decidió, ver docs/diseño/APP_PC.md
# Acá no se decide nada de la partida, solo se guarda lo último que dijo cada trama.

import protocolo

ESPERANDO = "esperando"
JUGANDO = "jugando"
TERMINADA = "terminada"


class Partida:

    def __init__(self):
        self.fase = ESPERANDO
        self.modo = None
        self.largo = 0
        self.patron = []
        self.intentos = 0
        self.causa = None

    @property
    def restantes(self):
        return protocolo.MAX_INTENTOS - self.intentos

    def aplicar(self, evento):
        if isinstance(evento, protocolo.Inicio):
            self._arrancar(evento)
        elif isinstance(evento, protocolo.Letra):
            self.intentos = evento.intentos
        elif isinstance(evento, protocolo.Fin):
            self.fase = TERMINADA
            self.causa = evento.causa

    def _arrancar(self, evento):
        self.fase = JUGANDO
        self.modo = evento.modo
        self.largo = evento.largo
        self.patron = ["_"] * evento.largo
        self.intentos = 0
        self.causa = None
