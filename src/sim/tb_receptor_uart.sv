`timescale 1ns/1ps

module tb_receptor_uart;

  localparam TICKS = 54; // (100e6 / 115200) / 16 = 54.25
  localparam CICLOS_BIT = TICKS * 16;

  localparam logic [1:0] ADDR_CTRL = 2'b10;
  localparam logic [1:0] ADDR_DATOS_RX = 2'b01;
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

  uart_rx #(.TICKS_X16(TICKS)) nucleo (
    .clk(clk_tb),
    .rst(rst_tb),
    .i_rx(rx_linea),
    .o_dato_listo(rx_data_rdy),
    .o_dato(rx_data_out)
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

  // el nucleo termina el byte a mitad del bit de stop, o sea que el receptor lo atiende mientras la linea
  logic limpiar_visto;
  logic hubo_atencion;
  logic [7:0] letra_vista;
  logic valid_visto;

  always_ff @(posedge clk_tb) begin
    if (rst_tb || limpiar_visto) begin
      hubo_atencion <= 1'b0;
      letra_vista <= 8'h00;
      valid_visto <= 1'b0;
    end
    else if (o_write_enable_tb && o_addr_tb == ADDR_CTRL) begin
      hubo_atencion <= 1'b1;
      letra_vista <= o_letra_tb;
      valid_visto <= o_valid_w_tb;
    end
  end

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

  task automatic enviar(input logic [7:0] b);
    limpiar_visto = 1'b1;
    ciclo();
    limpiar_visto = 1'b0;
    serial(b);
    repeat (20) ciclo();
  endtask

  task automatic chequear_entrega(input string nombre, input logic [7:0] letra);
    anotar(nombre, hubo_atencion === 1'b1 && letra_vista === letra && valid_visto === 1'b1,
           $sformatf("esperaba atendido con letra=%02h y valid=1, y dio atendido=%0b letra=%02h valid=%0b",
                     letra, hubo_atencion, letra_vista, valid_visto));
  endtask

  task automatic chequear_descarte(input string nombre);
    anotar(nombre, hubo_atencion === 1'b1 && valid_visto === 1'b0,
           $sformatf("esperaba atendido sin valid, y dio atendido=%0b valid=%0b",
                     hubo_atencion, valid_visto));
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

    enviar("Z");
    chequear_entrega("la Z pasa, es el borde de arriba del rango", 8'h5A);

    enviar(8'h40);
    chequear_descarte("el arroba queda justo debajo de la A y se descarta");
    chequear_bus("y aun asi volvio a espera, el receptor no se traba", ADDR_CTRL, 1'b0);

    enviar(8'h5B);
    chequear_descarte("el corchete queda justo encima de la Z y se descarta");

    enviar("a");
    chequear_descarte("una minuscula se descarta");

    enviar("7");
    chequear_descarte("un digito se descarta");

    enviar("M");
    chequear_entrega("despues de varios bytes botados sigue entregando bien", 8'h4D);

    i_state_tb = SELECCION;
    enviar("M");
    chequear_descarte("una letra valida en seleccion de modo se descarta, pero igual limpia new_rx");

    i_state_tb = RESULTADO;
    enviar("M");
    chequear_descarte("una letra valida mostrando resultado tambien se descarta");

    i_state_tb = JUEGO;
    enviar("M");
    chequear_entrega("de vuelta en juego la vuelve a aceptar", 8'h4D);

    // sin un solo ciclo de linea en reposo entre el stop de uno y el start del otro
    limpiar_visto = 1'b1;
    ciclo();
    limpiar_visto = 1'b0;
    serial("H");
    chequear_entrega("el primero de un par pegado sale bien", 8'h48);
    limpiar_visto = 1'b1;
    ciclo();
    limpiar_visto = 1'b0;
    serial("I");
    repeat (20) ciclo();
    chequear_entrega("el segundo del par pegado tambien", 8'h49);

    // rst a mitad del byte, el que venia en camino se pierde y el receptor tiene que quedar sano
    fork
      serial("Q");
      begin
        repeat (CICLOS_BIT * 4) ciclo();
        rst_tb = 1'b1;
        repeat (10) ciclo();
        rst_tb = 1'b0;
      end
    join
    // la cola del byte cortado deja bits sueltos en la linea, el nucleo resincroniza sobre ellos y arma un frame falso
    repeat (CICLOS_BIT * 12) ciclo();
    chequear_valid("pasado el ruido del corte no queda ninguna letra entregandose", 1'b0);
    chequear_bus("y el bus quedo de vuelta en espera", ADDR_CTRL, 1'b0);

    enviar("W");
    chequear_entrega("y sigue recibiendo bien despues de ese rst", 8'h57);

    $display("%0d pruebas, %0d fallos", pruebas, errores);
    if (errores != 0) $fatal(1, "tb_receptor_uart termino con fallos");
    $finish;
  end

endmodule
