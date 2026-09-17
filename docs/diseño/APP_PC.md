# APP_PC, la terminal del jugador

Ficha del bloque `APP_PC` del nivel 2. No lleva el formato de nivel 4 de los módulos porque no es
hardware, no tiene diagrama por compuertas ni restricciones de pin.

El código vive en `sw/` y la única dependencia es `pyserial`.

## Por qué no hay lógica de juego acá

El enunciado lo pide explícito y es lo primero que se pregunta en la defensa. La app **no** decide
si una letra es correcta, **no** cuenta intentos, **no** decide cuándo termina la partida, **no**
sabe cuál es la palabra y **no** lleva el tiempo. Todo eso lo resuelve la FPGA y lo comunica por el
enlace.

Lo único que la app calcula es despliegue:

- Los intentos restantes salen de `MAX_INTENTOS - intentos`, porque el mensaje manda los fallos
  acumulados y en pantalla se ve mejor lo que queda.
- El patrón visible se arma con el delta de la máscara. Cuando la FPGA contesta que la letra fue
  acierto, las posiciones que la máscara acaba de destapar son las de la letra que la app acaba de
  mandar, así que las llena con esa letra. Cuáles posiciones se destapan lo decidió
  `comparador_letra.sv`, la app solo copia.
- El muñeco se dibuja según los intentos que reportó la FPGA.

## Estructura

- `sw/protocolo.py`, decodificador del flujo de bytes y filtro A-Z de la tecla. Es puro, no toca el
  puerto ni la pantalla, y por eso se prueba sin tarjeta.
- `sw/partida.py`, el espejo del estado. Guarda lo último que dijo cada mensaje.
- `sw/vista.py` y `sw/dibujo.py`, el pintado de la pantalla y el muñeco.
- `sw/enlace.py`, apertura del puerto serial y detección de la tarjeta.
- `sw/terminal.py`, el teclado en modo cbreak.
- `sw/ahorcado_pc.py`, la CLI y el ciclo principal.
- `sw/pruebas/`, las pruebas con `unittest`.

## El decodificador

Los mensajes son de largo variable y se identifican por la cabecera, así que el decodificador es una
máquina de estados sobre el flujo de bytes. Con `0x49` espera 2 bytes más, con `0x4C` espera 4 y con
`0x46` espera 1. Cualquier otro byte cuando no hay mensaje en curso se bota y se cuenta.

Eso último es lo que resincroniza la app cuando se abre con la FPGA a media partida, que es el caso
normal, porque la tarjeta ya está corriendo cuando uno lanza la terminal.

El formato completo de los mensajes está en
[`M11_Transmisor-UART.md`](modulos/M11_Transmisor-UART.md), esta ficha no lo repite para no tener
dos fuentes de verdad. Ahí y en el RTL se les dice tramas, es el mismo byte con otro nombre.

Dos detalles del formato que pesan acá. La máscara llega con los bits de arriba de `word_length` en
uno, porque `comparador_letra.sv` arranca el relleno en unos para que su comparación de palabra
completa sirva igual con 4 letras que con 12, así que la app solo mira los primeros `word_length`
bits. Y el mensaje de letra no dice cuál letra era, así que la app aparea las respuestas en orden con
una cola FIFO de las letras que mandó.

El bit 0 de la máscara es la primera letra de la palabra, porque `comparador_letra.sv` recibe la
palabra con la letra 1 en los bits bajos. La app recorre la máscara desde el bit 0 y pinta el patrón
de izquierda a derecha en ese mismo orden.

## El ciclo principal

Un solo hilo con `select` sobre dos descriptores, la entrada estándar y el puerto serial. Sin
hilos, sin colas y sin locks.

El teclado va en modo cbreak, así la letra sale apenas se aprieta la tecla y no hay que darle Enter,
igual que la tarjeta reacciona letra por letra. Se usa cbreak y no raw para que Ctrl-C siga
funcionando.

La app solo manda la tecla cuando la partida está activa. Fuera de partida la FPGA descarta el byte
igual, en `receptor_uart.sv`, pero mandarlo descuadraría la cola de letras esperando respuesta.

## Lo que la pantalla no muestra

- La cuenta regresiva, porque el tiempo no viaja por UART y es exclusivo de los 7 segmentos.
- El contador acumulado de partidas ganadas, que vive solo en los 7 segmentos.
- La palabra cuando se pierde. La FPGA nunca la transmite, así que las posiciones que no se
  llegaron a destapar quedan en guion bajo. El enunciado pide el resultado final con su causa y eso
  sí se muestra.

## Cómo se corre

Lo normal es por el `GNUmakefile`, con el mismo `python3` que usa el resto de los targets.

```
make app                          # busca la tarjeta sola
make app PUERTO=/dev/ttyUSB1      # puerto a mano
make all                          # bitstream, programar y abrir la app, en ese orden
```

`make all` abre la app apenas `make program` termina, así que la terminal queda lista cuando la
tarjeta ya está corriendo el diseño nuevo. Después de programar, la FPGA arranca en la selección
de modo y el mensaje de inicio no sale hasta que alguien aprieta `BTN_OK`, así que la app siempre
alcanza a abrirse antes del primer mensaje.

Directo con Python también sirve, y ahí se tienen las opciones que el target no expone.

```
pip install -r sw/requirements.txt
python3 sw/ahorcado_pc.py --lista    # muestra los puertos de la tarjeta
python3 sw/ahorcado_pc.py -b 9600    # otro baudaje, solo para pruebas con un puerto que no sea la tarjeta
```

Si se prefiere no instalar `pyserial` en el sistema, un entorno virtual en `sw/.venv/` ya está en
el `.gitignore`. En ese caso hay que activarlo antes de `make app`, porque el target llama a
`python3` a secas.

La detección automática busca el FT2232 por VID y PID y se queda con el último puerto, porque el
chip saca dos canales y el segundo es el del puente USB-UART. El primero es el del JTAG.

La app necesita `termios` para el modo cbreak, así que corre en Linux y en FreeBSD. En Windows no
está probada.

En FreeBSD hay un detalle de orden. `make connect` pide `kldunload uftdi` para que openFPGALoader
pueda hablar JTAG, y ese unload se lleva también los `/dev/cuaU*`, así que hay que programar
primero y volver a cargar `uftdi` antes de abrir la app. Por eso en FreeBSD `make all` no llega a
abrir la terminal si `uftdi` quedó descargado, y lo que funciona es `make program`, después
`kldload uftdi` y al final `make app`. En Linux el driver se desprende por interfaz y el puerto del
UART sobrevive a la programación, así que `make all` corre de punta a punta.

## Pruebas

```
make test-app
```

Corren sin tarjeta y sin puerto, contra vectores de bytes armados a mano. Cubren los tres mensajes,
un mensaje partido en varias lecturas, la basura antes de la cabecera, abrir a medio mensaje, un byte
del cuerpo que se parece a una cabecera, el filtro A-Z con acentos y con la ñ, y del lado del
espejo la revelación de todas las posiciones de una letra, el relleno de arriba, la letra repetida,
el apareo de respuestas cuando salen dos letras seguidas, y el reinicio entre partidas.

Aparte hay un chequeo manual del teclado, que no es unittest y por eso vive en
`sw/pruebas/teclado.py` sin el prefijo `test`.

```
make test-teclado
```

Imprime el byte que saldría hacia la FPGA por cada tecla apretada, y ESC lo corta. Necesita una
terminal interactiva, con la entrada canalizada avisa y solo procesa lo que le llegue.

Para probar el ciclo completo sin la tarjeta sirve un pseudoterminal. Se abre con `pty.openpty()`,
se le pasa el `/dev/pts/N` a la app con `-p`, y por el otro extremo se le escriben los mensajes
crudos mientras se le mandan teclas por la entrada estándar.
