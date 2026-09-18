# Nivel 3

Este nivel refleja las conexiones **presentes en `src/design/top.sv` de la rama `develop`**.

## Diagrama de tercer nivel

```mermaid
flowchart TD
    BTNSEL["btn_sel"] --> M09["M09 Botones"]
    BTNOK["btn_ok"] --> M09
    M09 -->|"sel_pulse, ok_pulse"| M13["M13 FSM"]

    M13 -->|"state, modo"| M03["M03 Temporizador"]
    M13 -->|"state, modo"| M08["M08 LFSR"]
    M13 -->|"state"| M07["M07 Comparador"]
    M13 -->|"state"| M12["M12 Intentos"]
    M13 -->|"state"| M10["M10 Receptor UART"]
    M13 -->|"state, modo"| M11["M11 Transmisor UART"]
    M13 -->|"state, modo"| M04["M04 Mostrar LCD"]
    M13 -->|"state"| M02["M02 Tono"]
    M13 -->|"state"| M05["M05 Estado"]
    M13 -->|"state"| M06["M06 Ganadas"]

    M08 -->|"bank_addr[5:0]"| M14["M14 Banco Palabras"]
    M14 -->|"bank_word[63:0]"| M08
    M08 -->|"word[63:0]"| WORD["Palabra seleccionada<br/>longitud + 12 códigos"]
    M08 -->|"valid_word"| M13

    WORD -->|"word[59:0], length[3:0]"| M07
    WORD -->|"length[3:0]"| M11
    WORD -->|"conversión 5b→ASCII en top"| M04

    M10 -->|"letra_in[7:0], letra_nueva"| M07
    M07 -->|"letra_state, letra_lista"| M11
    M07 -->|"letra_state, letra_lista"| M02
    M07 -->|"mascara[11:0]"| M11
    M07 -->|"mascara[11:0]"| M04
    M07 -->|"try"| M12
    M07 -->|"palabra_completa"| M13

    M12 -->|"intentos[2:0]"| M11
    M12 -->|"intentos[2:0]"| M04
    M12 -->|"intentos_agotados"| M13

    M03 -->|"tiempo_agotado, fin_espera"| M13
    M03 -->|"tiempo BCD[7:0]"| M01["M01 Marcador"]

    M06 -->|"num_ganadas[6:0]"| M01
    M01 -->|"seg, an, dp"| DISP["Display 4 dígitos"]
    M05 -->|"state_led[1:0]"| LED["LEDs"]
    M02 -->|"sound"| BUZ["Buzzer"]

    M10 <-->|"bus RX"| ARB["Árbitro UART"]
    M11 <-->|"bus TX"| ARB
    ARB <-->|"bus 32b"| PUART["Periférico UART"]
    PC["APP PC"] <-->|"RX/TX 115200"| PUART

    M04 <-->|"bus 32b"| PLCD["Periférico LCD"]
    PLCD --> LCD["PmodCLP"]
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
