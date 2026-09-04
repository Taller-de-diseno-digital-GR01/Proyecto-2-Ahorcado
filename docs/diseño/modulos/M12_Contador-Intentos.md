# M12 - Contador de intentos

## Propósito

Registra la cantidad de intentos realizados durante la partida.

## Entradas

- `try`: evento de intento desde `M07_Comparador-letra`.

## Salidas

- `try`: contador de intentos hacia la `FSM` y `M11_Transmisor-UART`.

## Funcionamiento

Incrementa el contador cuando se procesa un intento y conserva el valor para el control de la partida y el envío al PC.
