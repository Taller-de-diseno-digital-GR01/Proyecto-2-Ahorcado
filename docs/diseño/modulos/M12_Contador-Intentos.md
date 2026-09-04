# M12 - Contador de intentos

## Propósito

Lleva la cuenta de letras incorrectas de la partida en curso y avisa cuando se alcanzaron las seis
que el enunciado fija como máximo. Es la condición de derrota por intentos.

---

## Entradas

- `clk`, `rst`.
- `try`: pulso de intento fallido, desde `M07_Comparador-letra`.
- `state`: estado actual, desde `M13_FSM`.

---

## e) Salidas

- `intentos_agotados`: bandera de seis fallos alcanzados, hacia `M13_FSM`.
- `try`: cantidad de fallos acumulados, hacia `M11_Transmisor-UART`.

---

## f) Relación con otros módulos

`M07_Comparador-letra` es el único que lo incrementa, y solo pulsa `try` cuando la letra fue un
fallo real. Una letra acertada no pulsa, y una letra repetida tampoco, así que este módulo no
necesita saber nada de aciertos ni de repeticiones, le llega el evento ya filtrado.

`M13_FSM` recibe `intentos_agotados` y es quien decide terminar la partida. Este módulo no decide
nada del flujo, solo reporta que llegó al límite.

`M11_Transmisor-UART` recibe la cuenta para armar la trama hacia la PC. El enunciado pide reportar
intentos fallidos **restantes**, y lo que sale de acá son los acumulados, así que la resta
`6 - try` la hace `M11_Transmisor-UART` al componer la trama. Se dejó así para no meterle un
restador a este módulo cuando el valor que de verdad importa adentro de la FPGA es el acumulado.

De `M13_FSM` recibe `state`, y lo usa solo para limpiar la cuenta al entrar a CARGA, o sea al
arrancar cada partida nueva.

Queda un detalle de nomenclatura pendiente. La señal `try` significa dos cosas distintas según el
tramo, un pulso de evento cuando viene de `M07_Comparador-letra` y una cuenta acumulada cuando va hacia
`M11_Transmisor-UART`. Conviene renombrar la segunda a `intentos` en algún momento, está pendiente
de acordar con el equipo porque toca el diagrama de tercer nivel y el módulo de transmisión.

---

## g) Explicación de funcionamiento

El contador arranca en cero y se limpia cada vez que el sistema pasa por CARGA, que es el estado
en que se escoge la palabra de la partida nueva. No hace falta una señal de limpieza dedicada
desde la FSM, el paso por ese estado ya es la señal.

Durante la partida, cada pulso `try` suma uno. Al llegar a seis se levanta `intentos_agotados` y
la FSM se lleva el sistema a PERDIO_INTENTOS. El contador se satura ahí, no sigue contando ni da
la vuelta a cero, aunque en la práctica no debería recibir más pulsos porque la partida ya
terminó y `REG_Letra-in` deja de cargar letras al salir de JUEGO.

`rst` lo devuelve a cero igual que la limpieza por estado, lo que hace que BTN_RST deje la cuenta
en un estado consistente sin importar en qué momento de la partida se presione.

---

## h) Diseño

### Ancho del contador

La cuenta va de 0 a 6, así que necesita tres bits:

$$
ancho = \lceil \log_2(6+1) \rceil = 3
$$

Se describe con `localparam` y `$clog2` siguiendo la convención del proyecto, con el máximo de
intentos como parámetro del módulo en vez de un seis fijo en la lógica. Así el valor sale del
mismo lugar en el que está documentado, y probar la partida con tres intentos en simulación no
obliga a tocar la descripción.

### Contador

Tabla de verdad del contador, en orden de prioridad descendente, que es el mismo orden de los
`if / else if / else` de la implementación:

| Condición                        | `cuenta'`     |
| -------------------------------- | ------------- |
| `rst = 1`                        | `000`         |
| `state = CARGA`                  | `000`         |
| `try = 1` y `cuenta < 6`         | `cuenta + 1`  |
| resto                            | `cuenta`      |

La condición `cuenta < 6` de la tercera fila es la que satura el contador. Sin ella, un pulso
extra lo llevaría a 7 y el siguiente lo devolvería a 0, apagando `intentos_agotados` justo después
de haberlo levantado.

El reset gana sobre la limpieza por estado, y las dos ganan sobre el incremento. Ese orden importa
para el caso en que llegue un `try` en el mismo ciclo en que el sistema entra a CARGA, donde la
cuenta tiene que quedar en cero y no en uno.

### Bandera de agotados

$$
intentos\_agotados = (cuenta = 6)
$$

| `cuenta`        | `intentos_agotados` | Situación |
| --------------- | ------------------- | --------- |
| `000`           | `0`                 | partida recién empezada, seis intentos disponibles |
| `001` a `101`   | `0`                 | quedan intentos |
| `110`           | `1`                 | seis fallos, derrota por intentos |
| `111`           | `1`                 | no alcanzable, el contador satura en `110` |

La bandera es combinacional a partir del registro, no un registro aparte. Así se levanta en el
mismo ciclo en que el contador llega a seis, sin un ciclo de atraso que dejaría entrar una letra
más antes de que la FSM reaccione.

La fila `111` se documenta por completitud de la tabla. Con la saturación del contador ese valor
no se alcanza, y de todas formas la comparación por mayor o igual lo dejaría del lado correcto.

---

