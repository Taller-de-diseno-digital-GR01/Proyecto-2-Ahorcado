`timescale 1ns/1ps

module tb_transmisor_uart;

  localparam WORD_MAXLEN = 12;

  // el periferico real tarda 868*10 ciclos en soltar send, aca se reescala para no eternizar la simulacion
  localparam CICLOS_SEND = 20;

  localparam logic [1:0] ADDR_UART_CTRL = 2'b10;
  localparam logic [1:0] ADDR_UART_TX = 2'b00;
  localparam BIT_SEND = 0;

  localparam logic [2:0] SELECCION = 3'b000;
  localparam logic [2:0] CARGA = 3'b001;
  localparam logic [2:0] JUEGO = 3'b010;
  localparam logic [2:0] GANO = 3'b011;
  localparam logic [2:0] PERDIO_INTENTOS = 3'b100;
  localparam logic [2:0] PERDIO_TIEMPO = 3'b101;

  localparam logic [1:0] FALLO = 2'b00;
  localparam logic [1:0] ACIERTO = 2'b01;
  localparam logic [1:0] REPETIDA = 2'b10;

  logic clk_tb;
  logic rst_tb;
  logic [2:0] i_state_tb;
  logic i_modo_tb;
  logic [1:0] i_letra_state_tb;
  logic i_letra_lista_tb;
  logic [2:0] i_intentos_tb;
  logic [3:0] i_word_length_tb;
  logic [WORD_MAXLEN-1:0] i_mascara_tb;
  logic [31:0] i_rdata_tb;
  logic o_write_enable_tb;
  logic [1:0] o_addr_tb;
  logic [31:0] o_wdata_tb;

  int pruebas = 0;
  int errores = 0;

  transmisor_uart #(.WORD_MAXLEN(WORD_MAXLEN)) dut (
    .clk(clk_tb),
    .rst(rst_tb),
    .i_state(i_state_tb),
    .i_modo(i_modo_tb),
    .i_letra_state(i_letra_state_tb),
    .i_letra_lista(i_letra_lista_tb),
    .i_intentos(i_intentos_tb),
    .i_word_length(i_word_length_tb),
    .i_mascara(i_mascara_tb),
    .i_rdata(i_rdata_tb),
    .o_write_enable(o_write_enable_tb),
    .o_addr(o_addr_tb),
    .o_wdata(o_wdata_tb)
  );

  always #5 clk_tb = ~clk_tb;

  task automatic ciclo();
    @(posedge clk_tb);
    #1;
  endtask

  // modelo del periferico, send sube cuando se lo escriben y lo baja el solo al terminar, tal como pide el enunciado
  logic send;
  int cuenta_send;

  always_ff @(posedge clk_tb) begin
    if (rst_tb) begin
      send <= 1'b0;
      cuenta_send <= 0;
    end
    else if (o_write_enable_tb && o_addr_tb == ADDR_UART_CTRL && o_wdata_tb[BIT_SEND]) begin
      send <= 1'b1;
      cuenta_send <= CICLOS_SEND;
    end
    else if (cuenta_send > 0) begin
      cuenta_send <= cuenta_send - 1;
      if (cuenta_send == 1) send <= 1'b0;
    end
  end

  always_comb begin
    case (o_addr_tb)
      ADDR_UART_CTRL: i_rdata_tb = {31'b0, send};
      default: i_rdata_tb = 32'b0;
    endcase
  end

  // guarda los bytes que el transmisor va escribiendo en el registro de datos, en orden
  logic limpiar_trama;
  logic [7:0] trama [0:7];
  int n_bytes;

  always_ff @(posedge clk_tb) begin
    if (rst_tb || limpiar_trama) n_bytes <= 0;
    else if (o_write_enable_tb && o_addr_tb == ADDR_UART_TX) begin
      trama[n_bytes] <= o_wdata_tb[7:0];
      n_bytes <= n_bytes + 1;
    end
  end

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

  task automatic arrancar_trama();
    limpiar_trama = 1'b1;
    ciclo();
    limpiar_trama = 1'b0;
  endtask

  // espera a que salgan los bytes esperados y unos ciclos mas, para cazar si manda de mas
  task automatic esperar_trama(input int esperados);
    int n;
    n = 0;
    while (n_bytes < esperados && n < 400) begin
      ciclo();
      n++;
    end
    repeat (CICLOS_SEND * 2) ciclo();
  endtask

  task automatic chequear_largo(input string nombre, input int esperado);
    anotar(nombre, n_bytes === esperado,
           $sformatf("la trama esperaba %0d bytes y trajo %0d", esperado, n_bytes));
  endtask

  task automatic chequear_byte(input string nombre, input int i, input logic [7:0] esperado);
    anotar(nombre, trama[i] === esperado,
           $sformatf("el byte %0d esperaba %02h y dio %02h", i, esperado, trama[i]));
  endtask

  task automatic pulso_letra(input logic [1:0] estado, input logic [2:0] intentos,
                             input logic [WORD_MAXLEN-1:0] mascara);
    i_letra_state_tb = estado;
    i_intentos_tb = intentos;
    i_mascara_tb = mascara;
    i_letra_lista_tb = 1'b1;
    ciclo();
    i_letra_lista_tb = 1'b0;
  endtask

  initial begin
    $dumpfile("tb_transmisor_uart.vcd");
    $dumpvars(0, tb_transmisor_uart);
  end

  initial begin
    clk_tb = 1'b0;
    rst_tb = 1'b1;
    i_state_tb = SELECCION;
    i_modo_tb = 1'b0;
    i_letra_state_tb = FALLO;
    i_letra_lista_tb = 1'b0;
    i_intentos_tb = 3'd0;
    i_word_length_tb = 4'd5;
    i_mascara_tb = '0;
    limpiar_trama = 1'b0;

    ciclo();
    anotar("el reset deja el bus sin escribir", o_write_enable_tb === 1'b0,
           $sformatf("o_write_enable dio %0b", o_write_enable_tb));
    rst_tb = 1'b0;

    repeat (10) ciclo();
    chequear_largo("en seleccion de modo no manda nada", 0);

    // trama de inicio, "I" mas modo mas longitud
    arrancar_trama();
    i_state_tb = JUEGO;
    esperar_trama(3);
    chequear_largo("la trama de inicio son tres bytes", 3);
    chequear_byte("y arranca con la I", 0, 8'h49);
    chequear_byte("el segundo byte es el modo", 1, 8'h00);
    chequear_byte("el tercero es la longitud de la palabra", 2, 8'h05);

    // trama de letra, "L" mas resultado mas intentos mas los dos bytes del patron
    arrancar_trama();
    pulso_letra(ACIERTO, 3'd2, 12'hFE5);
    esperar_trama(5);
    chequear_largo("la trama de letra son cinco bytes", 5);
    chequear_byte("arranca con la L", 0, 8'h4C);
    chequear_byte("el resultado es acierto", 1, 8'h01);
    chequear_byte("los intentos acumulados van en el tercero", 2, 8'h02);
    chequear_byte("el patron manda primero el byte bajo", 3, 8'hE5);
    chequear_byte("y despues el alto", 4, 8'h0F);

    arrancar_trama();
    pulso_letra(FALLO, 3'd3, 12'hFE5);
    esperar_trama(5);
    chequear_byte("un fallo tambien manda trama", 1, 8'h00);
    chequear_byte("con los intentos actualizados", 2, 8'h03);

    arrancar_trama();
    pulso_letra(REPETIDA, 3'd3, 12'hFE5);
    esperar_trama(5);
    chequear_byte("la repetida tambien avisa, si no la pc se queda esperando", 1, 8'h02);

    // trama de fin, "F" mas la causa
    arrancar_trama();
    i_state_tb = GANO;
    esperar_trama(2);
    chequear_largo("la trama de fin son dos bytes", 2);
    chequear_byte("arranca con la F", 0, 8'h46);
    chequear_byte("y lleva el estado que causo el fin", 1, 8'h03);

    $display("%0d pruebas, %0d fallos", pruebas, errores);
    if (errores != 0) $fatal(1, "tb_transmisor_uart termino con fallos");
    $finish;
  end

endmodule
