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
        FSM["FSM"]
        M04["M04_Mostrar-LCD"]
        M07["M07_Comparador-letra"]
        M10["M10_Receptor-UART"]
        M11["M11_Transmisor-UART"]
        M12["M12_Contador-Intentos"]
        REG_W[REG_Palabra-escogida]
        REG_LI[REG_Letra-in]

        FSM-->|load|REG_LI
        FSM-->|show|M04
        FSM-->|modo|M04
        FSM-->|modo|M11
        M07-->|try|M12
        M10-->|letra_in|REG_LI
        REG_LI-->|letra_in|M07
        REG_LI-->|letra_in|M04
        REG_W-->|word|M07
        M07-->|letra_state|FSM
        M07-->|letra_state|M11
        M10-->|valid_w|FSM
        M12-->|try|FSM
        M12-->|try|M11
        REG_W-->|word_length|M11
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

    FSM-->|state|M05
    FSM-->|start|M03
    FSM-->|detener|M03
    FSM-->|choose|M08
    FSM-->|start|M02
    FSM-->|count|M06
    FSM-->|modo|M08
    FSM-->|modo|M03
    M07-->|letra_state|M02
    M08-->|word|REG_W
    M08-->|valid_word|FSM
    M03-->|tiempo_agotado|FSM
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
    IN_START(["start (de FSM)"]) --> REG_EN["REG_ENABLE<br/>registro"]
    IN_STATE(["letra_state (de M07)"]) --> MUX1{{"MUX 2:1<br/>tono acierto/fallo"}}
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

Generar el tono del buzzer cuando la FSM lo dispara (`start`), usando `letra_state` de
M07_Comparador-letra para elegir un tono distinto según si la última letra fue acierto o fallo.

### d) Entradas

- `clk`, `rst`.
- `start`, pulso que dispara el tono, desde la FSM.
- `letra_state`, resultado de la última letra evaluada, desde M07_Comparador-letra.

### e) Salidas

- `sound`, onda cuadrada de audio, hacia BUZZER.

## M03: Temporizador

### b) Diagrama modular

```mermaid
flowchart LR
    IN_MODO(["modo (de FSM)"]) --> MUX1{{"MUX 2:1<br/>tiempo inicial"}}
    MUX1 --> REG_T["REG_TIEMPO<br/>registro"]
    IN_START(["start (de FSM)"]) --> REG_T
    IN_STOP(["detener (de FSM)"]) --> REG_EN["REG_ENABLE<br/>registro"]
    CNT_PRE["CONT_PRESCALER<br/>contador (100MHz→1Hz)"] --> CMP1{"CMP = 0<br/>habilita decremento"}
    REG_EN --> CMP1
    CMP1 -->|en| SUB1["SUMADOR<br/>-1 (decrementador)"]
    REG_T --> SUB1
    SUB1 --> REG_T
    REG_T --> CMP2{"CMP = 0<br/>tiempo agotado"}
    CMP2 --> OUT_FIN(["tiempo_agotado (a FSM)"])
    REG_T --> OUT_TIME(["time (a M01)"])
```

### c) Objetivo del módulo

Llevar la cuenta regresiva de tiempo de la partida activa. La FSM la arranca (`start`) y la
puede detener (`detener`); la duración inicial depende del `modo` recibido de la FSM. Entrega el
tiempo restante a M01_Marcador y avisa a la FSM cuando el tiempo se agota (`tiempo_agotado`).

### d) Entradas

- `clk`, `rst`.
- `start`, `detener`, control de arranque/paro de la cuenta, desde la FSM.
- `modo`, fácil o difícil, desde la FSM (define el tiempo inicial a cargar).

### e) Salidas

- `tiempo_agotado`, bandera de fin de tiempo, hacia la FSM.
- `time`, tiempo restante de la partida, hacia M01_Marcador.

## M04: Mostrar-LCD

### b) Diagrama modular

```mermaid
flowchart LR
    IN_LETRA(["letra_in (de REG_LI)"]) --> MUX1{{"MUX 2:1<br/>letra / texto modo"}}
    IN_MODO(["modo (de FSM)"]) --> MUX1
    IN_SHOW(["show (de FSM)"]) --> MUX1
    MUX1 --> REG_MSG["REG_MENSAJE<br/>registro"]
    CNT_POS["CONT_POSICION<br/>contador (dirección LCD)"] --> REG_MSG
    REG_MSG --> OUT_LCD(["word/Modo (a PERIFERICO_LCD)"])
```

### c) Objetivo del módulo

Controlar lo que se muestra en el LCD: cuando la FSM lo ordena (`show`), compone el mensaje a
partir de la última letra recibida (REG_Letra-in) y del modo actual, y lo envía como
`word/Modo` al periférico LCD.

### d) Entradas

- `clk`, `rst`.
- `show`, pulso de la FSM que ordena refrescar el LCD.
- `modo`, desde la FSM.
- `letra_in`, última letra recibida, desde REG_Letra-in.

### e) Salidas

- `word/Modo`, mensaje compuesto, hacia PERIFERICO_LCD.

## M05: Estado

### b) Diagrama modular

```mermaid
flowchart LR
    IN_STATE(["state (de FSM)"]) --> REG_S["REG_ESTADO<br/>registro"]
    REG_S --> DEC1["DECOD_ESTADO<br/>decodificador"]
    DEC1 --> OUT_LED(["state_led (a LED_S)"])
```

### c) Objetivo del módulo

Reflejar el estado actual de la FSM en el LED de estado, traduciendo la señal `state` que
recibe de la FSM a la salida física que enciende LED_S.

### d) Entradas

- `clk`, `rst`.
- `state`, código de estado actual, desde la FSM.

### e) Salidas

- `state_led`, señal física del LED de estado, hacia LED_S.

## M06: Ganadas

### b) Diagrama modular

```mermaid
flowchart LR
    IN_COUNT(["count (de FSM)"]) --> CNT1["CONT_GANADAS<br/>contador ascendente"]
    CNT1 --> REG_OUT["REG_SALIDA<br/>registro"]
    REG_OUT --> OUT_WIN(["num_ganadas (a M01)"])
```

### c) Objetivo del módulo

Contar el número de partidas ganadas: incrementa cuando la FSM lo indica (`count`) y entrega el
total acumulado a M01_Marcador para su despliegue.

### d) Entradas

- `clk`, `rst`.
- `count`, pulso de incremento (partida ganada), desde la FSM.

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
    REG_ST --> OUT_FSM(["letra_state (a FSM)"])
    REG_ST --> OUT_M11(["letra_state (a M11)"])
    REG_ST --> OUT_M02(["letra_state (a M02)"])
    REG_ST --> CNT1["CONT_PULSO<br/>generador de pulso try"]
    CNT1 --> OUT_TRY(["try (a M12)"])
```

### c) Objetivo del módulo

Comparar la letra recibida (REG_Letra-in, `letra_in`) contra la palabra secreta
(REG_Palabra-escogida, `word`) para determinar acierto o fallo, informando el resultado
(`letra_state`) a la FSM, a M11_Transmisor-UART y a M02_Generador-Tono, y avisando a
M12_Contador-Intentos (`try`) que se evaluó un intento.

### d) Entradas

- `clk`, `rst`.
- `letra_in`, letra recibida, desde REG_Letra-in.
- `word`, palabra secreta, desde REG_Palabra-escogida.

### e) Salidas

- `letra_state`, resultado de la comparación, hacia la FSM, M11_Transmisor-UART y
  M02_Generador-Tono.
- `try`, pulso de intento evaluado, hacia M12_Contador-Intentos.

## M08: LFSR

### b) Diagrama modular

```mermaid
flowchart LR
    REG_LFSR["REG_LFSR<br/>registro de desplazamiento"] --> XOR1["XOR<br/>realimentación"]
    XOR1 --> REG_LFSR
    IN_CHOOSE(["choose (de FSM)"]) --> REG_LFSR
    IN_MODO(["modo (de FSM)"]) --> MUX1{{"MUX 2:1<br/>rango de índices"}}
    REG_LFSR --> MUX1
    IN_BANK(["bank_word (de REG_WBank)"]) --> REG_SEL["REG_WORD_SEL<br/>registro"]
    MUX1 --> REG_SEL
    REG_SEL --> CMP1{"CMP<br/>índice válido"}
    CMP1 --> OUT_VALID(["valid_word (a FSM)"])
    REG_SEL --> OUT_WORD(["word (a REG_W)"])
```

### c) Objetivo del módulo

Escoger de forma pseudoaleatoria la palabra secreta de la partida usando un LFSR: cuando la FSM
lo pide (`choose`), muestrea el banco de palabras (REG_WBank) según el `modo` recibido
directamente de la FSM, entrega la palabra elegida a REG_Palabra-escogida y confirma su validez
a la FSM (`valid_word`).

### d) Entradas

- `clk`, `rst`.
- `choose`, pulso de solicitud de nueva palabra, desde la FSM.
- `modo`, fácil o difícil, desde la FSM (acota el rango de palabras válidas).
- `bank_word`, palabra leída del banco, desde REG_WBank.

### e) Salidas

- `word`, palabra escogida, hacia REG_Palabra-escogida.
- `valid_word`, bandera de índice/palabra válida, hacia la FSM.

## M09: Botones

### b) Diagrama modular

```mermaid
flowchart LR
    IN_SEL(["BTN_SEL"]) --> DEB1["DEBOUNCER_SEL<br/>contador + registro"]
    DEB1 --> EDGE1["DETECTOR_FLANCO<br/>flip-flop"]
    EDGE1 --> OUT_SEL(["sel (a FSM)"])
    IN_OK(["BTN_OK"]) --> DEB2["DEBOUNCER_OK<br/>contador + registro"]
    DEB2 --> EDGE2["DETECTOR_FLANCO<br/>flip-flop"]
    EDGE2 --> OUT_OK(["ok (a FSM)"])
```

### c) Objetivo del módulo

Capturar y filtrar (debounce) las pulsaciones físicas de BTN_SEL y BTN_OK, entregando los
pulsos limpios `sel` y `ok` directamente a la FSM.

### d) Entradas

- `clk`, `rst`.
- `BTN_SEL`, señal cruda del botón de selección.
- `BTN_OK`, señal cruda del botón de confirmación.

### e) Salidas

- `sel`, pulso de selección filtrado, hacia la FSM.
- `ok`, pulso de confirmación filtrado, hacia la FSM.

## M10: Receptor-UART

### b) Diagrama modular

```mermaid
flowchart LR
    IN_BUS(["bus 32b (de PERIFERICO_UART)"]) --> REG_RX["REG_RX<br/>registro"]
    REG_RX --> CMP1{"CMP A-Z<br/>comparador de rango"}
    CMP1 --> REG_VALID["REG_VALID<br/>registro"]
    REG_RX --> OUT_LETRA(["letra_in (a REG_LI)"])
    REG_VALID --> OUT_VALIDW(["valid_w (a FSM)"])
```

### c) Objetivo del módulo

Recibir la letra enviada por la PC a través de UART, cargarla en REG_Letra-in (`letra_in`) y
avisar a la FSM que llegó un dato válido (`valid_w`).

### d) Entradas

- `clk`, `rst`.
- Bus de 32 bits compartido con PERIFERICO_UART (lee `REG_DATOS_RX`).

Nota: el diagrama de tercer nivel no dibuja una flecha individual de entrada hacia M10; el dato
le llega a través del bus de 32 bits que todo CONTROL_JUEGO comparte con PERIFERICO_UART.

### e) Salidas

- `letra_in`, letra recibida, hacia REG_Letra-in.
- `valid_w`, bandera de dato válido recibido, hacia la FSM.

## M11: Transmisor-UART

### b) Diagrama modular

```mermaid
flowchart LR
    IN_MODO(["modo (de FSM)"]) --> REG_FRAME["REG_TRAMA<br/>registro"]
    IN_STATE(["letra_state (de M07)"]) --> REG_FRAME
    IN_TRY(["try (de M12)"]) --> REG_FRAME
    IN_LEN(["word_length (de REG_W)"]) --> REG_FRAME
    REG_FRAME --> MUX1{{"MUX<br/>selección de campo"}}
    CNT_BYTE["CONT_BYTE<br/>contador"] --> MUX1
    MUX1 --> OUT_UART(["modo/letra_state/Resultado/w_word/Intentos (a PERIFERICO_UART)"])
```

### c) Objetivo del módulo

Ensamblar y transmitir hacia la PC, por UART, la trama de estado del juego: modo, estado de la
última letra, resultado, longitud de la palabra e intentos usados
(`modo/letra_state/Resultado/w_word/Intentos`).

### d) Entradas

- `clk`, `rst`.
- `modo`, desde la FSM.
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
    CNT1 --> REG_OUT["REG_SALIDA<br/>registro"]
    REG_OUT --> OUT_FSM(["try (a FSM)"])
    REG_OUT --> OUT_M11(["try (a M11)"])
```

### c) Objetivo del módulo

Contar los intentos (letras evaluadas) de la partida en curso: se incrementa con cada pulso
`try` de M07_Comparador-letra y reporta el total tanto a la FSM como a M11_Transmisor-UART.

### d) Entradas

- `clk`, `rst`.
- `try`, pulso de intento evaluado, desde M07_Comparador-letra.

### e) Salidas

- `try`, número acumulado de intentos, hacia la FSM y hacia M11_Transmisor-UART.
