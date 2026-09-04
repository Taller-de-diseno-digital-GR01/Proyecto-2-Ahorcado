# M10 - Receptor UART

## Propósito

Recibe datos seriales enviados desde la aplicación del PC.

## Entradas

- `RX serial`: flujo serial proveniente del `PC` a través de `PERIFERICO_UART`.
- `bus 32b`: registros de control y datos del periférico UART.

## Salidas

- `letra_in`: letra recibida hacia `REG_Letra-in`.
- `valid_w`: indica a la `FSM` que se recibió una palabra válida.

## Funcionamiento

Lee los datos recibidos por UART, identifica si corresponden a una letra o a una palabra válida y entrega el resultado al control del juego.
