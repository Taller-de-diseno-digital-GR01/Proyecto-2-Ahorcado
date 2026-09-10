# Pruebas del estado espejo, la palabra de ejemplo es BANANA de 6 letras
# Correr con: python3 -m unittest discover -s sw/pruebas -t sw

import unittest

import partida
import protocolo

# La máscara llega con el relleno de arriba en unos, tal como la deja comparador_letra.sv
RELLENO = 0b111111000000
NADA = RELLENO
CON_A = RELLENO | 0b101010
CON_A_Y_N = RELLENO | 0b111110
COMPLETA = 0b111111111111


def letra(resultado, intentos, mascara):
    return protocolo.Letra(resultado=resultado, intentos=intentos, mascara=mascara)


class PartidaTest(unittest.TestCase):

    def setUp(self):
        self.juego = partida.Partida()
        self.juego.aplicar(protocolo.Inicio(modo=protocolo.MODO_FACIL, largo=6))

    def jugar(self, tecla, evento):
        self.juego.letra_enviada(tecla)
        self.juego.aplicar(evento)

    def test_arranca_con_todo_tapado(self):
        self.assertEqual(self.juego.patron, ["_"] * 6)
        self.assertEqual(self.juego.fase, partida.JUGANDO)
        self.assertEqual(self.juego.restantes, protocolo.MAX_INTENTOS)

    def test_un_acierto_revela_todas_las_posiciones_de_la_letra(self):
        self.jugar("A", letra(protocolo.ACIERTO, 0, CON_A))
        self.assertEqual("".join(self.juego.patron), "_A_A_A")

    def test_el_relleno_de_arriba_no_se_pinta(self):
        self.jugar("A", letra(protocolo.ACIERTO, 0, CON_A))
        self.assertEqual(len(self.juego.patron), 6)  # los bits 6 a 11 vienen en uno y no son de la palabra

    def test_un_fallo_gasta_intento_y_queda_anotado(self):
        self.jugar("Z", letra(protocolo.FALLO, 1, NADA))
        self.assertEqual(self.juego.erradas, ["Z"])
        self.assertEqual(self.juego.restantes, 5)
        self.assertEqual("".join(self.juego.patron), "______")

    def test_una_repetida_no_cambia_nada(self):
        self.jugar("A", letra(protocolo.ACIERTO, 0, CON_A))
        self.jugar("A", letra(protocolo.REPETIDA, 0, CON_A))
        self.assertEqual("".join(self.juego.patron), "_A_A_A")
        self.assertEqual(self.juego.erradas, [])
        self.assertEqual(self.juego.restantes, protocolo.MAX_INTENTOS)

    def test_la_misma_errada_no_se_anota_dos_veces(self):
        self.jugar("Z", letra(protocolo.FALLO, 1, NADA))
        self.jugar("Z", letra(protocolo.REPETIDA, 1, NADA))
        self.assertEqual(self.juego.erradas, ["Z"])

    def test_cada_respuesta_se_aparea_con_la_letra_que_le_toca(self):
        self.juego.letra_enviada("A")
        self.juego.letra_enviada("N")
        self.juego.aplicar(letra(protocolo.ACIERTO, 0, CON_A))
        self.juego.aplicar(letra(protocolo.ACIERTO, 0, CON_A_Y_N))
        self.assertEqual("".join(self.juego.patron), "_ANANA")

    def test_completar_la_palabra(self):
        self.jugar("A", letra(protocolo.ACIERTO, 0, CON_A))
        self.jugar("N", letra(protocolo.ACIERTO, 0, CON_A_Y_N))
        self.jugar("B", letra(protocolo.ACIERTO, 0, COMPLETA))
        self.assertEqual("".join(self.juego.patron), "BANANA")

    def test_si_abrimos_a_media_partida_la_posicion_queda_en_interrogante(self):
        self.juego.aplicar(letra(protocolo.ACIERTO, 0, CON_A))  # nadie mandó esa letra desde acá
        self.assertEqual("".join(self.juego.patron), "_?_?_?")

    def test_el_fin_deja_la_causa_y_corta_la_cola(self):
        self.juego.letra_enviada("Q")
        self.juego.aplicar(protocolo.Fin(causa=protocolo.PERDIO_TIEMPO))
        self.assertEqual(self.juego.fase, partida.TERMINADA)
        self.assertEqual(self.juego.causa, protocolo.PERDIO_TIEMPO)
        self.assertEqual(len(self.juego.enviadas), 0)

    def test_la_partida_nueva_borra_la_anterior(self):
        self.jugar("Z", letra(protocolo.FALLO, 1, NADA))
        self.juego.aplicar(protocolo.Fin(causa=protocolo.GANO))
        self.juego.aplicar(protocolo.Inicio(modo=protocolo.MODO_DIFICIL, largo=8))
        self.assertEqual(self.juego.patron, ["_"] * 8)
        self.assertEqual(self.juego.erradas, [])
        self.assertEqual(self.juego.intentos, 0)
        self.assertEqual(self.juego.fase, partida.JUGANDO)


if __name__ == "__main__":
    unittest.main()
