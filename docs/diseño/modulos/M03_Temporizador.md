# M03 - Temporizador

## Propósito

Controla el tiempo disponible para la partida.

## Entradas

- `start`: inicia el temporizador desde la `FSM`.
- `modo`: selecciona el modo de operación.

**DETENER NO ENTRA**

## Salidas

- `time`: tiempo restante hacia `M01_Marcador`.
- `tiempo_agotado`: indica a la `FSM` que terminó el tiempo.

## Funcionamiento

Cuenta el tiempo mientras está habilitado. Al llegar al límite, activa `tiempo_agotado` para que la `FSM` cambie de estado.
