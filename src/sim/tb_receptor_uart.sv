`timescale 1ns/1ps

// Transcripcion de UART/src/UART_rx.vhd, misma fsm y mismos tiempos, para poder simularlo con iverilog
module modelo_uart_rx #(parameter BAUD_X16_CLK_TICKS = 54) (
  input logic clk,
  input logic reset,
  input logic rx_data_in,
  output logic rx_data_rdy,
  output logic [7:0] rx_data_out
  );

  localparam logic [1:0] IDLE = 2'd0;
  localparam logic [1:0] START = 2'd1;
  localparam logic [1:0] DATA = 2'd2;
  localparam logic [1:0] STOP = 2'd3;

  logic [1:0] rx_state;
  logic baud_rate_x16_clk;
  logic [7:0] rx_stored_data;
  logic rx_end;
  logic edge_signal;
  int baud_x16_count;
  int bit_duration_count;
  int bit_count;

  always_ff @(posedge clk) begin
    if (reset) begin
      baud_rate_x16_clk <= 1'b0;
      baud_x16_count <= BAUD_X16_CLK_TICKS - 1;
    end
    else if (baud_x16_count == 0) begin
      baud_rate_x16_clk <= 1'b1;
      baud_x16_count <= BAUD_X16_CLK_TICKS - 1;
    end
    else begin
      baud_rate_x16_clk <= 1'b0;
      baud_x16_count <= baud_x16_count - 1;
    end
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      rx_state <= IDLE;
      rx_stored_data <= 8'h00;
      rx_data_out <= 8'h00;
      rx_end <= 1'b0;
      bit_duration_count <= 0;
      bit_count <= 0;
    end
    else if (baud_rate_x16_clk) begin
      case (rx_state)
        IDLE: begin
          rx_end <= 1'b0;
          rx_stored_data <= 8'h00;
          bit_duration_count <= 0;
          bit_count <= 0;
          if (!rx_data_in) rx_state <= START;
        end
        // los primeros 8 ticks de medio bit son los que corren el punto de muestreo al centro
        START: begin
          rx_end <= 1'b0;
          if (!rx_data_in) begin
            if (bit_duration_count == 7) begin
              rx_state <= DATA;
              bit_duration_count <= 0;
            end
            else bit_duration_count <= bit_duration_count + 1;
          end
          else rx_state <= IDLE;
        end
        DATA: begin
          if (bit_duration_count == 15) begin
            rx_stored_data[bit_count] <= rx_data_in;
            bit_duration_count <= 0;
            if (bit_count == 7) rx_state <= STOP;
            else bit_count <= bit_count + 1;
          end
          else bit_duration_count <= bit_duration_count + 1;
        end
        STOP: begin
          if (bit_duration_count == 15) begin
            rx_data_out <= rx_stored_data;
            rx_end <= 1'b1;
            rx_state <= IDLE;
          end
          else bit_duration_count <= bit_duration_count + 1;
        end
      endcase
    end
  end

  // detector de flanco sobre rx_end, por esto rx_data_rdy sale como un pulso de un solo ciclo
  always_ff @(posedge clk) begin
    if (reset) begin
      rx_data_rdy <= 1'b0;
      edge_signal <= 1'b0;
    end
    else begin
      rx_data_rdy <= rx_end && !edge_signal;
      edge_signal <= rx_end;
    end
  end

endmodule


module tb_receptor_uart;

  // el generico del profe viene en 9, calculado para 16 MHz, la Basys 3 corre a 100 MHz
  localparam TICKS = 54; // (100e6 / 115200) / 16 = 54.25
  localparam CICLOS_BIT = TICKS * 16;

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

  logic rx_linea;
  logic rx_data_rdy;
  logic [7:0] rx_data_out;
  logic new_rx;

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

  modelo_uart_rx #(.BAUD_X16_CLK_TICKS(TICKS)) nucleo (
    .clk(clk_tb),
    .reset(rst_tb),
    .rx_data_in(rx_linea),
    .rx_data_rdy(rx_data_rdy),
    .rx_data_out(rx_data_out)
  );

  always #5 clk_tb = ~clk_tb;

  // esto es lo que PERIFERICO_UART va a tener que hacer, el nucleo solo da un pulso de un ciclo y eso no se puede sondear
  always_ff @(posedge clk_tb) begin
    if (rst_tb) new_rx <= 1'b0;
    else if (rx_data_rdy) new_rx <= 1'b1;
    else if (o_write_enable_tb && o_addr_tb == ADDR_CTRL && !o_wdata_tb[BIT_NEW_RX]) new_rx <= 1'b0;
  end

  always_comb begin
    case (o_addr_tb)
      ADDR_CTRL: i_rdata_tb = {30'b0, new_rx, 1'b0};
      ADDR_DATOS_RX: i_rdata_tb = {24'b0, rx_data_out};
      default: i_rdata_tb = 32'b0;
    endcase
  end

  task automatic ciclo();
    @(posedge clk_tb);
    #1;
  endtask

  // un bit por vez sobre la linea, start en cero, ocho de dato con el menos significativo primero, stop en uno
  task automatic serial(input logic [7:0] b);
    rx_linea = 1'b0;
    repeat (CICLOS_BIT) @(posedge clk_tb);
    for (int i = 0; i < 8; i++) begin
      rx_linea = b[i];
      repeat (CICLOS_BIT) @(posedge clk_tb);
    end
    rx_linea = 1'b1;
    repeat (CICLOS_BIT) @(posedge clk_tb);
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

  task automatic esperar_rdy();
    while (!rx_data_rdy) ciclo();
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

  initial begin
    $dumpfile("tb_receptor_uart.vcd");
    $dumpvars(0, tb_receptor_uart);
  end

  initial begin
    clk_tb = 1'b0;
    rst_tb = 1'b1;
    i_state_tb = JUEGO;
    rx_linea = 1'b1;

    ciclo();
    chequear_letra("el reset deja la letra y el valid en cero", 8'h00, 1'b0);
    chequear_bus("el reset deja el bus sondeando control sin escribir", ADDR_CTRL, 1'b0);
    rst_tb = 1'b0;

    repeat (20) ciclo();
    chequear_bus("con la linea en reposo se queda sondeando control", ADDR_CTRL, 1'b0);
    chequear_valid("y no entrega ninguna letra", 1'b0);

    // el primer byte se mira ciclo a ciclo, la linea corre en paralelo porque el receptor lo atiende antes de que termine el stop
    fork
      serial("A");
      begin
        esperar_rdy();
        ciclo();
        ciclo();
        chequear_bus("con new_rx arriba pasa a leer el registro de datos", ADDR_DATOS_RX, 1'b0);
        ciclo();
        chequear_letra("la A llega entera y sale con su valid", 8'h41, 1'b1);
        chequear_bus("y en el mismo ciclo escribe para bajar new_rx", ADDR_CTRL, 1'b1);
        anotar("la escritura de limpieza manda ceros", o_wdata_tb === 32'b0,
               $sformatf("o_wdata esperaba 0 y dio %08h", o_wdata_tb));
        ciclo();
        chequear_valid("o_valid_w dura un solo ciclo", 1'b0);
        chequear_bus("y vuelve a sondear control", ADDR_CTRL, 1'b0);
      end
    join

    repeat (CICLOS_BIT) ciclo();
    chequear_valid("el byte ya limpiado no se vuelve a entregar", 1'b0);

    $display("%0d pruebas, %0d fallos", pruebas, errores);
    if (errores != 0) $fatal(1, "tb_receptor_uart termino con fallos");
    $finish;
  end

endmodule
