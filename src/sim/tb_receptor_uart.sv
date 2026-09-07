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
    rst_tb = 1'b0;
    repeat (5) ciclo();

    entregar("A");
    ciclo();

    $finish;
  end

endmodule
