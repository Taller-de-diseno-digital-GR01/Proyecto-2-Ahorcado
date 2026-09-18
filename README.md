# Proyecto 2, Ahorcado FPGA/PC — EL3313 Taller de Diseño Digital

 Profesor:
  Dr.-Ing. Jeferson González-Gómez, Ing. Rolen Coto Calderón

Integrantes:
- Carlos Castro Villegas
- Jefferson Chinchilla Quesada
- Mattio Coghi Quirós
- Nicolás Mena Valerio

II Semestre 2026
 
## Estructura del repo

- `docs/diseño/` tiene el planteamiento del diseño, las specs por módulo y los diagramas.
- `docs/informe/` tiene el informe técnico final.
- `src/design/` tiene el RTL en SystemVerilog, un archivo por módulo.
- `src/sim/` tiene los testbenches autoverificables.
- `src/fpga/` tiene los constraints de la Basys3 (XDC).
- `sw/` tiene la app de PC en Python.

## Cómo simular, compilar y cargar a la FPGA

Todo el flujo está en el `GNUmakefile` y no usa Vivado en ningún paso. `make help` lista
los targets; los principales son:

```sh
make list              # testbenches disponibles
make sim TB=fsm        # simula src/sim/tb_fsm.sv con Icarus Verilog
make test              # corre todos los testbenches
make bitstream         # genera src/build/top.bit
make connect           # revisa que la Basys3 esté visible por USB/JTAG
make program           # carga el .bit a la tarjeta con openFPGALoader
make all               # bitstream + program + app de PC
```

El bitstream se arma con el toolchain abierto [openXC7](https://github.com/openXC7):
yosys sintetiza para `xc7` → `nextpnr-xilinx` hace place & route contra el chipdb del
XC7A35T → `fasm2frames.py` y `xc7frames2bit` (de prjxray) arman el `.bit`.

El makefile arma solo el `PATH` y el `PYTHONPATH` que esas herramientas necesitan, así
que **no hay que correr `source .../export.sh` antes**. Da por hecho openXC7 en
`/opt/openxc7` y el repo de prjxray clonado en `~/prjxray`; si están en otro lado:

```sh
make bitstream OPENXC7=/ruta/openxc7 PRJXRAY_PY=/ruta/prjxray
```

`make bitstream` revisa antes que estén las herramientas, el chipdb, la base de datos de
prjxray y los módulos de python. Vale la pena que falle ahí: si `fasm2frames.py` se cae a
medio camino, el `.bit` igual se genera, pero sale **en blanco** y la tarjeta lo acepta sin
dar ningún error, solo no hace nada.

## Diseño modular

Todo el diseño (los tres niveles de diagramas y el detalle de cada módulo) también está junto en
un solo archivo en [`docs/diseño/diseño.md`](docs/diseño/diseño.md).

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

La app de PC, que tampoco lleva número de módulo porque no es hardware:

- [APP_PC, la terminal del jugador](docs/diseño/APP_PC.md)

Los dos bloques del subsistema UART que no llevan número de módulo:

- [Periférico UART](docs/diseño/modulos/PERIFERICO_UART.md)
- [Árbitro del bus UART](docs/diseño/modulos/ARBITRO_UART.md)
