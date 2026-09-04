# M07 - Comparador de letra

## Propósito

Compara la letra recibida con la palabra escogida y determina el resultado del intento.

## Entradas

- `letra_in`: letra almacenada en `REG_Letra-in`.
- `word`: palabra almacenada en `REG_Palabra-escogida`.

## Salidas

- `letra_state`: resultado de la comparación hacia la `FSM`, `M02_Generador-Tono` y `M11_Transmisor-UART`.
- `try`: indica a `M12_Contador-Intentos` que debe registrar el intento.

## Funcionamiento

Busca la letra recibida dentro de la palabra escogida y produce el estado correspondiente para actualizar el juego, el sonido y la comunicación serial.
