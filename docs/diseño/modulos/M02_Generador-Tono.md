# M02 - Generador de tono

 ## Propósito

 Genera la señal sonora del juego para indicar el resultado de una letra o de una transición de estado.

 ## Entradas

 - `start`: habilitación de la generación de sonido desde la `FSM`.
 - `letra_state`: resultado de la letra entregado por `M07_Comparador-letra`.

 **REVISAR LESTRA_STATE**

 ## Salidas

 - `sound`: señal hacia el buzzer.

 ## Funcionamiento

 Selecciona y genera el tono correspondiente al evento indicado por `start` y `letra_state`.
