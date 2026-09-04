# Nivel 3

## Diagrama de tercer nivel

```mermaid
flowchart TD

clk
rst
BTN_SEL[BTN_SEL] -->|sel|M09
BTN_OK[BTN_OK] -->|ok|M09

subgraph "UART"[UART \n TX/RX 115200 baud]
    REG_DATA["REG_DATA"]
    REG_CTRL["REG_CTRL"]

end

subgraph "LCD"
    REG_LCD["REG_LCD"]
    REG_CTRL_LCD["REG_CTRL_LCD"]

end

UART -->|"letra(32)"| M10
PC -->|"letra(32)"| UART



LETRA-..->PC
subgraph "PC"
    App["App"]

end

subgraph "FPGA"
    FSM["FSM"]
    FSM-->|state|M05
    FSM-->|start|M03
    FSM-->|choose|M08

    FSM-->|load|REG_WI
    FSM-->|load|REG_W
    FSM-->|start|M02
    FSM-->|show|M04
    FSM-->|count|M06

    M01["M01_Marcador"]
    M02["M02_Buzzer"]
    M03["M03_Timer"]
    M04["M04_showLCD"]
    M05["M05_State"]
    M06["M06_Ganadas"]
    M07["M07_Comparador-letra"]
    M08["M08_LFSR"]
    M09["M09_Press-Btn"]
    M10["M10_R-UART"]
    M11["M11_Modo"]
    M12["M12_T-UART"]
    M13["M13_Try-Counter"]

    M09-->|sel|M11
    M09-->|ok|M11
    M11-->|ok|FSM
    M11-->|modo|M04
    M11-->|modo|M08
    M11-->|modo|M03
    M11-->|modo|M12
    M07-->|try|M13



    M10-->|word_in|REG_WI

    REG_WS[REG_WBank] -->|bank_word| M08
    M08 --> |word|REG_W


    M03-->|time|M01
    M06-->|num_win|M01
    REG_WI -->|word_in|M07

    REG_W[REG_Palabra-escogida] -->|word|M04
    REG_W-->|word|M07
    M08-->|valid_word|FSM
    REG_WI[REG_Palabra-in]

    M07-->|check|FSM
    M10-->|valid_w|FSM
    M13-->|try|FSM

end

M01-->|time|7SEG1["7SEG TIEMPO"]
M01-->|num_win|7SEG2["7SEG GANADAS"]
M02-->|sound|BUZZER["BUZZER"]
M05-->|state|LED_S["LED ESTADO"]
M04-->|word/Modo|LCD
M12-->|modo/letra_state/Resultado/w_word/Intentos|UART
M13-->|try|M12
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
    IN_WIN(["num_win (de M06)"]) --> REG_G["REG_GANADAS<br/>registro"]
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

Manejar los displays de 7 segmentos del marcador: recibe el tiempo restante desde M03_Timer y
el número de partidas ganadas desde M06_Ganadas, y los muestra en 7SEG1 y 7SEG2
respectivamente.

### d) Entradas

- `clk`, `rst`.
- `time`, tiempo restante de la partida, desde M03_Timer.
- `num_win`, número de partidas ganadas, desde M06_Ganadas.

### e) Salidas

- `deco_time`, patrón de segmentos/ánodos del display de tiempo, hacia 7SEG1.
- `deco_num_win`, patrón de segmentos/ánodos del display de ganadas, hacia 7SEG2.

## M02: Buzzer

### b) Diagrama modular

```mermaid
flowchart LR
    IN_START(["start (de FSM)"]) --> REG_EN["REG_ENABLE<br/>registro"]
    REG_EN --> CNT_DIV["CONT_DIVISOR<br/>contador (prescaler)"]
    CNT_DIV --> CMP1{"CMP = N<br/>comparador"}
    CMP1 -->|toggle| REG_SQ["REG_ONDA<br/>flip-flop T"]
    REG_SQ --> OUT_SND(["sound (a BUZZER)"])
    CNT_DUR["CONT_DURACION<br/>contador"] -->|fin| REG_EN
    REG_EN --> CNT_DUR
```

### c) Objetivo del módulo

Generar la señal de sonido para el buzzer cuando la FSM lo indica (por ejemplo, como
retroalimentación de acierto, error o fin de partida).

### d) Entradas

- `clk`, `rst`.
- `start`, pulso que dispara el tono, desde la FSM.

### e) Salidas

- `sound`, onda cuadrada de audio, hacia BUZZER.

## M03: Timer

### b) Diagrama modular

```mermaid
flowchart LR
    IN_MODO(["modo (de M11)"]) --> MUX1{{"MUX 2:1<br/>tiempo inicial"}}
    MUX1 --> REG_T["REG_TIEMPO<br/>registro"]
    IN_START(["start (de FSM)"]) --> REG_T
    CNT_PRE["CONT_PRESCALER<br/>contador (100MHz→1Hz)"] --> CMP1{"CMP = 0<br/>habilita decremento"}
    CMP1 -->|en| SUB1["SUMADOR<br/>-1 (decrementador)"]
    REG_T --> SUB1
    SUB1 --> REG_T
    REG_T --> OUT_TIME(["time (a M01)"])
```

### c) Objetivo del módulo

Llevar la cuenta regresiva de tiempo de la partida activa. Arranca cuando la FSM lo indica,
ajusta la duración según el modo (fácil/difícil) recibido de M11_Modo, y entrega el tiempo
restante a M01_Marcador para mostrarlo.

### d) Entradas

- `clk`, `rst`.
- `start`, pulso que arranca/reinicia la cuenta, desde la FSM.
- `modo`, fácil o difícil, desde M11_Modo (define el tiempo inicial a cargar).

### e) Salidas

- `time`, tiempo restante de la partida, hacia M01_Marcador.

## M04: ShowLCD

### b) Diagrama modular

```mermaid
flowchart LR
    IN_WORD(["word (de REG_W)"]) --> MUX1{{"MUX 2:1<br/>word / texto modo"}}
    IN_MODO(["modo (de M11)"]) --> MUX1
    IN_SHOW(["show (de FSM)"]) --> MUX1
    MUX1 --> REG_MSG["REG_MENSAJE<br/>registro"]
    CNT_POS["CONT_POSICION<br/>contador (dirección LCD)"] --> REG_MSG
    REG_MSG --> OUT_LCD(["word/Modo (a LCD)"])
```

### c) Objetivo del módulo

Controlar lo que se muestra en el LCD: cuando la FSM lo ordena, toma la palabra escogida
(REG_W) y el modo actual (M11_Modo) y compone la salida `word/Modo` que se envía al periférico
LCD.

### d) Entradas

- `clk`, `rst`.
- `show`, pulso de la FSM que ordena refrescar el LCD.
- `modo`, desde M11_Modo.
- `word`, palabra escogida (REG_Palabra-escogida).

### e) Salidas

- `word/Modo`, mensaje compuesto (palabra en curso o texto de modo), hacia el periférico LCD.

## M05: State

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
    REG_OUT --> OUT_WIN(["num_win (a M01)"])
```

### c) Objetivo del módulo

Contar el número de partidas ganadas: incrementa cuando la FSM lo indica (`count`) y entrega el
total acumulado a M01_Marcador para su despliegue.

### d) Entradas

- `clk`, `rst`.
- `count`, pulso de incremento (partida ganada), desde la FSM.

### e) Salidas

- `num_win`, número acumulado de partidas ganadas, hacia M01_Marcador.

## M07: Comparador-letra

### b) Diagrama modular

```mermaid
flowchart LR
    IN_WIN(["word_in (de REG_WI)"]) --> XOR1["XOR<br/>comparación bit a bit"]
    IN_W(["word (de REG_W)"]) --> XOR1
    XOR1 --> OR1["OR<br/>reducción"]
    OR1 --> REG_CHK["REG_CHECK<br/>registro"]
    REG_CHK --> OUT_CHK(["check (a FSM)"])
    REG_CHK --> CNT1["CONT_PULSO<br/>generador de pulso try"]
    CNT1 --> OUT_TRY(["try (a M13)"])
```

### c) Objetivo del módulo

Comparar la letra recibida (REG_WI, `word_in`) contra la palabra secreta (REG_W, `word`) para
determinar si hubo acierto o fallo, informando el resultado (`check`) a la FSM y actualizando el
contador de intentos en M13_Try-Counter (`try`).

### d) Entradas

- `clk`, `rst`.
- `word_in`, letra recibida, desde REG_Palabra-in.
- `word`, palabra secreta, desde REG_Palabra-escogida.

### e) Salidas

- `check`, resultado de la comparación (acierto/fallo), hacia la FSM.
- `try`, pulso de intento evaluado, hacia M13_Try-Counter.

## M08: LFSR

### b) Diagrama modular

```mermaid
flowchart LR
    REG_LFSR["REG_LFSR<br/>registro de desplazamiento"] --> XOR1["XOR<br/>realimentación"]
    XOR1 --> REG_LFSR
    IN_CHOOSE(["choose (de FSM)"]) --> REG_LFSR
    IN_MODO(["modo (de M11)"]) --> MUX1{{"MUX 2:1<br/>rango de índices"}}
    REG_LFSR --> MUX1
    IN_BANK(["bank_word (de REG_WBank)"]) --> REG_SEL["REG_WORD_SEL<br/>registro"]
    MUX1 --> REG_SEL
    REG_SEL --> CMP1{"CMP<br/>índice válido"}
    CMP1 --> OUT_VALID(["valid_word (a FSM)"])
    REG_SEL --> OUT_WORD(["word (a REG_W)"])
```

### c) Objetivo del módulo

Escoger de forma pseudoaleatoria la palabra secreta de la partida usando un LFSR: cuando la FSM
lo pide (`choose`), muestrea el banco de palabras (REG_WBank) según el modo indicado por
M11_Modo, entrega la palabra elegida a REG_W y confirma su validez a la FSM (`valid_word`).

### d) Entradas

- `clk`, `rst`.
- `choose`, pulso de solicitud de nueva palabra, desde la FSM.
- `modo`, fácil o difícil, desde M11_Modo (acota el rango de palabras válidas).
- `bank_word`, palabra leída del banco, desde REG_WBank.

### e) Salidas

- `word`, palabra escogida, hacia REG_Palabra-escogida.
- `valid_word`, bandera de índice/palabra válida, hacia la FSM.

## M09: Press_Btn

### b) Diagrama modular

```mermaid
flowchart LR
    IN_SEL(["BTN_SEL"]) --> DEB1["DEBOUNCER_SEL<br/>contador + registro"]
    DEB1 --> EDGE1["DETECTOR_FLANCO<br/>flip-flop"]
    EDGE1 --> OUT_SEL(["sel (a M11)"])
    IN_OK(["BTN_OK"]) --> DEB2["DEBOUNCER_OK<br/>contador + registro"]
    DEB2 --> EDGE2["DETECTOR_FLANCO<br/>flip-flop"]
    EDGE2 --> OUT_OK(["ok (a M11)"])
```

### c) Objetivo del módulo

Capturar y filtrar (debounce) las pulsaciones físicas de BTN_SEL y BTN_OK, entregando los
pulsos limpios `sel` y `ok` a M11_Modo.

### d) Entradas

- `clk`, `rst`.
- `BTN_SEL`, señal cruda del botón de selección.
- `BTN_OK`, señal cruda del botón de confirmación.

### e) Salidas

- `sel`, pulso de selección filtrado, hacia M11_Modo.
- `ok`, pulso de confirmación filtrado, hacia M11_Modo.

## M10: R-UART

### b) Diagrama modular

```mermaid
flowchart LR
    IN_LETRA(["letra(32) (de UART)"]) --> REG_RX["REG_RX<br/>registro"]
    REG_RX --> CMP1{"CMP A-Z<br/>comparador de rango"}
    CMP1 --> REG_VALID["REG_VALID<br/>registro"]
    REG_RX --> OUT_WIN(["word_in (a REG_WI)"])
    REG_VALID --> OUT_VALIDW(["valid_w (a FSM)"])
```

### c) Objetivo del módulo

Recibir la letra enviada por la PC a través de UART, cargarla en REG_WI (`word_in`) y avisar a
la FSM que llegó un dato válido (`valid_w`).

### d) Entradas

- `clk`, `rst`.
- `letra(32)`, byte recibido por UART (empaquetado en 32 bits), desde el periférico UART.

### e) Salidas

- `word_in`, letra recibida, hacia REG_Palabra-in.
- `valid_w`, bandera de dato válido recibido, hacia la FSM.

## M11: Modo

### b) Diagrama modular

```mermaid
flowchart LR
    IN_SEL(["sel (de M09)"]) --> REG_MODO["REG_MODO<br/>registro (toggle)"]
    IN_OK(["ok (de M09)"]) --> REG_OK["REG_OK<br/>registro"]
    REG_OK --> OUT_OK(["ok (a FSM)"])
    REG_MODO --> OUT_MODO(["modo (a M04, M08, M03, M12)"])
```

### c) Objetivo del módulo

Gestionar la selección de modo de juego (fácil/difícil): a partir de los pulsos `sel`/`ok` de
M09_Press-Btn, confirma el inicio de partida a la FSM (`ok`) y distribuye el modo elegido
(`modo`) a M04_showLCD, M08_LFSR, M03_Timer y M12_T-UART.

### d) Entradas

- `clk`, `rst`.
- `sel`, pulso de cambio de modo, desde M09_Press-Btn.
- `ok`, pulso de confirmación, desde M09_Press-Btn.

### e) Salidas

- `ok`, confirmación de inicio de partida, hacia la FSM.
- `modo`, modo elegido (fácil/difícil), hacia M04_showLCD, M08_LFSR, M03_Timer y M12_T-UART.

## M12: T-UART

### b) Diagrama modular

```mermaid
flowchart LR
    IN_MODO(["modo (de M11)"]) --> REG_FRAME["REG_TRAMA<br/>registro"]
    IN_TRY(["try (de M13)"]) --> REG_FRAME
    REG_FRAME --> MUX1{{"MUX<br/>selección de campo"}}
    CNT_BYTE["CONT_BYTE<br/>contador"] --> MUX1
    MUX1 --> OUT_UART(["modo/letra_state/Resultado/w_word/Intentos (a UART)"])
```

### c) Objetivo del módulo

Transmitir hacia la PC, por UART, el estado del juego: modo, estado de la letra, resultado,
palabra en curso e intentos usados (`modo/letra_state/Resultado/w_word/Intentos`), a partir del
modo recibido de M11_Modo y los intentos reportados por M13_Try-Counter.

### d) Entradas

- `clk`, `rst`.
- `modo`, desde M11_Modo.
- `try`, número de intentos, desde M13_Try-Counter.

Nota: el diagrama de tercer nivel no dibuja explícitamente el origen de `letra_state`,
`Resultado` ni `w_word` dentro de la trama; quedan pendientes de conectar (probablemente desde
la FSM o desde REG_W/M07) al completar este apartado.

### e) Salidas

- `modo/letra_state/Resultado/w_word/Intentos`, trama de estado del juego, hacia el periférico
  UART.

## M13: Try-Counter

### b) Diagrama modular

```mermaid
flowchart LR
    IN_TRY(["try (de M07)"]) --> CNT1["CONT_INTENTOS<br/>contador ascendente"]
    CNT1 --> REG_OUT["REG_SALIDA<br/>registro"]
    REG_OUT --> OUT_FSM(["try (a FSM)"])
    REG_OUT --> OUT_M12(["try (a M12)"])
```

### c) Objetivo del módulo

Contar los intentos (letras evaluadas) de la partida en curso: se incrementa con cada resultado
de M07_Comparador-letra y reporta el total tanto a la FSM como a M12_T-UART para su transmisión
a la PC.

### d) Entradas

- `clk`, `rst`.
- `try`, pulso de intento evaluado, desde M07_Comparador-letra.

### e) Salidas

- `try`, número acumulado de intentos, hacia la FSM y hacia M12_T-UART.
