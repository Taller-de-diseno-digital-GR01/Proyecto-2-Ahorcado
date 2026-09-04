# M06 - Ganadas

## Propósito

Cuenta las partidas ganadas durante la ejecución del juego.

## Entradas

- `count`: orden de actualización proveniente de la `FSM`.

## Salidas

- `num_ganadas`: contador hacia `M01_Marcador`.

## Funcionamiento

Incrementa el número de partidas ganadas cuando la `FSM` confirma una victoria y conserva el valor para mostrarlo en el marcador.
