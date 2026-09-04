# Nivel 3

En este documento se detallan los diagramas de diseño de tercer nivel. Además, se detallan las entradas y salidas de estos módulos y como se buscan conectar entre ellos.



## Diagrama de tercer nivel

```mermaid
flowchart TD

clk --> FPGA
BTN_RST[BTN_RST] --> FPGA
BTN_SEL[BTN_SEL] -->|sel|M09
BTN_OK[BTN_OK] -->|ok|M09

PC -->|"RX serial"| PERIFERICO_UART



LETRA -.-> PC
subgraph "PC"
    App["App"]

end

subgraph "FPGA"

    subgraph PERIFERICO_UART["PERIFERICO_UART<br/>TX/RX 115200 baud"]
        REG_CTRL["REG_CTRL\nsend(0,WC) new_rx(1,RW)"]
        REG_DATOS_TX["REG_DATOS_TX"]
        REG_DATOS_RX["REG_DATOS_RX"]

    end

    subgraph "PERIFERICO_LCD"
        REG_CTRL_LCD["REG_CTRL_ESTADO\nstart(0,W1P) rs(1) clear(2,W1P) home(3,W1P) busy(8,RO) done(9,RO)"]
        REG_LCD["REG_DATOS\ndata_byte(7:0)"]

    end

    subgraph "CONTROL_JUEGO"
        FSM["M13_FSM"]
        M04["M04_Mostrar-LCD"]
        M07["M07_Comparador-letra"]
        M10["M10_Receptor-UART"]
        M11["M11_Transmisor-UART"]
        M12["M12_Contador-Intentos"]
        REG_W[REG_Palabra-escogida]
        REG_LI[REG_Letra-in]

        M07-->|try|M12
        M10-->|letra_in|REG_LI
        M10-->|valid_w|REG_LI
        REG_LI-->|letra_in|M07
        REG_LI-->|letra_in|M04
        REG_W-->|word|M07
        M07-->|letra_state|M11
        M07-->|palabra_completa|FSM
        M12-->|try|M11
        M12-->|intentos_agotados|FSM
        REG_W-->|word_length|M11
        FSM-->|state|REG_LI
        FSM-->|state|M07
        FSM-->|state|M10
        FSM-->|state|M12
        FSM-->|"state, modo"|M04
        FSM-->|"state, modo"|M11
    end

    subgraph "BANCO_PALABRAS"
        M08["M08_LFSR"]
        REG_WS[REG_WBank]

        REG_WS-->|bank_word|M08
    end

    subgraph "TEMPORIZADOR"
        M03["M03_Temporizador"]
    end

    subgraph "E_S_LOCALES"
        M01["M01_Marcador"]
        M02["M02_Generador-Tono"]
        M05["M05_Estado"]
        M06["M06_Ganadas"]
        M09["M09_Botones"]

        M06-->|num_ganadas|M01
    end

    CONTROL_JUEGO <-->|"bus 32b"| PERIFERICO_UART
    CONTROL_JUEGO <-->|"bus 32b"| PERIFERICO_LCD

    FSM-->|state|M02
    FSM-->|state|M05
    FSM-->|state|M06
    FSM-->|"state, modo"|M03
    FSM-->|"state, modo"|M08
    M07-->|letra_state|M02
    M08-->|word|REG_W
    M08-->|valid_word|FSM
    M03-->|tiempo_agotado|FSM
    M03-->|fin_espera|FSM
    M03-->|time|M01
    M09-->|sel|FSM
    M09-->|ok|FSM

end

M01-->|time|7SEG1["7SEG TIEMPO"]
M01-->|num_win|7SEG2["7SEG GANADAS"]
M02-->|sound|BUZZER["BUZZER"]
M05-->|state|LED_S["LED ESTADO"]
M04-->|word/Modo|PERIFERICO_LCD
M11-->|modo/letra_state/Resultado/w_word/Intentos|PERIFERICO_UART
```

### Leyenda de los diagramas modulares

Para facilitar la creación de los diagramas, utilizando mermaid, utilizaremos la siguiente notación:

- **Óvalo**: puerto externo del módulo (entrada o salida hacia otro módulo/bloque).
- **Rectángulo**: registro o contador.
- **Hexágono**: multiplexor.
- **Rombo**: comparador o lógica de decisión.
- **Rectángulos etiquetados** `XOR`, `OR`, `SUMADOR`, `DECOD_...`: compuertas o bloques combinacionales
  puntuales (comparación bit a bit, decremento, decodificación).

`clk` y `rst` entran a todo registro/contador de cada módulo aunque no se dibujen en cada elemento,
por el mismo criterio usado en los niveles 1 y 2.

## M01: Marcador

### b) Diagrama modular

```mermaid
flowchart LR
    IN_TIME(["time (de M03)"]) --> REG_T["REG_TIEMPO<br/>registro"]
    IN_WIN(["num_ganadas (de M06)"]) --> REG_G["REG_GANADAS<br/>registro"]
    CNT_REF["CONT_REFRESCO<br/>contador"] --> MUX1{{"MUX 2:1<br/>selecciona dígito"}}
    REG_T --> MUX1
    REG_G --> MUX1
    MUX1 --> DEC["DECOD_BCD_7SEG<br/>decodificador"]
    DEC --> OUT_SEG(["segmentos + ánodos"])
    CNT_REF --> OUT_SEG
    OUT_SEG --> OUT_T(["deco_time (a 7SEG1)"])
    OUT_SEG --> OUT_W(["deco_num_win (a 7SEG2)"])
```

### c) Objetivo del módulo

Manejar los displays de 7 segmentos del marcador: recibe el tiempo restante desde
M03_Temporizador y el número de partidas ganadas desde M06_Ganadas, y los muestra en 7SEG1 y
7SEG2 respectivamente.

### d) Entradas

- `clk`, `rst`.
- `time`, tiempo restante de la partida, desde M03_Temporizador.
- `num_ganadas`, número de partidas ganadas, desde M06_Ganadas.

### e) Salidas

- `deco_time`, patrón de segmentos/ánodos del display de tiempo, hacia 7SEG1.
- `deco_num_win`, patrón de segmentos/ánodos del display de ganadas, hacia 7SEG2.

## M02: Generador-Tono

### b) Diagrama modular

```mermaid
flowchart LR
    IN_STATE(["state (de M13_FSM)"]) --> DEC_ST["DECOD_ESTADO<br/>detecta fin de partida"]
    DEC_ST --> REG_EN["REG_ENABLE<br/>registro"]
    IN_LST(["letra_state (de M07)"]) --> REG_EN
    IN_LST --> MUX1{{"MUX 3:1<br/>tono acierto/fallo/fin"}}
    DEC_ST --> MUX1
    MUX1 --> REG_N["REG_N<br/>registro (valor N)"]
    REG_EN --> CNT_DIV["CONT_DIVISOR<br/>contador (prescaler)"]
    REG_N --> CMP1{"CMP = N<br/>comparador"}
    CNT_DIV --> CMP1
    CMP1 -->|toggle| REG_SQ["REG_ONDA<br/>flip-flop T"]
    REG_SQ --> OUT_SND(["sound (a BUZZER)"])
    CNT_DUR["CONT_DURACION<br/>contador"] -->|fin| REG_EN
    REG_EN --> CNT_DUR
```

### c) Objetivo del módulo

Generar el tono del buzzer. Se dispara solo, con `letra_state` de M07_Comparador-letra para
distinguir acierto de fallo, y decodificando `state` para el tono de fin de partida cuando el
sistema entra a GANO, PERDIO_INTENTOS o PERDIO_TIEMPO. Son los tres sonidos distintos que pide el
enunciado.

### d) Entradas

- `clk`, `rst`.
- `state`, estado actual, desde M13_FSM, de ahí saca el fin de partida.
- `letra_state`, resultado de la última letra evaluada, desde M07_Comparador-letra.

### e) Salidas

- `sound`, onda cuadrada de audio, hacia BUZZER.

## M03: Temporizador

### b) Diagrama modular

```mermaid
flowchart LR
    IN_MODO(["modo (de M13_FSM)"]) --> MUX1{{"MUX 2:1<br/>tiempo inicial"}}
    MUX1 --> REG_T["REG_TIEMPO<br/>registro"]
    IN_STATE(["state (de M13_FSM)"]) --> DEC_ST["DECOD_ESTADO<br/>JUEGO / resultado"]
    DEC_ST -->|carga| REG_T
    DEC_ST --> REG_EN["REG_ENABLE<br/>registro"]
    CNT_PRE["CONT_PRESCALER<br/>contador (100MHz→1Hz)"] --> CMP1{"CMP = 0<br/>habilita decremento"}
    REG_EN --> CMP1
    CMP1 -->|en| SUB1["SUMADOR<br/>-1 (decrementador)"]
    REG_T --> SUB1
    SUB1 --> REG_T
    REG_T --> CMP2{"CMP = 0<br/>tiempo agotado"}
    CMP2 --> OUT_FIN(["tiempo_agotado (a M13_FSM)"])
    REG_T --> OUT_TIME(["time (a M01)"])
    DEC_ST --> CNT_3S["CONT_RESULTADO<br/>contador de 3 s"]
    CNT_PRE --> CNT_3S
    CNT_3S --> OUT_ESP(["fin_espera (a M13_FSM)"])
```

### c) Objetivo del módulo

Llevar la cuenta regresiva de la partida activa. Arranca sola al ver que `state` entró a JUEGO y
se detiene al salir, con la duración inicial que le dice `modo`. Entrega el tiempo restante a
M01_Marcador y avisa a M13_FSM cuando el tiempo se agota (`tiempo_agotado`).

Es además la única fuente de tiempo real del sistema, así que también le toca contar los 3 s
mínimos que el resultado tiene que quedarse en pantalla, y avisar con `fin_espera`. Se hace acá y
no en la FSM para no duplicar un prescalador de 100 MHz a 1 Hz que ya vive en este módulo.

### d) Entradas

- `clk`, `rst`.
- `state`, estado actual, desde M13_FSM, de ahí saca cuándo contar la partida y cuándo los 3 s.
- `modo`, fácil o difícil, desde M13_FSM, define el tiempo inicial a cargar.

### e) Salidas

- `tiempo_agotado`, bandera de fin de tiempo de partida, hacia M13_FSM.
- `fin_espera`, bandera de 3 s cumplidos mostrando resultado, hacia M13_FSM.
- `time`, tiempo restante de la partida, hacia M01_Marcador.

## M04: Mostrar-LCD

### b) Diagrama modular

```mermaid
flowchart LR
    IN_LETRA(["letra_in (de REG_LI)"]) --> MUX1{{"MUX 3:1<br/>selección / palabra / resultado"}}
    IN_MODO(["modo (de M13_FSM)"]) --> MUX1
    IN_STATE(["state (de M13_FSM)"]) --> DEC_ST["DECOD_ESTADO<br/>pantalla a mostrar"]
    DEC_ST --> MUX1
    DEC_ST -->|repintar| REG_MSG["REG_MENSAJE<br/>registro"]
    MUX1 --> REG_MSG
    CNT_POS["CONT_POSICION<br/>contador (dirección LCD)"] --> REG_MSG
    REG_MSG --> OUT_LCD(["word/Modo (a PERIFERICO_LCD)"])
```

### c) Objetivo del módulo

Controlar lo que se muestra en el LCD. Decodifica `state` para saber cuál de las tres pantallas
toca, selección de modo, palabra en juego, o resultado final, compone el mensaje con la última
letra recibida (REG_Letra-in) y el modo actual, y lo manda como `word/Modo` al periférico LCD.

Repinta la pantalla del estado que ve, no una pantalla por cada transición, así que si un estado
corto pasa antes de que el LCD alcance a refrescar no queda un mensaje a medias, simplemente
pinta el que sigue.

### d) Entradas

- `clk`, `rst`.
- `state`, estado actual, desde M13_FSM, decide cuál pantalla se pinta.
- `modo`, desde M13_FSM.
- `letra_in`, última letra recibida, desde REG_Letra-in.

### e) Salidas

- `word/Modo`, mensaje compuesto, hacia PERIFERICO_LCD.

## M05: Estado

### b) Diagrama modular

```mermaid
flowchart LR
    IN_STATE(["state (de M13_FSM)"]) --> REG_S["REG_ESTADO<br/>registro"]
    REG_S --> DEC1["DECOD_ESTADO<br/>decodificador"]
    DEC1 --> OUT_LED(["state_led (a LED_S)"])
```

### c) Objetivo del módulo

Reflejar el estado actual del sistema en el LED de estado, traduciendo la señal `state` que
recibe de M13_FSM a la salida física que enciende LED_S. Distingue selección de modo, partida
activa y resultado final, que es lo que pide el enunciado.

### d) Entradas

- `clk`, `rst`.
- `state`, código de estado actual, desde M13_FSM.

### e) Salidas

- `state_led`, señal física del LED de estado, hacia LED_S.

## M06: Ganadas

### b) Diagrama modular

```mermaid
flowchart LR
    IN_STATE(["state (de M13_FSM)"]) --> DEC_ST["DECOD_ESTADO<br/>detecta entrada a GANO"]
    DEC_ST --> CNT1["CONT_GANADAS<br/>contador ascendente"]
    CNT1 --> REG_OUT["REG_SALIDA<br/>registro"]
    REG_OUT --> OUT_WIN(["num_ganadas (a M01)"])
```

### c) Objetivo del módulo

Contar el número de partidas ganadas. Incrementa por su cuenta al detectar que `state` entró a
GANO y entrega el total acumulado a M01_Marcador para su despliegue. `rst` lo devuelve a cero,
que es lo que hace que BTN_RST reinicie el marcador acumulado como pide el enunciado.

### d) Entradas

- `clk`, `rst`.
- `state`, estado actual, desde M13_FSM, incrementa al entrar a GANO.

### e) Salidas

- `num_ganadas`, número acumulado de partidas ganadas, hacia M01_Marcador.

## M07: Comparador-letra

### b) Diagrama modular

```mermaid
flowchart LR
    IN_LETRA(["letra_in (de REG_LI)"]) --> XOR1["XOR<br/>comparación bit a bit"]
    IN_W(["word (de REG_W)"]) --> XOR1
    XOR1 --> OR1["OR<br/>reducción"]
    OR1 --> REG_ST["REG_LETRA_STATE<br/>registro"]
    OR1 --> REG_MASC["REG_MASCARA<br/>posiciones reveladas"]
    IN_STATE(["state (de M13_FSM)"]) --> REG_MASC
    IN_STATE --> REG_USADAS["REG_USADAS<br/>letras ya recibidas"]
    IN_LETRA --> REG_USADAS
    REG_USADAS --> CMP_REP{"CMP<br/>letra repetida"}
    CMP_REP --> REG_ST
    REG_MASC --> CMP_FIN{"CMP<br/>todas reveladas"}
    IN_W --> CMP_FIN
    CMP_FIN --> OUT_COMP(["palabra_completa (a M13_FSM)"])
    REG_ST --> OUT_M11(["letra_state (a M11)"])
    REG_ST --> OUT_M02(["letra_state (a M02)"])
    REG_ST --> CNT1["CONT_PULSO<br/>generador de pulso try"]
    CNT1 --> OUT_TRY(["try (a M12)"])
```

### c) Objetivo del módulo

Comparar la letra recibida (REG_Letra-in, `letra_in`) contra la palabra secreta
(REG_Palabra-escogida, `word`) para determinar acierto, fallo o letra repetida, informando el
resultado (`letra_state`) a M11_Transmisor-UART y a M02_Generador-Tono, y avisando a
M12_Contador-Intentos (`try`) que se evaluó un intento que sí cuenta.

Guarda además la máscara de posiciones ya reveladas y el registro de letras ya recibidas. La
máscara es la que permite avisarle a M13_FSM que la palabra quedó completa, y el registro de
usadas es el que hace que una letra repetida no gaste intento ni vuelva a sonar como fallo.
Ambos se limpian al ver que `state` entró a CARGA, o sea al empezar cada partida nueva.

### d) Entradas

- `clk`, `rst`.
- `letra_in`, letra recibida, desde REG_Letra-in.
- `word`, palabra secreta, desde REG_Palabra-escogida.
- `state`, estado actual, desde M13_FSM, limpia máscara y letras usadas al entrar a CARGA.

### e) Salidas

- `letra_state`, resultado de la comparación (acierto, fallo o repetida), hacia
  M11_Transmisor-UART y M02_Generador-Tono.
- `palabra_completa`, todas las posiciones reveladas, hacia M13_FSM.
- `try`, pulso de intento evaluado, hacia M12_Contador-Intentos.

## M08: LFSR

### b) Diagrama modular

```mermaid
flowchart LR
    REG_LFSR["REG_LFSR<br/>registro de desplazamiento"] --> XOR1["XOR<br/>realimentación"]
    XOR1 --> REG_LFSR
    IN_STATE(["state (de M13_FSM)"]) --> DEC_ST["DECOD_ESTADO<br/>detecta entrada a CARGA"]
    DEC_ST -->|muestrea| REG_LFSR
    IN_MODO(["modo (de M13_FSM)"]) --> MUX1{{"MUX 2:1<br/>rango de índices"}}
    REG_LFSR --> MUX1
    IN_BANK(["bank_word (de REG_WBank)"]) --> REG_SEL["REG_WORD_SEL<br/>registro"]
    MUX1 --> REG_SEL
    REG_SEL --> CMP1{"CMP<br/>índice válido"}
    CMP1 --> OUT_VALID(["valid_word (a M13_FSM)"])
    REG_SEL --> OUT_WORD(["word (a REG_W)"])
```

### c) Objetivo del módulo

Escoger de forma pseudoaleatoria la palabra secreta de la partida usando un LFSR. El LFSR corre
libre todo el tiempo y este módulo lo muestrea al ver que `state` entró a CARGA, saca del banco
(REG_WBank) una palabra acorde al `modo`, la entrega a REG_Palabra-escogida y confirma con
`valid_word` que ya está lista, que es justo lo que M13_FSM está esperando para pasar a JUEGO.

### d) Entradas

- `clk`, `rst`.
- `state`, estado actual, desde M13_FSM, muestrea el LFSR al entrar a CARGA.
- `modo`, fácil o difícil, desde M13_FSM, acota el rango de palabras válidas.
- `bank_word`, palabra leída del banco, desde REG_WBank.

### e) Salidas

- `word`, palabra escogida, hacia REG_Palabra-escogida.
- `valid_word`, bandera de índice/palabra válida, hacia M13_FSM.

## M09: Botones

### b) Diagrama modular

```mermaid
flowchart LR
    IN_SEL(["BTN_SEL"]) --> DEB1["DEBOUNCER_SEL<br/>contador + registro"]
    DEB1 --> EDGE1["DETECTOR_FLANCO<br/>flip-flop"]
    EDGE1 --> OUT_SEL(["sel (a M13_FSM)"])
    IN_OK(["BTN_OK"]) --> DEB2["DEBOUNCER_OK<br/>contador + registro"]
    DEB2 --> EDGE2["DETECTOR_FLANCO<br/>flip-flop"]
    EDGE2 --> OUT_OK(["ok (a M13_FSM)"])
```

### c) Objetivo del módulo

Capturar y filtrar (debounce) las pulsaciones físicas de BTN_SEL y BTN_OK, entregando los
pulsos limpios `sel` y `ok` directamente a M13_FSM.

### d) Entradas

- `clk`, `rst`.
- `BTN_SEL`, señal cruda del botón de selección.
- `BTN_OK`, señal cruda del botón de confirmación.

### e) Salidas

- `sel`, pulso de selección filtrado, hacia M13_FSM.
- `ok`, pulso de confirmación filtrado, hacia M13_FSM.

## M10: Receptor-UART

### b) Diagrama modular

```mermaid
flowchart LR
    IN_BUS(["bus 32b (de PERIFERICO_UART)"]) --> REG_RX["REG_RX<br/>registro"]
    REG_RX --> CMP1{"CMP A-Z<br/>comparador de rango"}
    IN_STATE(["state (de M13_FSM)"]) --> CMP_JUEGO{"CMP = JUEGO<br/>hay partida activa"}
    CMP1 --> AND1["AND<br/>letra válida y en partida"]
    CMP_JUEGO --> AND1
    AND1 --> REG_VALID["REG_VALID<br/>registro"]
    REG_RX --> OUT_LETRA(["letra_in (a REG_LI)"])
    REG_VALID --> OUT_VALIDW(["valid_w (a REG_LI)"])
```

### c) Objetivo del módulo

Recibir la letra enviada por la PC a través de UART, cargarla en REG_Letra-in (`letra_in`) y
habilitar esa carga con `valid_w` solo si el byte es A-Z y además hay partida activa.

Acá es donde se resuelve lo que el enunciado exige documentar, la letra que llega mientras el
sistema está en selección de modo o mostrando resultado se descarta en este punto, no llega a
REG_Letra-in ni a M07_Comparador-letra, así que no gasta intento ni toca el temporizador. Se
filtra por `state` en vez de preguntarle a M13_FSM, que es lo mismo que hacen los demás módulos.

### d) Entradas

- `clk`, `rst`.
- Bus de 32 bits compartido con PERIFERICO_UART (lee `REG_DATOS_RX`).
- `state`, estado actual, desde M13_FSM, solo deja pasar letras durante JUEGO.

Nota: el diagrama de tercer nivel no dibuja una flecha individual de entrada hacia M10; el dato
le llega a través del bus de 32 bits que todo CONTROL_JUEGO comparte con PERIFERICO_UART.

### e) Salidas

- `letra_in`, letra recibida, hacia REG_Letra-in.
- `valid_w`, habilitación de carga de la letra, hacia REG_Letra-in.

## M11: Transmisor-UART

### b) Diagrama modular

```mermaid
flowchart LR
    IN_MODO(["modo (de M13_FSM)"]) --> REG_FRAME["REG_TRAMA<br/>registro"]
    IN_STATE(["state (de M13_FSM)"]) --> DEC_ST["DECOD_ESTADO<br/>cuál trama toca enviar"]
    DEC_ST --> REG_FRAME
    IN_LST(["letra_state (de M07)"]) --> REG_FRAME
    IN_LST --> DEC_ST
    IN_TRY(["try (de M12)"]) --> REG_FRAME
    IN_LEN(["word_length (de REG_W)"]) --> REG_FRAME
    REG_FRAME --> MUX1{{"MUX<br/>selección de campo"}}
    CNT_BYTE["CONT_BYTE<br/>contador"] --> MUX1
    MUX1 --> OUT_UART(["modo/letra_state/Resultado/w_word/Intentos (a PERIFERICO_UART)"])
```

### c) Objetivo del módulo

Ensamblar y transmitir hacia la PC, por UART, la trama de estado del juego, con modo, estado de
la última letra, resultado, longitud de la palabra e intentos usados
(`modo/letra_state/Resultado/w_word/Intentos`).

Decide solo cuándo transmitir. Al ver que `state` entró a JUEGO manda la trama de inicio de
partida con longitud y modo, con cada `letra_state` nuevo manda el resultado de la letra y los
intentos restantes, y al entrar a GANO, PERDIO_INTENTOS o PERDIO_TIEMPO manda el resultado final.
Como los tres estados de fin son distintos, la causa de la derrota sale directo del `state`, sin
necesidad de una señal aparte.

### d) Entradas

- `clk`, `rst`.
- `state`, estado actual, desde M13_FSM, decide cuál trama toca enviar.
- `modo`, desde M13_FSM.
- `letra_state`, desde M07_Comparador-letra.
- `try`, número de intentos, desde M12_Contador-Intentos.
- `word_length`, longitud de la palabra escogida, desde REG_Palabra-escogida.

### e) Salidas

- `modo/letra_state/Resultado/w_word/Intentos`, trama de estado del juego, hacia
  PERIFERICO_UART.

## M12: Contador-Intentos

### b) Diagrama modular

```mermaid
flowchart LR
    IN_TRY(["try (de M07)"]) --> CNT1["CONT_INTENTOS<br/>contador ascendente"]
    IN_STATE(["state (de M13_FSM)"]) --> DEC_ST["DECOD_ESTADO<br/>limpia al entrar a CARGA"]
    DEC_ST --> CNT1
    CNT1 --> REG_OUT["REG_SALIDA<br/>registro"]
    REG_OUT --> CMP1{"CMP = 6<br/>intentos agotados"}
    CMP1 --> OUT_FSM(["intentos_agotados (a M13_FSM)"])
    REG_OUT --> OUT_M11(["try (a M11)"])
```

### c) Objetivo del módulo

Contar los intentos fallidos de la partida en curso. Se incrementa con cada pulso `try` de
M07_Comparador-letra, reporta el total a M11_Transmisor-UART y le avisa a M13_FSM con
`intentos_agotados` cuando llega a seis, que es la condición de derrota por intentos. Se limpia
solo al ver que `state` entró a CARGA.

### d) Entradas

- `clk`, `rst`.
- `try`, pulso de intento evaluado, desde M07_Comparador-letra.
- `state`, estado actual, desde M13_FSM, limpia la cuenta al entrar a CARGA.

### e) Salidas

- `intentos_agotados`, bandera de seis letras incorrectas alcanzadas, hacia M13_FSM.
- `try`, número acumulado de intentos, hacia M11_Transmisor-UART.

## M13: FSM

### b) Diagrama de estados

Para este módulo el diagrama de estados ocupa el lugar del diagrama modular de los demás. Una FSM
se escribe directamente desde su diagrama de estados, no desde un arreglo de registros y
compuertas, así que ese es el diagrama que de verdad sirve para implementarla.

```mermaid
stateDiagram-v2
    [*] --> SELECCION
    SELECCION --> SELECCION: sel / conmuta modo
    SELECCION --> CARGA: ok
    CARGA --> JUEGO: valid_word
    JUEGO --> GANO: palabra_completa
    JUEGO --> PERDIO_INTENTOS: intentos_agotados
    JUEGO --> PERDIO_TIEMPO: tiempo_agotado
    GANO --> SELECCION: fin_espera
    PERDIO_INTENTOS --> SELECCION: fin_espera
    PERDIO_TIEMPO --> SELECCION: fin_espera
```

Codificación de `state`, tres bits. Es el contrato que decodifican los demás módulos, así que el
valor de cada estado queda fijo:

- `000` SELECCION, pantalla de selección de modo.
- `001` CARGA, se le pide palabra al banco y se espera `valid_word`.
- `010` JUEGO, partida activa.
- `011` GANO, la palabra quedó completa.
- `100` PERDIO_INTENTOS, se alcanzaron las seis letras incorrectas.
- `101` PERDIO_TIEMPO, la cuenta regresiva llegó a cero.

`BTN_RST` devuelve la FSM a SELECCION desde cualquier estado, igual que reinicia al resto de los
módulos, por eso no se dibuja como una transición más del diagrama.

### c) Objetivo del módulo

Llevar el estado global de la partida y publicarlo para que cada módulo decida por su cuenta qué
le toca hacer. La FSM no le da órdenes puntuales a nadie, no manda pulsos de `start`, `show`,
`choose` ni `count`. Solo dice en cuál de los seis estados está el sistema y cuál modo está
seleccionado.

Esa es la decisión de diseño central del módulo. Con la FSM mandando, cada módulo nuevo obligaba a
agregarle una salida y a meterle mano a su lógica interna. Con los módulos decodificando `state`
la FSM queda fija, y un módulo nuevo solo se cuelga del estado que ya se difunde. Se nota en el
diagrama de tercer nivel, todas las flechas que salen de la FSM llevan lo mismo, `state` y en
algunos casos `modo`, en vez de once señales de control distintas.

El otro efecto es que la FSM nunca se queda esperando a nadie. No sondea el `busy` del LCD ni
espera confirmación de M11 para cambiar de estado, porque no les está ordenando nada. M04 repinta
el estado que ve en el momento en que puede, y si CARGA pasa demasiado rápido para el LCD,
simplemente pinta el siguiente estado sin que quede nada a medias.

De aquí sale también la respuesta a lo que el enunciado exige documentar, qué pasa con una letra
que llega por UART fuera de partida. REG_Letra-in solo carga cuando `state` es JUEGO, así que la
letra se descarta ahí mismo, sin llegar a M07 ni gastar intento. La FSM ni se entera.

### d) Entradas

- `clk`, `rst`.
- `sel`, pulso de cambio de modo, desde M09_Botones.
- `ok`, pulso de confirmación, desde M09_Botones.
- `valid_word`, palabra lista en REG_Palabra-escogida, desde M08_LFSR.
- `palabra_completa`, todas las posiciones de la palabra reveladas, desde M07_Comparador-letra.
- `intentos_agotados`, seis letras incorrectas alcanzadas, desde M12_Contador-Intentos.
- `tiempo_agotado`, cuenta regresiva en cero, desde M03_Temporizador.
- `fin_espera`, se cumplieron los 3 s de resultado en pantalla, desde M03_Temporizador.

### e) Salidas

- `state`, estado actual en tres bits, hacia M02_Generador-Tono, M03_Temporizador,
  M04_Mostrar-LCD, M05_Estado, M06_Ganadas, M07_Comparador-letra, M08_LFSR, M10_Receptor-UART,
  M11_Transmisor-UART, M12_Contador-Intentos y REG_Letra-in.
- `modo`, FACIL o DIFICIL, hacia M03_Temporizador, M04_Mostrar-LCD, M08_LFSR y
  M11_Transmisor-UART.
