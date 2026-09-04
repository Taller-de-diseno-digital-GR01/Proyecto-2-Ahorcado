# M08 - LFSR

## Propósito

Selecciona una palabra del banco de palabras mediante una secuencia pseudoaleatoria.

## Entradas

- `bank_word`: palabra disponible en `REG_WBank`.
- `choose`: orden de selección desde la `FSM`.
- `modo`: modo de operación desde la `FSM`.

## Salidas

- `word`: palabra seleccionada hacia `REG_Palabra-escogida`.
- `valid_word`: indica a la `FSM` que la palabra seleccionada es válida.

## Funcionamiento

Genera el índice pseudoaleatorio con un registro de desplazamiento con realimentación lineal y selecciona la palabra correspondiente del banco.
