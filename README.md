# Proyecto 2, Ahorcado FPGA/PC — EL3313 Taller de Diseño Digital

Profesor:
- Dr.-Ing. Jeferson González-Gómez, Ing. Rolen Coto Calderón

Integrantes:
- Carlos Castro Villegas
- Jefferson Chinchilla Quesada
- Mattio Coghi Quirós
- Nicolás Mena Valerio

II Semestre 2026

## Propósito

Juego de ahorcado distribuido entre una FPGA Basys 3 (Artix-7 XC7A35T) y una aplicación de PC,
comunicadas por un enlace serial UART. Toda la inteligencia de la partida vive en la FPGA: elige
la palabra secreta de un banco interno mediante un LFSR, valida cada letra recibida, controla el
tiempo y los intentos fallidos, y determina el resultado. La PC es únicamente una terminal remota
en Python que envía la letra que el jugador quiere adivinar y muestra la respuesta que la FPGA le
devuelve. Localmente, la FPGA refleja el estado de la partida en una pantalla LCD PmodCLP, en
displays de 7 segmentos, un LED de estado y un buzzer.

El enunciado completo del proyecto está en [`EL3313_proyecto2_2S2026.pdf`](EL3313_proyecto2_2S2026.pdf).

## Estructura del repo

- `EL3313_proyecto2_2S2026.pdf` — enunciado e indicaciones del proyecto.
- `docs/pmodclp_rm.pdf` — manual de referencia del módulo LCD PmodCLP.
- `docs/diseño/` — planteamiento del diseño: diagramas por nivel y specs por módulo.
- `docs/informe/` — informe técnico final.
- `src/design/` — RTL en SystemVerilog, un archivo por módulo.
- `src/sim/` — testbenches autoverificables, uno por módulo (`tb_<modulo>.sv`).
- `src/fpga/` — constraints de la Basys3 (`basys3.xdc`) y scripts de síntesis/programación.
- `src/fpga/harness/` — top-levels descartables para probar un módulo suelto en la FPGA sin
  esperar a que exista un `top.sv` integrado (ver `src/fpga/harness/CONVENCION.txt`).
- `UART/src/` — núcleo UART TX/RX provisto por el curso, en VHDL. No se modifica.
- `sw/` — aplicación de PC en Python (terminal remota del jugador) y sus pruebas.
- `GNUmakefile` — flujo real del proyecto (FreeBSD/Linux/macOS/WSL): simulación, síntesis
  completa con el toolchain abierto openXC7 (sin Vivado), programación y app de PC.
- `Makefile.windows` — flujo equivalente para Windows nativo: simulación con Icarus Verilog y,
  como alternativa a openXC7 en ese SO, síntesis/implementación/bitstream/programación con
  Vivado, tanto del proyecto completo como de un módulo suelto.

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
- [M14 - Banco de palabras](docs/diseño/modulos/M14_banco-palabras.md)

La app de PC, que tampoco lleva número de módulo porque no es hardware:

- [APP_PC, la terminal del jugador](docs/diseño/APP_PC.md)

Los dos bloques del subsistema UART/LCD que no llevan número de módulo:

- [Periférico LCD](docs/diseño/modulos/PERIFERICO_LCD.md)
- [Periférico UART](docs/diseño/modulos/PERIFERICO_UART.md)
- [Árbitro del bus UART](docs/diseño/modulos/ARBITRO_UART.md)

## Dependencias

### Hardware

- Tarjeta Basys 3 (Xilinx Artix-7 XC7A35T), cable USB de datos.
- Módulo LCD PmodCLP (16x2, compatible HD44780), conectado al puerto Pmod indicado en
  `src/fpga/basys3.xdc`.
- Computadora con al menos un puerto serie disponible (el mismo cable USB de la Basys3 expone un
  puerto serie virtual mediante su chip FTDI).

### Software

- Python 3 y la librería `pyserial` (`sw/requirements.txt`), para la app de PC.
- [Icarus Verilog](https://bleyer.org/icarus/) (`iverilog`, `vvp`) — obligatorio para correr las
  simulaciones (`sim`/`test`) en cualquier sistema operativo.
- [GTKWave](https://gtkwave.sourceforge.net/) — opcional, solo para inspeccionar formas de onda
  (`make wave`). Lo trae el mismo instalador de Icarus Verilog en Windows.
- [yosys](https://github.com/YosysHQ/yosys) — obligatorio en FreeBSD/Linux/macOS/WSL como parte
  del toolchain de síntesis completo; opcional en Windows nativo (solo para el chequeo genérico
  de latches con `make synth`).
- Toolchain abierto [openXC7](https://github.com/openXC7) (`nextpnr-xilinx`, `prjxray`,
  `fasm2frames.py`) y [`openFPGALoader`](https://github.com/trabucayre/openFPGALoader) — para
  generar y cargar el bitstream del proyecto completo. Es el flujo real del proyecto
  (`GNUmakefile`) y solo corre en FreeBSD/Linux/macOS o WSL.
- Vivado — alternativa a openXC7 para Windows nativo, vía `Makefile.windows`
  (`fpga-bitstream`/`fpga-program`). Sirve tanto para sintetizar, implementar y programar el
  **proyecto completo** como para probar un módulo suelto en la FPGA con un harness.

## Instalación

1. Clonar el repositorio.
2. Crear un entorno virtual e instalar la app de PC:

   ```sh
   python3 -m venv .venv
   # Linux/macOS
   source .venv/bin/activate
   # Windows (PowerShell)
   .venv\Scripts\Activate.ps1

   pip install -r sw/requirements.txt
   ```

3. Instalar Icarus Verilog y agregarlo al `PATH` (obligatorio para simular en cualquier SO).
4. Según el flujo de síntesis que se vaya a usar, instalar además:
   - **FreeBSD/Linux/macOS o WSL** (flujo real del proyecto): el toolchain openXC7 en
     `/opt/openxc7` (o donde sea, pasando `OPENXC7=<ruta>`), el repo de `prjxray` clonado (por
     defecto en `~/prjxray`, o `PRJXRAY_PY=<ruta>`), y `openFPGALoader`. El `GNUmakefile` arma
     solo el `PATH`/`PYTHONPATH` que esas herramientas necesitan; no hace falta correr
     `source .../export.sh` a mano.
   - **Windows nativo**: Vivado, con `<instalación de Vivado>/bin` en el `PATH`, o abriendo la
     terminal desde una "Vivado Tcl Shell".
5. Verificar las herramientas instaladas:

   ```sh
   # FreeBSD/Linux/macOS/WSL
   make check-tools

   # Windows
   make -f Makefile.windows check-tools
   make -f Makefile.windows check-vivado
   ```

## Compilación y simulación

Cada módulo de `src/design/` tiene su testbench autoverificable en `src/sim/tb_<modulo>.sv`.

```sh
# FreeBSD/Linux/macOS/WSL
make sim TB=<modulo>            # compila y corre un testbench puntual
make test                       # corre todos los testbenches
make synth SYNTH_TOP=<modulo>   # sintetiza con yosys y revisa que no haya latches inferidos
make wave TB=<modulo>           # corre la simulación y abre GTKWave
make test-app                   # pruebas de la app de PC (unittest), no necesita la tarjeta

# Windows
make -f Makefile.windows sim TB=<modulo>
make -f Makefile.windows test
make -f Makefile.windows synth SYNTH_TOP=<modulo>
make -f Makefile.windows wave TB=<modulo>
```

`make list` (o `make -f Makefile.windows list`) muestra los testbenches disponibles.

## Ejecución

### Cargar el sistema completo en la Basys3

Hay dos flujos equivalentes para sintetizar, implementar y programar el proyecto completo
(`src/design/top.sv` y todo lo que instancia), según el sistema operativo:

**FreeBSD/Linux/macOS o WSL, con el toolchain openXC7 (flujo real del proyecto, sin Vivado):**

```sh
make connect     # verifica que la Basys3 esté detectable por USB/JTAG
make bitstream   # sintetiza + implementa con yosys + nextpnr-xilinx + prjxray -> src/build/top.bit
make program     # reconstruye el bitstream si hace falta y lo carga a la Basys3 con openFPGALoader
make all         # encadena bitstream + program + app (abre la terminal de PC al final)
```

`make bitstream` revisa antes que estén las herramientas, el chipdb y la base de datos de
prjxray, y falla ahí si falta algo: si `fasm2frames.py` se corta a medio camino, el `.bit` igual
se genera pero sale en blanco y la tarjeta lo acepta sin avisar, solo no hace nada.

**Windows nativo, con Vivado como alternativa a openXC7:**

```sh
make -f Makefile.windows fpga-bitstream   # SYNTH_TOP=top por defecto: sintetiza + implementa
                                           # + genera el .bit del proyecto completo con Vivado
make -f Makefile.windows fpga-program     # carga ese .bit a la Basys3 por JTAG
```

`fpga-program` requiere la tarjeta conectada por USB y encendida (switch `SW16`).

### Probar un módulo suelto en la FPGA (Windows nativo, con Vivado)

El mismo flujo de Vivado también sirve, sin depender de que exista un `top.sv` integrado, para
probar un módulo aislado contra los harnesses de `src/fpga/harness/` (ver
`src/fpga/harness/CONVENCION.txt`):

```sh
make -f Makefile.windows fpga-bitstream SYNTH_TOP=<harness> FPGA_SRCS="src/fpga/harness/<harness>.sv src/design/<modulo>.sv"
make -f Makefile.windows fpga-program SYNTH_TOP=<harness>
```

### Jugar desde la PC

Con la FPGA ya programada y conectada:

```sh
python sw/ahorcado_pc.py --lista       # lista los puertos donde se detecta la Basys3
python sw/ahorcado_pc.py               # busca la tarjeta sola y arranca la partida
python sw/ahorcado_pc.py -p <puerto>   # o se indica el puerto manualmente

# equivalente en FreeBSD/Linux/macOS/WSL, sin activar el venv a mano:
make app
make app PUERTO=<puerto>
```

Dentro de la terminal se teclea una letra `A`-`Z` por turno; `Esc` o `Ctrl+D` termina la sesión.
El protocolo de aplicación sobre UART está documentado en
[`docs/diseño/APP_PC.md`](docs/diseño/APP_PC.md).
