`timescale 1ns/1ps

module tb_periferico_uart;

  // reescalado, lo real son 868 y 54
  localparam TICKS_BIT = 160;
  localparam TICKS_X16 = TICKS_BIT / 16;

  localparam logic [1:0] ADDR_DATOS_TX = 2'b00;
  localparam logic [1:0] ADDR_DATOS_RX = 2'b01;
  localparam logic [1:0] ADDR_CONTROL = 2'b10;
  localparam logic [1:0] ADDR_LIBRE = 2'b11;
  localparam BIT_SEND = 0;
  localparam BIT_NEW_RX = 1;

  logic clk_tb;
  logic rst_tb;
  logic we_tb;
  logic [1:0] addr_tb;
  logic [31:0] wdata_tb;
  logic [31:0] rdata_tb;
  logic linea; // el tx se realimenta al rx, asi una sola instancia prueba las dos direcciones

  int pruebas = 0;
  int errores = 0;

  periferico_uart #(.TICKS_BIT(TICKS_BIT), .TICKS_X16(TICKS_X16)) dut (
    .clk_i(clk_tb),
    .rst_i(rst_tb),
    .write_enable_i(we_tb),
    .addr_i(addr_tb),
    .wdata_i(wdata_tb),
    .rdata_o(rdata_tb),
    .rx_i(linea),
    .tx_o(linea)
  );

  always #5 clk_tb = ~clk_tb;

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
    addr_tb = a;
    wdata_tb = d;
    we_tb = 1'b1;
    ciclo();
    we_tb = 1'b0;
    wdata_tb = 32'b0;
  endtask

  task automatic leer(input logic [1:0] a, output logic [31:0] d);
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

  task automatic esperar_new_rx(input string nombre);
    int n;
    logic [31:0] d;
    n = 0;
    addr_tb = ADDR_CONTROL;
    while (!rdata_tb[BIT_NEW_RX] && n < TICKS_BIT * 20) begin
      ciclo();
      n++;
    end
    anotar(nombre, rdata_tb[BIT_NEW_RX] === 1'b1,
           $sformatf("new_rx nunca subio, control quedo en %08h", rdata_tb));
  endtask

  initial begin
    $dumpfile("tb_periferico_uart.vcd");
    $dumpvars(0, tb_periferico_uart);
  end

  initial begin
    clk_tb = 1'b0;
    rst_tb = 1'b1;
    we_tb = 1'b0;
    addr_tb = ADDR_CONTROL;
    wdata_tb = 32'b0;

    repeat (4) ciclo();
    chequear_reg("el reset deja el control en ceros", ADDR_CONTROL, 32'h0);
    chequear_reg("y los dos registros de datos tambien", ADDR_DATOS_TX, 32'h0);
    rst_tb = 1'b0;

    chequear_reg("la direccion 11 no se usa y devuelve ceros", ADDR_LIBRE, 32'h0);

    escribir(ADDR_DATOS_TX, 32'h41);
    chequear_reg("el registro de transmision guarda lo que le escriben", ADDR_DATOS_TX, 32'h41);
    chequear_reg("y escribirlo no toca el control", ADDR_CONTROL, 32'h0);

    escribir(ADDR_DATOS_RX, 32'h5A);
    chequear_reg("el de recepcion tambien es de escritura, lo dice el enunciado", ADDR_DATOS_RX, 32'h5A);

    escribir(ADDR_DATOS_RX, 32'h00);

    // arranca la transferencia, el byte sale por tx y vuelve por rx
    escribir(ADDR_CONTROL, 32'h1);
    chequear_reg("send se lee alto apenas se escribe", ADDR_CONTROL, 32'h1);

    ciclo();
    addr_tb = ADDR_CONTROL;
    repeat (TICKS_BIT * 2) ciclo();
    anotar("y sigue alto mientras el byte va saliendo", rdata_tb[BIT_SEND] === 1'b1,
           $sformatf("control dio %08h", rdata_tb));

    esperar_new_rx("el byte da la vuelta y levanta new_rx");
    chequear_reg("y aparece entero en el registro de recepcion", ADDR_DATOS_RX, 32'h41);

    chequear_reg("send ya se bajo solo al terminar, es WC, y new_rx sigue esperando", ADDR_CONTROL, 32'h2);

    // limpiar new_rx es responsabilidad de quien instancia, se hace escribiendo un cero en el bit 1
    escribir(ADDR_CONTROL, 32'h0);
    chequear_reg("escribir cero en el bit 1 limpia new_rx", ADDR_CONTROL, 32'h0);
    chequear_reg("pero el dato recibido se queda donde estaba", ADDR_DATOS_RX, 32'h41);

    // segundo byte, para ver que el periferico no se traba despues del primero
    escribir(ADDR_DATOS_TX, 32'h5A);
    escribir(ADDR_CONTROL, 32'h1);
    esperar_new_rx("un segundo byte tambien da la vuelta");
    chequear_reg("y llega con su valor", ADDR_DATOS_RX, 32'h5A);
    escribir(ADDR_CONTROL, 32'h0);

    // el choque que el enunciado deja abierto, escribir send con el bit 1 en cero borra un byte sin leer
    escribir(ADDR_DATOS_TX, 32'h37);
    escribir(ADDR_CONTROL, 32'h1);
    esperar_new_rx("llega un byte y queda esperando que lo lean");
    escribir(ADDR_CONTROL, 32'h1);
    chequear_reg("escribir solo send borra new_rx, por eso el arbitro tiene que componer la escritura", ADDR_CONTROL, 32'h1);

    $display("%0d pruebas, %0d fallos", pruebas, errores);
    if (errores != 0) $fatal(1, "tb_periferico_uart termino con fallos");
    $finish;
  end

endmodule
