# Nivel 3

Este nivel refleja las conexiones **presentes en `src/design/top.sv` de la rama `develop`**.

## Diagrama de tercer nivel

```mermaid
flowchart TD

clk -->|clk| FPGA
BTN_RST[BTN_RST] -->|rst| FPGA
BTN_SEL[BTN_SEL] -->|sel|M09
BTN_OK[BTN_OK] -->|ok|M09

PC -->|"RX serial"| PERIFERICO_UART
PERIFERICO_UART -->|tx_o| PC



LETRA -.->|"letra A-Z"| PC
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
        ARB["ARBITRO_UART"]
        REG_W[REG_Palabra-escogida]
        REG_LI[REG_Letra-in]

        M07-->|try|M12
        M10-->|letra_in|REG_LI
        M10-->|valid_w|REG_LI
        REG_LI-->|"letra_in, letra_nueva"|M07
        REG_W-->|"word, word_length"|M07
        M07-->|"letra_state, letra_lista, mascara"|M11
        M07-->|palabra_completa|FSM
        M07-->|mascara|M04
        REG_W-->|"word, word_length"|M04
        M12-->|intentos|M04
        M12-->|intentos|M11
        M12-->|intentos_agotados|FSM
        REG_W-->|word_length|M11
        M10<-->|"bus 32b"|ARB
        M11<-->|"bus 32b"|ARB
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

    ARB <-->|"bus 32b"| PERIFERICO_UART

    FSM-->|state|M02
    FSM-->|state|M05
    FSM-->|state|M06
    FSM-->|"state, modo"|M03
    FSM-->|"state, modo"|M08
    M07-->|"letra_state, letra_lista"|M02
    M08-->|word|REG_W
    M08-->|valid_word|FSM
    M03-->|tiempo_agotado|FSM
    M03-->|fin_espera|FSM
    M03-->|tiempo|M01
    M09-->|sel|FSM
    M09-->|ok|FSM

end

M01-->|time|7SEG1["7SEG TIEMPO"]
M01-->|num_win|7SEG2["7SEG GANADAS"]
M02-->|sound|BUZZER["BUZZER"]
M05-->|state|LED_S["LED ESTADO"]
M04 <-->|"bus 32b"| PERIFERICO_LCD
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
    IN_TIME(["time (de M03)"]) -->|time_value| REG_T["REG_TIEMPO<br/>registro"]
    IN_WIN(["num_ganadas (de M06)"]) -->|num_ganadas| REG_G["REG_GANADAS<br/>registro"]
    CNT_REF["CONT_REFRESCO<br/>contador"] -->|selector| MUX1{{"MUX 2:1<br/>selecciona dígito"}}
    REG_T -->|time_value_reg| MUX1
    REG_G -->|ganadas_reg| MUX1
    MUX1 -->|digito_bcd| DEC["DECOD_BCD_7SEG<br/>decodificador"]
    DEC -->|seg| OUT_SEG(["segmentos + ánodos"])
    CNT_REF -->|selector| OUT_SEG
    OUT_SEG -->|"seg, an"| OUT_T(["deco_time (a 7SEG1)"])
    OUT_SEG -->|"seg, an"| OUT_W(["deco_num_win (a 7SEG2)"])
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
    IN_STATE(["state (de M13_FSM)"]) -->|i_state| DEC_ST["DECOD_ESTADO<br/>detecta fin de partida"]
    DEC_ST -->|pulso_fin| REG_EN["REG_ENABLE<br/>registro"]
    IN_LST(["letra_state (de M07)"]) -->|i_letra_state| REG_EN
    IN_LST -->|i_letra_state| MUX1{{"MUX 3:1<br/>tono acierto/fallo/fin"}}
    DEC_ST -->|pulso_fin| MUX1
    MUX1 -->|next_n| REG_N["REG_N<br/>registro (valor N)"]
    REG_EN -->|reg_enable| CNT_DIV["CONT_DIVISOR<br/>contador (prescaler)"]
    REG_N -->|reg_n| CMP1{"CMP = N<br/>comparador"}
    CNT_DIV -->|cont_divisor| CMP1
    CMP1 -->|"cont_divisor = reg_n (toggle)"| REG_SQ["REG_ONDA<br/>flip-flop T"]
    REG_SQ -->|o_sound| OUT_SND(["sound (a BUZZER)"])
    CNT_DUR["CONT_DURACION<br/>contador"] -->|"cont_duracion = DUR_CYCLES (fin)"| REG_EN
    REG_EN -->|reg_enable| CNT_DUR
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
- `letra_lista`, estrobo que marca cuándo `letra_state` es nuevo, desde M07_Comparador-letra.

### e) Salidas

- `sound`, onda cuadrada de audio, hacia BUZZER.

## M03: Temporizador

### b) Diagrama modular

```mermaid
flowchart LR
    IN_STATE(["i_state (de FSM)"]) -->|i_state| DECJ["FLANCO_JUEGO<br/>start, flanco de entrada a JUEGO"]
    IN_STATE -->|i_state| DECFN["DEC_FIN<br/>nivel, en GANO o PERDIO"]
    IN_STATE -->|i_state| DECF["FLANCO_FIN<br/>pulso_fin, flanco de entrada a GANO/PERDIO"]
    DECJ -->|"start (carga)"| REG_T["REG_TIEMPO<br/>2 décadas BCD"]
    DECJ -->|"start (enciende)"| REG_RUN["REG_RUNNING<br/>registro"]
    DECFN -->|"dec_fin (apaga running)"| REG_RUN
    DECF -->|"pulso_fin (reinicia a 00)"| REG_T
    IN_MODO(["modo (de FSM)"]) -->|modo| MUX1{{"MUX 2:1<br/>tiempo inicial 60 / 45"}}
    MUX1 -->|"tiempo_dec_inicial, tiempo_uni_inicial"| REG_T
    CNT_PRE["CONT_PRESCALER<br/>27 bits descendente"] -->|prescaler_cnt| CMP0{"CMP = 0<br/>tick_1hz"}
    CMP0 -->|tick_1hz| AND_EN["AND<br/>cten = running · tick_1hz"]
    REG_RUN -->|running| AND_EN
    AND_EN -->|"cten (en)"| SUB1["DECREMENTADOR BCD<br/>con préstamo entre décadas"]
    REG_T -->|"tiempo_dec, tiempo_uni"| SUB1
    SUB1 -->|"tiempo_dec, tiempo_uni"| REG_T
    REG_T -->|"tiempo_dec, tiempo_uni"| CMP2{"CMP = 00<br/>zero"}
    CMP2 -->|"zero (apaga running)"| REG_RUN
    CMP2 -->|zero| REG_TA["REG_TIEMPO_AGOTADO<br/>set: running · zero"]
    REG_RUN -->|running| REG_TA
    DECJ -->|"start (limpia)"| REG_TA
    DECF -->|"pulso_fin (limpia)"| REG_TA
    REG_TA -->|tiempo_agotado| OUT_FIN(["tiempo_agotado (a FSM)"])
    REG_T -->|tiempo| OUT_TIME(["tiempo (a M01)"])
    DECF -->|"pulso_fin (reinicia)"| CNT_ESPERA["CONT_ESPERA<br/>2 bits, satura en 3"]
    DECFN -->|dec_fin| CNT_ESPERA
    CMP0 -->|tick_1hz| CNT_ESPERA
    CNT_ESPERA -->|cont_espera| REG_FE["REG_FIN_ESPERA<br/>set: tercer tick en GANO/PERDIO"]
    DECJ -->|"start (limpia)"| REG_FE
    DECF -->|"pulso_fin (limpia)"| REG_FE
    REG_FE -->|o_fin_espera| OUT_ESPERA(["o_fin_espera (a FSM)"])
```

### c) Objetivo del módulo

Llevar la cuenta regresiva de la partida activa. Arranca sola al ver que `state` entró a JUEGO,
con la duración inicial que le dice `modo`, y se detiene al llegar a cero o al entrar a GANO o
PERDIO. Entrega el tiempo restante en BCD a M01_Marcador y avisa a M13_FSM cuando el tiempo se
agota (`tiempo_agotado`).

Es además la única fuente de tiempo real del sistema, así que también le toca contar la espera
del resultado en pantalla, tres pulsos de su `tick_1hz` en GANO o PERDIO, y avisar con
`o_fin_espera`. Se hace acá y no en la FSM para no duplicar un prescalador de 100 MHz a 1 Hz que
ya vive en este módulo.

### d) Entradas

- `clk`, `rst`.
- `i_state`, estado actual, desde M13_FSM, de ahí saca cuándo contar la partida y cuándo la
  espera del resultado.
- `modo`, fácil o difícil, desde M13_FSM, define el tiempo inicial a cargar (60 s o 45 s).

### e) Salidas

- `tiempo_agotado`, bandera de fin de tiempo de partida, hacia M13_FSM.
- `o_fin_espera`, bandera de espera de resultado cumplida, hacia M13_FSM.
- `tiempo[7:0]`, tiempo restante de la partida en BCD, hacia M01_Marcador.

## M04: Mostrar-LCD

### b) Diagrama modular

```mermaid
flowchart LR
    IN_STATE(["i_state (de M13_FSM)"]) -->|i_state| CMP_CAMBIO{"CMP<br/>actual ≠ foto"}
    IN_MODO(["i_modo (de M13_FSM)"]) -->|i_modo| CMP_CAMBIO
    IN_MASC(["i_mascara (de M07)"]) -->|i_mascara| CMP_CAMBIO
    IN_INT(["i_intentos (de M12)"]) -->|i_intentos| CMP_CAMBIO
    IN_RD(["i_rdata: busy, done (de PERIFERICO_LCD)"]) -->|"busy, done"| FSM_LCD
    CMP_CAMBIO -->|cambio| FSM_LCD["FSM_LCD<br/>IDLE / HOME / SEND / WAIT"]
    FSM_LCD -->|"estado (captura IDLE→HOME)"| REG_FOTO["REG_FOTO<br/>state, modo, mascara, intentos, last_pos"]
    IN_STATE -->|i_state| REG_FOTO
    IN_MODO -->|i_modo| REG_FOTO
    IN_MASC -->|i_mascara| REG_FOTO
    IN_INT -->|i_intentos| REG_FOTO
    REG_FOTO -->|"act_state, act_modo, act_mascara, act_intentos"| CMP_CAMBIO
    FSM_LCD -->|"estado (reinicia / incrementa pos)"| CNT_POS["CONT_POSICION<br/>pos, 4 bits"]
    CNT_POS -->|pos| CMP_FIN{"CMP<br/>pos = last_pos"}
    REG_FOTO -->|act_last_pos| CMP_FIN
    CMP_FIN -->|"pos = act_last_pos"| FSM_LCD
    REG_FOTO -->|"act_state, act_modo"| ROM_TXT["ROM_TEXTO<br/>MODO / GANASTE / PERDISTE"]
    CNT_POS -->|pos| ROM_TXT
    REG_FOTO -->|"act_mascara, act_intentos"| GEN_JUEGO["PANTALLA_JUEGO<br/>letra o _ , sufijo I:n"]
    CNT_POS -->|pos| GEN_JUEGO
    IN_WORD(["i_word / i_word_length (de REG_Palabra-escogida)"]) -->|"i_word, i_word_length"| GEN_JUEGO
    ROM_TXT -->|f_byte| MUX1{{"MUX 2:1<br/>texto fijo / juego"}}
    GEN_JUEGO -->|f_byte_juego| MUX1
    REG_FOTO -->|act_state| MUX1
    MUX1 -->|"o_wdata[7:0]"| BUS_OUT["LOGICA_BUS<br/>dirección, write_enable, wdata"]
    FSM_LCD -->|"estado, byte_step"| BUS_OUT
    BUS_OUT -->|"o_addr, o_write_enable, o_wdata"| OUT_LCD(["o_addr / o_write_enable / o_wdata (a PERIFERICO_LCD)"])
```

### c) Objetivo del módulo

Controlar lo que se muestra en el LCD. Decodifica `state` para saber cuál pantalla toca,
selección de modo, palabra en juego, ganó o perdió. Compone el mensaje con `modo`, la palabra
escogida, `mascara` e `intentos`, y lo escribe carácter por carácter en PERIFERICO_LCD por el bus.

Repinta la pantalla del estado que ve, no una pantalla por cada transición, así que si un estado
corto pasa antes de que el LCD alcance a refrescar no queda un mensaje a medias, simplemente
pinta el que sigue.

### d) Entradas

- `clk`, `rst`.
- `i_state`, estado actual, desde M13_FSM, decide cuál pantalla se pinta.
- `i_modo`, desde M13_FSM.
- `i_word`, `i_word_length`, palabra escogida y su longitud, desde REG_Palabra-escogida. La
  palabra llega convertida a ASCII por un adaptador en `top.sv`.
- `i_mascara`, posiciones ya reveladas de la palabra, desde M07_Comparador-letra. Es lo que decide
  cuáles letras se pintan y cuáles quedan como guion bajo.
- `i_intentos`, fallos acumulados de la partida, desde M12_Contador-Intentos. Se muestran como
  intentos restantes al final de la pantalla de juego.
- `i_rdata`, lectura del bus de PERIFERICO_LCD, de donde saca `busy` y `done`.

### e) Salidas

- `o_addr`, `o_write_enable`, `o_wdata`, escrituras de bus hacia PERIFERICO_LCD.

## M05: Estado

### b) Diagrama modular

```mermaid
flowchart LR
    IN_STATE(["state (de M13_FSM)"]) -->|state| REG_S["REG_ESTADO<br/>registro"]
    REG_S -->|state_reg| DEC1["DECOD_ESTADO<br/>decodificador"]
    DEC1 -->|state_led| OUT_LED(["state_led (a LED_S)"])
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
    IN_STATE(["state (de M13_FSM)"]) -->|state| DEC_ST["DECOD_ESTADO<br/>detecta entrada a GANO"]
    DEC_ST -->|entrada_gano| CNT1["CONT_GANADAS<br/>contador ascendente"]
    CNT1 -->|contador_ganadas| REG_OUT["REG_SALIDA<br/>registro"]
    REG_OUT -->|num_ganadas| OUT_WIN(["num_ganadas (a M01)"])
```

## Observaciones de integración

- La FSM tiene cinco estados útiles y no envía `start`, `show`, `choose`, `count`, `load` ni
  `detener`.
- `banco_palabras` es un módulo separado del LFSR.
- No existe un registro `REG_Palabra-escogida` instanciado en el `top` actual. `word[63:0]` sale
  directamente de `lfsr.sv`.
- `palabra_escogida.sv` existe en el repositorio, pero **no está instanciado**. El `top` hace
  directamente el slicing de la palabra y la conversión de los códigos de 5 bits a ASCII.
- El receptor y transmisor UART no se conectan directamente al periférico: pasan por
  `arbitro_uart.sv`.
- `mostrar_lcd.sv` escribe al periférico LCD por bus; no genera directamente `RS`, `RW`, `E` ni
  `lcd_data`.
- El display de 7 segmentos es uno de cuatro dígitos: AN0/AN1 muestran ganadas y AN2/AN3 tiempo.

## Codificación de estado compartida

| Código | Estado |
|---|---|
| `000` | SELECCION |
| `001` | CARGA |
| `010` | JUEGO |
| `011` | GANO |
| `100` | PERDIO |
| `101` | no usado |
| `110` | no usado |
| `111` | no usado |

La codificación es un contrato entre la FSM y los módulos que decodifican `state`.
