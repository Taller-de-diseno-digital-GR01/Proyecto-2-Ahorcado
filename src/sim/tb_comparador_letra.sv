`timescale 1ns/1ps

module tb_comparador_letra;

  localparam WORD_MAXLEN = 12;
  localparam LETRA_WIDTH = 5;
  localparam LARGO_WIDTH = $clog2(WORD_MAXLEN+1);

  // el dut solo decodifica CARGA, JUEGO es cualquier otro estado que no recargue la palabra
  localparam logic [2:0] CARGA = 3'b001;
  localparam logic [2:0] JUEGO = 3'b010;

  localparam logic [1:0] FALLO = 2'b00;
  localparam logic [1:0] ACIERTO = 2'b01;
  localparam logic [1:0] REPETIDA = 2'b10;

  logic clk_tb;
  logic rst_tb;
  logic [7:0] i_letra_tb;
  logic i_letra_nueva_tb;
  logic [WORD_MAXLEN*LETRA_WIDTH-1:0] i_word_tb;
  logic [LARGO_WIDTH-1:0] i_word_length_tb;
  logic [2:0] i_state_tb;
  logic [1:0] o_letra_state_tb;
  logic o_letra_lista_tb;
  logic o_palabra_completa_tb;
  logic [WORD_MAXLEN-1:0] o_mascara_tb;
  logic o_try_tb;

  int pruebas = 0;
  int errores = 0;

  comparador_letra #(.WORD_MAXLEN(WORD_MAXLEN), .LETRA_WIDTH(LETRA_WIDTH)) dut (
    .clk(clk_tb),
    .rst(rst_tb),
    .i_letra(i_letra_tb),
    .i_letra_nueva(i_letra_nueva_tb),
    .i_word(i_word_tb),
    .i_word_length(i_word_length_tb),
    .i_state(i_state_tb),
    .o_letra_state(o_letra_state_tb),
    .o_letra_lista(o_letra_lista_tb),
    .o_palabra_completa(o_palabra_completa_tb),
    .o_mascara(o_mascara_tb),
    .o_try(o_try_tb)
  );

  always #5 clk_tb = ~clk_tb;

  // el #1 despues del flanco deja que las salidas se asienten antes de mirarlas
  task automatic ciclo();
    @(posedge clk_tb);
    #1;
  endtask

  // letra 1 en los bits bajos, igual que como lo va a entregar el banco de palabras
  function automatic logic [WORD_MAXLEN*LETRA_WIDTH-1:0] empacar(input string palabra);
    empacar = '0;
    for (int i = 0; i < palabra.len(); i++)
      empacar[i*LETRA_WIDTH +: LETRA_WIDTH] = palabra[i] - 8'h41;
  endfunction

  task automatic cargar(input string palabra);
    i_word_tb = empacar(palabra);
    i_word_length_tb = palabra.len();
    i_state_tb = CARGA;
    ciclo();
    i_state_tb = JUEGO;
  endtask

  task automatic mandar(input logic [7:0] letra);
    i_letra_tb = letra;
    i_letra_nueva_tb = 1'b1;
    ciclo();
    i_letra_nueva_tb = 1'b0;
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

  task automatic chequear_mascara(input string nombre, input logic [WORD_MAXLEN-1:0] esperada);
    anotar(nombre, o_mascara_tb === esperada,
           $sformatf("o_mascara esperaba %012b y dio %012b", esperada, o_mascara_tb));
  endtask

  task automatic chequear_letra(input string nombre, input logic [1:0] estado,
                                input logic lista, input logic intento);
    anotar(nombre,
           o_letra_state_tb === estado && o_letra_lista_tb === lista && o_try_tb === intento,
           $sformatf("esperaba state=%02b lista=%0b try=%0b y dio state=%02b lista=%0b try=%0b",
                     estado, lista, intento, o_letra_state_tb, o_letra_lista_tb, o_try_tb));
  endtask

  task automatic chequear_completa(input string nombre, input logic esperada);
    anotar(nombre, o_palabra_completa_tb === esperada,
           $sformatf("o_palabra_completa esperaba %0b y dio %0b", esperada, o_palabra_completa_tb));
  endtask

  initial begin
    $dumpfile("tb_comparador_letra.vcd");
    $dumpvars(0, tb_comparador_letra);
  end

  initial begin
    clk_tb = 1'b0;
    rst_tb = 1'b1;
    i_letra_tb = 8'h41;
    i_letra_nueva_tb = 1'b0;
    i_word_tb = '0;
    i_word_length_tb = '0;
    i_state_tb = JUEGO;

    $display("== tb_comparador_letra, WORD_MAXLEN=%0d ==", WORD_MAXLEN);

    ciclo();
    chequear_mascara("el reset deja la mascara en ceros", 12'h000);
    chequear_letra("el reset deja las salidas de letra quietas", FALLO, 1'b0, 1'b0);
    chequear_completa("el reset no levanta palabra completa", 1'b0);
    rst_tb = 1'b0;

    cargar("CASA");
    chequear_mascara("CARGA pone el relleno en unos y las cuatro posiciones en cero", 12'hFF0);
    chequear_completa("una palabra recien cargada no esta completa", 1'b0);

    mandar("A");
    chequear_letra("la A esta en CASA y sale como acierto", ACIERTO, 1'b1, 1'b0);
    chequear_mascara("la A revela sus dos posiciones de un solo golpe", 12'hFFA);
    chequear_completa("con la palabra a medias no hay completa", 1'b0);

    ciclo();
    chequear_letra("o_letra_lista dura un solo ciclo", ACIERTO, 1'b0, 1'b0);

    mandar("Z");
    chequear_letra("la Z no esta y gasta intento", FALLO, 1'b1, 1'b1);
    chequear_mascara("un fallo no le mueve nada a la mascara", 12'hFFA);

    ciclo();
    chequear_letra("o_try tambien dura un solo ciclo", FALLO, 1'b0, 1'b0);

    mandar("A");
    chequear_letra("la A repetida avisa pero no gasta intento", REPETIDA, 1'b1, 1'b0);
    chequear_mascara("una repetida no toca la mascara", 12'hFFA);

    mandar("Z");
    chequear_letra("una letra que ya fallo tambien cuenta como repetida", REPETIDA, 1'b1, 1'b0);

    mandar("C");
    chequear_letra("la C acierta", ACIERTO, 1'b1, 1'b0);
    chequear_mascara("la C revela la primera posicion", 12'hFFB);
    chequear_completa("todavia falta la S", 1'b0);

    $display("== %0d pruebas, %0d fallos ==", pruebas, errores);
    if (errores != 0) $fatal(1, "tb_comparador_letra termino con fallos");
    $finish;
  end

endmodule
