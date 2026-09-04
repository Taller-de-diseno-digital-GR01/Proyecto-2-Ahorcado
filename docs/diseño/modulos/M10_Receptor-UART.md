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

## g) Explicación de funcionamiento

El módulo vive sondeando `new_rx`. Mientras esté en cero no hace nada y no toca el bus más allá de
mantener la dirección del registro de control para poder leerlo.

Cuando `new_rx` se levanta, hay un byte esperando. El módulo lo lee del registro de datos de
recepción y le hace dos preguntas. Si el byte cae en el rango A-Z, y si el sistema está en JUEGO.
Solo si las dos son ciertas levanta `valid_w` durante un ciclo, que es lo que hace que
`REG_Letra-in` cargue la letra.

Pase lo que pase con esas dos preguntas, el módulo limpia `new_rx`. Ese detalle es importante. Si
solo se limpiara cuando la letra se acepta, un byte basura recibido durante la pantalla de
selección de modo dejaría el bit levantado para siempre y el receptor quedaría trabado, sin poder
recibir nunca más. El byte se descarta, pero el periférico se libera igual.

Acá se resuelve lo que el enunciado exige documentar de forma explícita. Una letra que llega
mientras el sistema está en selección de modo o mostrando el resultado final se descarta en este
punto. No llega a `REG_Letra-in`, no llega a `M07_Comparador-letra`, no consume intento y no toca
el temporizador. La aplicación de PC además filtra antes de mandar, pero ese filtro es por
comodidad, el que de verdad manda es este.

---

## h) Diseño

### Validación del byte

El rango de letras mayúsculas en ASCII va de `0x41` a `0x5A`:

| `dato_rx`         | En rango A-Z |
| ----------------- | ------------ |
| `< 0x41`          | `0`          |
| `0x41` a `0x5A`   | `1`          |
| `> 0x5A`          | `0`          |

Se comparan los dos extremos con dos comparadores y se juntan con un AND. No se traduce a
minúsculas ni se corrige nada, el enunciado dice que todo byte que no sea una mayúscula A-Z se
descarta sin afectar la partida.

### Decisión de aceptar la letra

Tabla de verdad principal del módulo:

| `new_rx` | `en_rango` | `state = JUEGO` | `valid_w` | Limpia `new_rx` | Resultado |
| -------- | ---------- | --------------- | --------- | --------------- | --------- |
| `0`      | `x`        | `x`             | `0`       | no              | no hay dato |
| `1`      | `0`        | `x`             | `0`       | sí              | byte no alfabético, se bota |
| `1`      | `1`        | `0`             | `0`       | sí              | letra fuera de partida, se bota |
| `1`      | `1`        | `1`             | `1`       | sí              | letra aceptada |

Las tres últimas filas limpian `new_rx`, que es la propiedad que mantiene vivo el receptor pase lo
que pase con el byte.

### Secuencia de acceso al bus

La lectura no es de un solo ciclo, porque hay que poner la dirección, muestrear `rdata_o` y
después escribir de vuelta el registro de control. Se resuelve con una FSM interna de tres
estados, que no tiene nada que ver con la FSM principal del juego:

| Estado actual | Condición    | Estado siguiente | `addr_i`        | `write_enable_i` |
| ------------- | ------------ | ---------------- | --------------- | ---------------- |
| ESPERA        | `new_rx = 0` | ESPERA           | REG_CTRL        | `0`              |
| ESPERA        | `new_rx = 1` | LEE              | REG_CTRL        | `0`              |
| LEE           | siempre      | LIMPIA           | REG_DATOS_RX    | `0`              |
| LIMPIA        | siempre      | ESPERA           | REG_CTRL        | `1`              |

En LEE se muestrea el dato y se evalúa la tabla anterior, y ahí es donde sale el pulso `valid_w`.
En LIMPIA se escribe el registro de control con `new_rx` en cero.

El mapa exacto de direcciones de `addr_i[1:0]` lo define el diseño de `PERIFERICO_UART`, que es
del frente de UART. Este módulo solo depende de que existan un registro de control con el bit
`new_rx` y un registro de datos de recepción, no de en cuál dirección quedaron.

### Por qué sondeo y no interrupción

El periférico no ofrece una línea de interrupción, solo el bit `new_rx`. A 115200 baudios un byte
tarda unos 87 µs en llegar completo, y el ciclo de sondeo de esta FSM dura tres ciclos de reloj de
100 MHz, o sea 30 ns. Sobra margen de tres órdenes de magnitud, así que no hay riesgo de perder un
byte por sondear demasiado lento.

---

