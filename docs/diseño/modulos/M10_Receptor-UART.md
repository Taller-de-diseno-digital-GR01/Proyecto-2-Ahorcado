# M10 - Receptor UART

## Propósito

Recibe los bytes que manda la aplicación del PC, se queda solo con los que son una letra A-Z
durante una partida activa, y los entrega a `REG_Letra-in`. Es el punto donde se descarta todo lo
que no debe llegar a la lógica del juego.

---

## Entradas

- `clk`, `rst`.
- `bus 32b`: registros de control y datos del periférico UART, de ahí lee `new_rx` y el dato
  recibido.
- `state`: estado actual, desde `M13_FSM`.

El dato no le llega por una flecha propia en el diagrama de tercer nivel, entra por el bus de 32
bits que todo `CONTROL_JUEGO` comparte con `PERIFERICO_UART`.

---

## e) Salidas

- `letra_in`: letra recibida, hacia `REG_Letra-in`.
- `valid_w`: habilitación de carga de esa letra, hacia `REG_Letra-in`.
- Hacia el bus, `write_enable_i`, `addr_i` y `wdata_i` durante los ciclos en que limpia `new_rx`.

---

## f) Relación con otros módulos

Del lado del bus habla con `PERIFERICO_UART`. Le sondea el bit `new_rx` del registro de control,
le lee el registro de datos de recepción, y le vuelve a escribir el registro de control para bajar
`new_rx`. Esa limpieza es responsabilidad de quien instancia la interfaz, según el enunciado, y le
toca a este módulo.

Del lado del juego solo le habla a `REG_Letra-in`, con el dato y su habilitación de carga. No le
reporta nada a `M13_FSM`. En el planteamiento anterior este módulo le avisaba a la FSM que había
llegado una letra, y ahora ya no hace falta, porque la FSM no participa en el ciclo de validación
de letras.

De `M13_FSM` recibe `state`, y lo usa para decidir si la letra pasa o se bota.

El módulo comparte el bus de 32 bits con `M11_Transmisor-UART`, que es quien transmite. Los dos
acceden al mismo periférico, así que el arbitraje entre ambos tiene que quedar definido en el
diseño de `PERIFERICO_UART` y en el instanciado de `CONTROL_JUEGO`. Este módulo nunca escribe el
registro de datos de transmisión, solo el bit `new_rx` del de control, lo que reduce el choque a
un único registro compartido.

---

