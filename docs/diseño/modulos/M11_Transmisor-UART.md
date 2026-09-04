# M11 - Transmisor UART

## Propósito

Envía a la aplicación del PC el estado y los resultados de la partida.

## Entradas

- `modo`: modo actual desde la `FSM`.
- `letra_state`: resultado de la letra desde `M07_Comparador-letra`.
- `try`: número de intento desde `M12_Contador-Intentos`.
- `word_length`: longitud de la palabra escogida.
- `bus 32b`: acceso al periférico UART.

## Salidas

- `modo/letra_state/Resultado/w_word/Intentos`: datos transmitidos mediante `PERIFERICO_UART` hacia el PC.

## Funcionamiento

Construye los mensajes del juego y los transmite a 115200 baudios cuando la `FSM` habilita el envío.
