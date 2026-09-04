# Proyecto 2, Ahorcado FPGA/PC — EL3313 Taller de Diseño Digital

## Estructura del repo

- `docs/diseño/` tiene el planteamiento del diseño, las specs por módulo y los diagramas.
- `docs/informe/` tiene el informe técnico final.
- `src/design/` tiene el RTL en SystemVerilog, un archivo por módulo.
- `src/sim/` tiene los testbenches autoverificables.
- `src/fpga/` tiene los constraints de la Basys3 (XDC).
- `sw/` tiene la app de PC en Python.

## Diseño modular

Todo el diseño (los tres niveles de diagramas y el detalle de cada módulo) también está junto en
un solo archivo en [`docs/diseño/diseño.md`](docs/diseño/diseño.md). Los enlaces de abajo van a
cada archivo individual, que es la fuente de verdad que hay que editar.

### Nivel 1 — Sistema completo

- [Diagrama de primer nivel](docs/diseño/diagramas/nivel01.md)

### Nivel 2 — Bloques principales

- [Diagrama de segundo nivel](docs/diseño/diagramas/nivel02.md)

### Nivel 3 — Módulos

- [Diagrama de tercer nivel](docs/diseño/diagramas/nivel03.md)

### Nivel 4 — Diseño detallado por módulo

- [M01 - Marcador](docs/diseño/modulos/M01_Marcador.md)
- [M02 - Generador de Tono](docs/diseño/modulos/M02_Generador-Tono.md)
- [M03 - Temporizador](docs/diseño/modulos/M03_Temporizador.md)
- [M04 - Mostrar LCD](docs/diseño/modulos/M04_Mostrar-LCD.md)
- [M05 - Estado](docs/diseño/modulos/M05_Estado.md)
- [M06 - Ganadas](docs/diseño/modulos/M06_Ganadas.md)
- [M07 - Comparador de letra](docs/diseño/modulos/M07_Comparador-letra.md)
- [M08 - LFSR](docs/diseño/modulos/M08_LFSR.md)
- [M09 - Botones](docs/diseño/modulos/M09_Botones.md)
- [M10 - Receptor UART](docs/diseño/modulos/M10_Receptor-UART.md)
- [M11 - Transmisor UART](docs/diseño/modulos/M11_Transmisor-UART.md)
- [M12 - Contador de Intentos](docs/diseño/modulos/M12_Contador-Intentos.md)
- [M13 - FSM](docs/diseño/modulos/M13_FSM.md)
