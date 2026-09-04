# M09 - Antirrebote

## Propósito

Elimina los rebotes eléctricos de los botones de selección y confirmación.

## Entradas

- `BTN_SEL`: botón de selección.
- `BTN_OK`: botón de confirmación.
- `clk`: reloj del sistema.
- `BTN_RST`: reinicio del sistema.

## Salidas

- `sel`: evento de selección hacia la `FSM`.
- `ok`: evento de confirmación hacia la `FSM`.

## Funcionamiento

Filtra las transiciones inestables de los botones y genera pulsos únicos y sincronizados para el control del juego.
