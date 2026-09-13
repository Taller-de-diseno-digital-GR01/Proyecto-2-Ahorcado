# Pruebas del decodificador, corren sin tarjeta porque protocolo.py es puro
# Correr con: make test-app

import unittest

import protocolo

INICIO = bytes([0x49, 0x01, 0x06])
LETRA = bytes([0x4C, 0x01, 0x02, 0x2A, 0x0F])
FIN = bytes([0x46, 0x04])


class DecodificadorTest(unittest.TestCase):

    def setUp(self):
        self.decodificador = protocolo.Decodificador()

    def test_mensaje_de_inicio(self):
        eventos = self.decodificador.alimentar(INICIO)
        self.assertEqual(eventos, [protocolo.Inicio(modo=1, largo=6)])

    def test_mensaje_de_letra_junta_los_dos_bytes_de_mascara(self):
        eventos = self.decodificador.alimentar(LETRA)
        self.assertEqual(eventos, [protocolo.Letra(resultado=1, intentos=2, mascara=0x0F2A)])

    def test_mensaje_de_fin(self):
        eventos = self.decodificador.alimentar(FIN)
        self.assertEqual(eventos, [protocolo.Fin(causa=protocolo.PERDIO_INTENTOS)])

    def test_tres_mensajes_seguidos_en_una_sola_lectura(self):
        eventos = self.decodificador.alimentar(INICIO + LETRA + FIN)
        self.assertEqual(len(eventos), 3)

    def test_un_mensaje_partido_en_varias_lecturas(self):
        self.assertEqual(self.decodificador.alimentar(LETRA[:2]), [])
        self.assertEqual(self.decodificador.alimentar(LETRA[2:4]), [])
        eventos = self.decodificador.alimentar(LETRA[4:])
        self.assertEqual(eventos, [protocolo.Letra(resultado=1, intentos=2, mascara=0x0F2A)])

    def test_la_basura_antes_de_la_cabecera_se_bota(self):
        eventos = self.decodificador.alimentar(bytes([0x00, 0xFF, 0x21]) + FIN)
        self.assertEqual(eventos, [protocolo.Fin(causa=protocolo.PERDIO_INTENTOS)])
        self.assertEqual(self.decodificador.descartados, 3)

    def test_abrir_a_medio_mensaje_se_resincroniza(self):
        # entramos leyendo el cuerpo de un mensaje de letra, esos bytes no forman nada bueno
        eventos = self.decodificador.alimentar(LETRA[3:] + INICIO)
        self.assertEqual(eventos, [protocolo.Inicio(modo=1, largo=6)])

    def test_un_byte_del_cuerpo_que_parece_cabecera_no_confunde(self):
        # la máscara 0x494C tiene los códigos de "I" y "L" adentro y no debe cortar el mensaje
        mensaje = bytes([0x4C, 0x00, 0x03, 0x4C, 0x49])
        eventos = self.decodificador.alimentar(mensaje)
        self.assertEqual(eventos, [protocolo.Letra(resultado=0, intentos=3, mascara=0x494C)])
        self.assertEqual(self.decodificador.descartados, 0)


class CodificarLetraTest(unittest.TestCase):

    def test_la_minuscula_sube_a_mayuscula(self):
        self.assertEqual(protocolo.codificar_letra("a"), b"A")

    def test_la_mayuscula_pasa_igual(self):
        self.assertEqual(protocolo.codificar_letra("Z"), b"Z")

    def test_los_bordes_del_rango(self):
        self.assertEqual(protocolo.codificar_letra("A"), b"A")
        self.assertEqual(protocolo.codificar_letra("Z"), b"Z")

    def test_lo_que_no_es_letra_no_se_manda(self):
        for tecla in ["ñ", "á", "3", " ", "\n", "\x1b", ""]:
            self.assertIsNone(protocolo.codificar_letra(tecla), tecla)


if __name__ == "__main__":
    unittest.main()
