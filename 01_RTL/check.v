module test#(
  parameter MAT_SIZE = 16,
  parameter ADDR_WIDTH = 20,
  parameter DATA_WIDTH = 32
)(

);

  // vp vp(
  //   .matrix_v(matrix_v),
  //   .matrix_p(matrix_p),
  //   .x(x),
  //   .y(y),
  //   .z(z),
  //   .W(W),
  //   .H(H),
  //   .x_out(x_out),
  //   .y_out(y_out)
  // );

  // parameter zero_c = 2'sb1;
  // // parameter one_c = -1;
  // parameter two_c = 10'b1000000000; // 0.5
  // parameter three_c = 10'b0010101011; // 1/6


  // reg signed [DATA_W-1:0] a;
  // reg signed [DATA_W-1:0] b;
  // reg signed [DATA_W:0] tempa; 
  // reg signed [DATA_W:0] tempb; 
  // reg signed [DATA_W: 0] temp;
  // reg signed [2*DATA_W-1: 0] two_temp; // 1, 11, 20
  // reg signed [4*DATA_W-1: 0] four_temp; // 1, 23, 40
  // reg signed [6*DATA_W-1: 0] six_temp; // 1, 35, 60

  
  // reg signed [4*DATA_W+FRAC_W-1: 0] four_big_temp; // 1, 11, 20
  // reg signed [BIG_DATA_W: 0] big_temp;
  // reg signed [6*DATA_W+FRAC_W-1: 0] six_big_temp; // 1, 35, 70
  // reg signed [DATA_W-1:0] i_data_a;
  
  wire [5: 0] row;
  assign row = 6'b111100;
  reg [2: 0] rr;

  initial begin
    $display("\n===============================\n");
    
    $display("Row: %b", row);
    rr = row - 3'd2;
    $display("Row - 2: %b", rr[2:0]);
    rr = row - 3'd1;
    $display("Row - 1: %b", rr[2:0]);
    rr = row;
    $display("Row: %b", rr[2:0]);
    rr = row + 3'd1;
    $display("Row + 1: %b", rr[2:0]);
    rr = row + 3'd2;
    $display("Row + 2: %b", rr[2:0]);
    rr = row + 3'd3;
    $display("Row + 3: %b", rr[2:0]);
    rr = row + 3'd4;
    $display("Row + 4: %b", rr[2:0]);
    rr = row + 3'd5;
    $display("Row + 5: %b", rr[2:0]);
    $display("\n===============================\n");
    
    

  end
endmodule