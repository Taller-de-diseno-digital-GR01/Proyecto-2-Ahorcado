# M12 - Contador de intentos

## Propósito

Lleva la cuenta de letras incorrectas de la partida en curso y avisa cuando se alcanzaron las seis
que el enunciado fija como máximo. Es la condición de derrota por intentos.

---

## Entradas

- `clk`, `rst`.
- `try`: pulso de intento fallido, desde `M07_Comparador-letra`.
- `state`: estado actual, desde `M13_FSM`.

---

## e) Salidas

- `intentos_agotados`: bandera de seis fallos alcanzados, hacia `M13_FSM`.
- `try`: cantidad de fallos acumulados, hacia `M11_Transmisor-UART`.

---

## f) Relación con otros módulos

`M07_Comparador-letra` es el único que lo incrementa, y solo pulsa `try` cuando la letra fue un
fallo real. Una letra acertada no pulsa, y una letra repetida tampoco, así que este módulo no
necesita saber nada de aciertos ni de repeticiones, le llega el evento ya filtrado.

`M13_FSM` recibe `intentos_agotados` y es quien decide terminar la partida. Este módulo no decide
nada del flujo, solo reporta que llegó al límite.

`M11_Transmisor-UART` recibe la cuenta para armar la trama hacia la PC. El enunciado pide reportar
intentos fallidos **restantes**, y lo que sale de acá son los acumulados, así que la resta
`6 - try` la hace `M11_Transmisor-UART` al componer la trama. Se dejó así para no meterle un
restador a este módulo cuando el valor que de verdad importa adentro de la FPGA es el acumulado.

De `M13_FSM` recibe `state`, y lo usa solo para limpiar la cuenta al entrar a CARGA, o sea al
arrancar cada partida nueva.

Queda un detalle de nomenclatura pendiente. La señal `try` significa dos cosas distintas según el
tramo, un pulso de evento cuando viene de `M07_Comparador-letra` y una cuenta acumulada cuando va hacia
`M11_Transmisor-UART`. Conviene renombrar la segunda a `intentos` en algún momento, está pendiente
de acordar con el equipo porque toca el diagrama de tercer nivel y el módulo de transmisión.

---

