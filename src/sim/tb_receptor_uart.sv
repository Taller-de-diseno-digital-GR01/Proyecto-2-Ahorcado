`timescale 1ns/1ps

module tb_receptor_uart;

  localparam logic [1:0] ADDR_CTRL = 2'b00;
  localparam logic [1:0] ADDR_DATOS_RX = 2'b10;
  localparam BIT_NEW_RX = 1;

  localparam logic [2:0] JUEGO = 3'b010;
  localparam logic [2:0] SELECCION = 3'b000;
  localparam logic [2:0] RESULTADO = 3'b100;

  logic clk_tb;
  logic rst_tb;
  logic [31:0] i_rdata_tb;
  logic [2:0] i_state_tb;
  logic [1:0] o_addr_tb;
  logic o_write_enable_tb;
  logic [31:0] o_wdata_tb;
  logic [7:0] o_letra_tb;
  logic o_valid_w_tb;

  int pruebas = 0;
  int errores = 0;

  receptor_uart dut (
    .clk(clk_tb),
    .rst(rst_tb),
    .i_rdata(i_rdata_tb),
    .i_state(i_state_tb),
    .o_addr(o_addr_tb),
    .o_write_enable(o_write_enable_tb),
    .o_wdata(o_wdata_tb),
    .o_letra(o_letra_tb),
    .o_valid_w(o_valid_w_tb)
  );

  always #5 clk_tb = ~clk_tb;

  task automatic ciclo();
    @(posedge clk_tb);
    #1;
  endtask

  // Modelo del periferico uart, devuelve control o dato segun la direccion que le pone el dut
  logic new_rx_modelo;
  logic [7:0] byte_modelo;
  logic inyectar;

  always_comb begin
    case (o_addr_tb)
      ADDR_CTRL: i_rdata_tb = {30'b0, new_rx_modelo, 1'b0};
      ADDR_DATOS_RX: i_rdata_tb = {24'b0, byte_modelo};
      default: i_rdata_tb = 32'b0;
    endcase
  end

  // new_rx lo levanta el byte que llega y solo lo baja la escritura de ceros del dut
  always_ff @(posedge clk_tb) begin
    if (rst_tb) new_rx_modelo <= 1'b0;
    else if (inyectar) new_rx_modelo <= 1'b1;
    else if (o_write_enable_tb && o_addr_tb == ADDR_CTRL && !o_wdata_tb[BIT_NEW_RX]) new_rx_modelo <= 1'b0;
  end

  task automatic llega(input logic [7:0] b);
    byte_modelo = b;
    inyectar = 1'b1;
    ciclo();
    inyectar = 1'b0;
  endtask

  task automatic anotar(input string nombre, input bit ok, input string detalle);
    pruebas++;
    if (ok) begin
      $display("  ok     %s", nombre);
    end
    else begin
      errores++;
      $display("  FALLO  %s", nombre);
      $display("         %s", detalle);
    end
  endtask

  task automatic chequear_bus(input string nombre, input logic [1:0] addr, input logic we);
    anotar(nombre, o_addr_tb === addr && o_write_enable_tb === we,
           $sformatf("esperaba addr=%02b we=%0b y dio addr=%02b we=%0b",
                     addr, we, o_addr_tb, o_write_enable_tb));
  endtask

  task automatic chequear_letra(input string nombre, input logic [7:0] letra, input logic valid);
    anotar(nombre, o_letra_tb === letra && o_valid_w_tb === valid,
           $sformatf("esperaba letra=%02h valid=%0b y dio letra=%02h valid=%0b",
                     letra, valid, o_letra_tb, o_valid_w_tb));
  endtask

  task automatic chequear_valid(input string nombre, input logic valid);
    anotar(nombre, o_valid_w_tb === valid,
           $sformatf("o_valid_w esperaba %0b y dio %0b", valid, o_valid_w_tb));
  endtask

  // Mete un byte y avanza hasta el ciclo en que el dut ya lo evaluo
  task automatic entregar(input logic [7:0] b);
    llega(b);
    ciclo();
    ciclo();
  endtask

  initial begin
    $dumpfile("tb_receptor_uart.vcd");
    $dumpvars(0, tb_receptor_uart);
  end

  initial begin
    clk_tb = 1'b0;
    rst_tb = 1'b1;
    i_state_tb = JUEGO;
    byte_modelo = 8'h00;
    inyectar = 1'b0;

    $display("== tb_receptor_uart ==");

    ciclo();
    chequear_letra("el reset deja la letra y el valid en cero", 8'h00, 1'b0);
    chequear_bus("el reset deja el bus sondeando control sin escribir", ADDR_CTRL, 1'b0);
    rst_tb = 1'b0;

    repeat (5) ciclo();
    chequear_bus("sin new_rx se queda sondeando el registro de control", ADDR_CTRL, 1'b0);
    chequear_valid("y no entrega ninguna letra", 1'b0);

    llega("A");
    chequear_bus("todavia en espera el ciclo en que llega el byte", ADDR_CTRL, 1'b0);

    ciclo();
    chequear_bus("con new_rx arriba pasa a leer el registro de datos", ADDR_DATOS_RX, 1'b0);

    ciclo();
    chequear_letra("la A sale con su valid", 8'h41, 1'b1);
    chequear_bus("y en el mismo ciclo escribe para bajar new_rx", ADDR_CTRL, 1'b1);
    anotar("la escritura de limpieza manda ceros", o_wdata_tb === 32'b0,
           $sformatf("o_wdata esperaba 0 y dio %08h", o_wdata_tb));

    ciclo();
    chequear_valid("o_valid_w dura un solo ciclo", 1'b0);
    chequear_bus("y vuelve a sondear control", ADDR_CTRL, 1'b0);

    repeat (5) ciclo();
    chequear_valid("el byte ya limpiado no se vuelve a entregar", 1'b0);

    entregar("Z");
    chequear_letra("la Z tambien pasa, es el borde de arriba del rango", 8'h5A, 1'b1);

    entregar(8'h40);
    chequear_valid("el arroba queda justo debajo de la A y se descarta", 1'b0);

    ciclo();
    chequear_bus("y aun asi vuelve a espera, el receptor no se traba", ADDR_CTRL, 1'b0);

    entregar(8'h5B);
    chequear_valid("el corchete queda justo encima de la Z y se descarta", 1'b0);

    entregar("a");
    chequear_valid("una minuscula se descarta", 1'b0);

    entregar("7");
    chequear_valid("un digito se descarta", 1'b0);

    entregar("M");
    chequear_letra("despues de varios bytes botados sigue entregando bien", 8'h4D, 1'b1);

    $display("== %0d pruebas, %0d fallos ==", pruebas, errores);
    if (errores != 0) $fatal(1, "tb_receptor_uart termino con fallos");
    $finish;
  end

endmodule
