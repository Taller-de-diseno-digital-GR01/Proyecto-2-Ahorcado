# Espejo de lo que la FPGA ya decidió, ver docs/diseño/APP_PC.md
# Acá no se decide nada de la partida, solo se guarda lo último que dijo cada trama.

from collections import deque

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
        self.erradas = []
        self.ultima = None
        # La trama de letra no dice cuál letra era, así que se aparean en orden con las que salieron
        self.enviadas = deque()
        self._mascara = 0

    @property
    def restantes(self):
        return protocolo.MAX_INTENTOS - self.intentos

    def letra_enviada(self, letra):
        self.enviadas.append(letra)

    def aplicar(self, evento):
        if isinstance(evento, protocolo.Inicio):
            self._arrancar(evento)
        elif isinstance(evento, protocolo.Letra):
            self._letra(evento)
        elif isinstance(evento, protocolo.Fin):
            self.fase = TERMINADA
            self.causa = evento.causa
            self.enviadas.clear()

    def _arrancar(self, evento):
        self.fase = JUGANDO
        self.modo = evento.modo
        self.largo = evento.largo
        self.patron = ["_"] * evento.largo
        self.intentos = 0
        self.causa = None
        self.erradas = []
        self.ultima = None
        self.enviadas.clear()
        self._mascara = 0

    def _letra(self, evento):
        letra = self.enviadas.popleft() if self.enviadas else None
        self.intentos = evento.intentos
        self.ultima = (letra, evento.resultado)
        # Las posiciones que la máscara acaba de destapar son las de la letra que se mandó
        visibles = (1 << self.largo) - 1
        nuevas = evento.mascara & ~self._mascara & visibles
        self._mascara |= evento.mascara & visibles
        marca = letra if letra is not None else "?"  # si abrimos a media partida no sabemos cuál fue
        for posicion in range(self.largo):
            if nuevas >> posicion & 1:
                self.patron[posicion] = marca
        if evento.resultado == protocolo.FALLO and letra is not None and letra not in self.erradas:
            self.erradas.append(letra)
