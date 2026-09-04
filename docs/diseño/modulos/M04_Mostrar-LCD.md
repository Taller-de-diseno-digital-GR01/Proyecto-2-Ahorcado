# M04 - Mostrar LCD

## Propósito

Prepara la información del juego que debe mostrarse en el periférico LCD.

## Entradas

- `show`: orden de actualización desde la `FSM`.
- `modo`: modo actual del juego desde la `FSM`.
- `letra_in`: letra recibida desde `REG_Letra-in`.

## Salidas

- `word/Modo`: datos y comandos enviados a `PERIFERICO_LCD`.

## Funcionamiento

Construye la secuencia de datos que representa la palabra, la letra y el modo actual, y la envía al LCD cuando `show` lo solicita.
