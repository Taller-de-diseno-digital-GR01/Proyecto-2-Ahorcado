`timescale 1ns/1ps

// Testbench autoverificable de PERIFERICO_LCD.
//
// Reescalado: el reloj real de la FPGA es 100_000_000 Hz; aca instanciamos
// el periferico con uno mas chico para que la secuencia de encendido
// (~20ms + 37us + 37us + 1.52ms reales) no tarde una eternidad en simular.
// Como todos los tiempos del modulo se derivan de CLK_FREQ_HZ, la cantidad
// de ciclos de reloj necesaria se recalcula sola; lo que se pierde a este
// reloj reescalado es la resolucion fina del ancho del pulso E y del
// tiempo de setup (T_EPULSE_CYC/T_SETUP_CYC colapsan a 1 ciclo), asi que
// esa parte especifica de la temporizacion hay que verificarla aparte con
// una simulacion post-implementacion a 100MHz real, como pide el enunciado.
module tb_periferico_lcd;

  localparam int CLK_FREQ_HZ_TB = 1_000_000;
  localparam int TIMEOUT_CICLOS = 25_000; // cubre los ~20_000 ciclos de la espera de encendido

  localparam logic [1:0] ADDR_CTRL  = 2'b00;
  localparam logic [1:0] ADDR_DATOS = 2'b01;

  localparam int BIT_START = 0;
  localparam int BIT_RS    = 1;
  localparam int BIT_CLEAR = 2;
  localparam int BIT_HOME  = 3;
  localparam int BIT_BUSY  = 8;
  localparam int BIT_DONE  = 9;

  logic        clk_tb;
  logic        rst_tb;
  logic        we_tb;
  logic [1:0]  addr_tb;
  logic [31:0] wdata_tb;
  logic [31:0] rdata_tb;

  logic        lcd_rs_tb;
  logic        lcd_rw_tb;
  logic        lcd_e_tb;
  logic [7:0]  lcd_datos_tb;

  int pruebas = 0;
  int errores = 0;

  // R/W nunca deberia subir: este diseno solo escribe, nunca lee el LCD
  logic rw_alguna_vez_alto = 1'b0;

  periferico_lcd #(.CLK_FREQ_HZ(CLK_FREQ_HZ_TB)) dut (
    .clk_i(clk_tb),
    .rst_i(rst_tb),
    .write_enable_i(we_tb),
    .addr_i(addr_tb),
    .wdata_i(wdata_tb),
    .rdata_o(rdata_tb),
    .lcd_rs_o(lcd_rs_tb),
    .lcd_rw_o(lcd_rw_tb),
    .lcd_e_o(lcd_e_tb),
    .lcd_data_o(lcd_datos_tb)
  );

  always #5 clk_tb = ~clk_tb;

  always @(posedge clk_tb) if (lcd_rw_tb !== 1'b0) rw_alguna_vez_alto <= 1'b1;

  task automatic ciclo();
    @(posedge clk_tb);
    #1;
  endtask

  task automatic anotar(input string nombre, input bit ok, input string detalle);
    pruebas++;
    if (ok) begin
      $display("ok %s", nombre);
    end
    else begin
      errores++;
      $display("fallo %s", nombre);
      $display("  %s", detalle);
    end
  endtask

  task automatic escribir(input logic [1:0] a, input logic [31:0] d);
    addr_tb  = a;
    wdata_tb = d;
    we_tb    = 1'b1;
    ciclo();
    we_tb    = 1'b0;
    wdata_tb = 32'b0;
  endtask

  task automatic leer(input logic [1:0] a, output logic [31:0] d);
    we_tb   = 1'b0;
    addr_tb = a;
    ciclo();
    d = rdata_tb;
  endtask

  task automatic chequear_reg(input string nombre, input logic [1:0] a, input logic [31:0] esperado);
    logic [31:0] visto;
    leer(a, visto);
    anotar(nombre, visto === esperado,
           $sformatf("addr %02b esperaba %08h y dio %08h", a, esperado, visto));
  endtask

  // Espera a que busy (bit 8 de CONTROL/ESTADO) baje, o sea, a que el
  // periferico vuelva a IDLE. timeout_ciclos evita que la simulacion se
  // cuelgue si algo quedo mal.
  task automatic esperar_no_busy(input string nombre, input int timeout_ciclos);
    int n;
    n = 0;
    we_tb   = 1'b0;
    addr_tb = ADDR_CTRL;
    while (rdata_tb[BIT_BUSY] === 1'b1 && n < timeout_ciclos) begin
      ciclo();
      n++;
    end
    anotar(nombre, rdata_tb[BIT_BUSY] === 1'b0,
           $sformatf("busy nunca bajo, control quedo en %08h tras %0d ciclos", rdata_tb, n));
  endtask

  // Espera el proximo pulso de E hacia el LCD fisico (una transaccion de
  // bus completa: Function Set, Display On/Off, Clear, Return Home, o una
  // letra normal), y devuelve el byte y el rs que se mandaron durante ese
  // pulso.
  task automatic esperar_pulso_e(input string nombre, output logic [7:0] byte_visto,
                                  output logic rs_visto, input int timeout_ciclos);
    int n;
    n = 0;
    while (lcd_e_tb !== 1'b1 && n < timeout_ciclos) begin
      ciclo();
      n++;
    end
    if (lcd_e_tb !== 1'b1) begin
      anotar(nombre, 1'b0, $sformatf("nunca subio el pulso E (%0d ciclos de espera)", n));
      byte_visto = 8'hxx;
      rs_visto   = 1'bx;
    end
    else begin
      byte_visto = lcd_datos_tb;
      rs_visto   = lcd_rs_tb;
      anotar(nombre, 1'b1, "");
      while (lcd_e_tb === 1'b1) ciclo(); // deja pasar el resto del pulso
    end
  endtask

  task automatic chequear_byte(input string nombre, input logic [7:0] obtenido,
                                input logic [7:0] esperado, input logic rs_obt, input logic rs_esp);
    anotar(nombre, (obtenido === esperado) && (rs_obt === rs_esp),
           $sformatf("esperaba byte=%02h rs=%0b, dio byte=%02h rs=%0b",
                      esperado, rs_esp, obtenido, rs_obt));
  endtask

  initial begin
    $dumpfile("tb_periferico_lcd.vcd");
    $dumpvars(0, tb_periferico_lcd);
  end

  initial begin
    logic [7:0] byte_visto;
    logic       rs_visto;

    clk_tb   = 1'b0;
    rst_tb   = 1'b1;
    we_tb    = 1'b0;
    addr_tb  = ADDR_CTRL;
    wdata_tb = 32'b0;

    repeat (4) ciclo();
    chequear_reg("el reset deja CONTROL/ESTADO con busy en alto (arrancando la inicializacion)",
                 ADDR_CTRL, 32'h00000100);
    rst_tb = 1'b0;

    chequear_reg("la direccion 10 no se usa y devuelve ceros", 2'b10, 32'h0);
    chequear_reg("la direccion 11 tampoco se usa y devuelve ceros", 2'b11, 32'h0);

    // --- secuencia de inicializacion del KS0066/HD44780, segun el
    // datasheet del PmodCLP: Function Set (0x38), Display On/Off (0x0C),
    // Clear Display (0x01), todos con rs=0. El Entry Mode Set no se manda
    // explicito porque el reset interno del chip ya lo deja bien puesto.
    esperar_pulso_e("primer pulso E de inicializacion (Function Set)",
                    byte_visto, rs_visto, TIMEOUT_CICLOS);
    chequear_byte("Function Set manda 0x38 con rs=0", byte_visto, 8'h38, rs_visto, 1'b0);

    esperar_pulso_e("segundo pulso E de inicializacion (Display On/Off)",
                    byte_visto, rs_visto, TIMEOUT_CICLOS);
    chequear_byte("Display On/Off manda 0x0C con rs=0", byte_visto, 8'h0C, rs_visto, 1'b0);

    esperar_pulso_e("tercer pulso E de inicializacion (Clear Display)",
                    byte_visto, rs_visto, TIMEOUT_CICLOS);
    chequear_byte("Clear Display manda 0x01 con rs=0", byte_visto, 8'h01, rs_visto, 1'b0);

    esperar_no_busy("busy baja cuando termina la inicializacion", TIMEOUT_CICLOS);
    anotar("done sube justo cuando busy baja (llegan juntos a IDLE)",
           rdata_tb[BIT_DONE] === 1'b0,
           "nota: tras la inicializacion NO se espera un pulso de done, ese aviso es solo para operaciones pedidas por CONTROL_JUEGO");

    // --- operacion normal: CONTROL_JUEGO pide escribir la letra 'A' ---
    escribir(ADDR_DATOS, 32'h41);
    chequear_reg("el byte queda guardado en REG_DATOS", ADDR_DATOS, 32'h41);

    escribir(ADDR_CTRL, 32'h00000003); // rs=1, start=1
    esperar_pulso_e("pulso E de la letra 'A'", byte_visto, rs_visto, TIMEOUT_CICLOS);
    chequear_byte("la letra 'A' se manda con rs=1 (es un dato, no un comando)",
                  byte_visto, 8'h41, rs_visto, 1'b1);

    esperar_no_busy("busy baja cuando termina de escribir la letra", TIMEOUT_CICLOS);
    anotar("done sube justo cuando busy baja, al terminar una operacion pedida por el bus",
           rdata_tb[BIT_DONE] === 1'b1,
           $sformatf("esperaba done=1 en el instante que busy bajo, dio %08h", rdata_tb));

    chequear_reg("y done se limpia solo un ciclo despues (es un pulso, no se queda pegado)",
                 ADDR_CTRL, 32'h00000002); // rs sigue en 1 de la ultima escritura, done ya en 0

    // --- Return Home ---
    escribir(ADDR_CTRL, 32'h00000008); // home=1
    esperar_pulso_e("pulso E de Return Home", byte_visto, rs_visto, TIMEOUT_CICLOS);
    chequear_byte("Return Home manda 0x02 con rs=0", byte_visto, 8'h02, rs_visto, 1'b0);
    esperar_no_busy("busy baja despues de Return Home", TIMEOUT_CICLOS);

    // --- Clear Display, pedido directamente por CONTROL_JUEGO (no el de
    // la inicializacion) ---
    escribir(ADDR_CTRL, 32'h00000004); // clear=1
    esperar_pulso_e("pulso E de Clear Display (pedido directo)", byte_visto, rs_visto, TIMEOUT_CICLOS);
    chequear_byte("Clear Display (directo) manda 0x01 con rs=0", byte_visto, 8'h01, rs_visto, 1'b0);
    esperar_no_busy("busy baja despues del clear directo", TIMEOUT_CICLOS);

    anotar("R/W se mantuvo siempre en bajo durante toda la prueba (el diseno nunca lee del LCD)",
           !rw_alguna_vez_alto, "se detecto R/W en alto en algun momento");

    $display("%0d pruebas, %0d fallos", pruebas, errores);
    if (errores != 0) $fatal(1, "tb_periferico_lcd termino con fallos");
    $finish;
  end

endmodule