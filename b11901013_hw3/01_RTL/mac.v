// 25-input multiply-accumulate with round-to-nearest and clamp.
//   w0..w24 : Q0.7  (signed two's complement, value = w / 128)
//   a0..a24 : UQ8.0 (unsigned integer 0..255)
//   res     : UQ8.0 = clamp(round(sum(a_i * w_i)), 0, 255)
//
// Rounding: round half up (ties toward +infinity), i.e. floor(x + 0.5).
// Fully combinational.

module mac (
    input  wire [7:0] w0,  w1,  w2,  w3,  w4,  w5,  w6,  w7,  w8,  w9,
                      w10, w11, w12, w13, w14, w15, w16, w17, w18, w19,
                      w20, w21, w22, w23, w24,
    input  wire [7:0] a0,  a1,  a2,  a3,  a4,  a5,  a6,  a7,  a8,  a9,
                      a10, a11, a12, a13, a14, a15, a16, a17, a18, a19,
                      a20, a21, a22, a23, a24,
    output wire [7:0] res
);

    // Each product: unsigned 8b x signed 8b -> signed 17b, magnitude <= 255*128 = 32640
    // Sum of 25 products: magnitude <= 816000 < 2^20, so 21 signed bits suffice; use 22.
    localparam integer ACC_W = 22;

    // Signed product with the unsigned operand zero-extended to 9 bits
    function automatic signed [16:0] mul;
        input [7:0] a;
        input [7:0] w;
        reg signed [8:0] a_s;
        reg signed [8:0] w_s;
        begin
            a_s = {9'b0, a};              // zero-extend unsigned a to 17 bits
            w_s = {{9{w[7]}}, w};
            mul = a_s * w_s;
        end
    endfunction

    wire signed [ACC_W-1:0] sum =
          $signed(mul(a0,  w0 )) + $signed(mul(a1,  w1 )) + $signed(mul(a2,  w2 ))
        + $signed(mul(a3,  w3 )) + $signed(mul(a4,  w4 )) + $signed(mul(a5,  w5 ))
        + $signed(mul(a6,  w6 )) + $signed(mul(a7,  w7 )) + $signed(mul(a8,  w8 ))
        + $signed(mul(a9,  w9 )) + $signed(mul(a10, w10)) + $signed(mul(a11, w11))
        + $signed(mul(a12, w12)) + $signed(mul(a13, w13)) + $signed(mul(a14, w14))
        + $signed(mul(a15, w15)) + $signed(mul(a16, w16)) + $signed(mul(a17, w17))
        + $signed(mul(a18, w18)) + $signed(mul(a19, w19)) + $signed(mul(a20, w20))
        + $signed(mul(a21, w21)) + $signed(mul(a22, w22)) + $signed(mul(a23, w23))
        + $signed(mul(a24, w24));

    // sum has 7 fractional bits. Add 0.5 (= 64) and arithmetic-shift right by 7
    // => floor(sum/128 + 0.5) = round half up.
    wire signed [ACC_W-1:0] rounded = (sum + 22'sd64) >>> 7;

    // Clamp to [0, 255]
    assign res = rounded[ACC_W-1]            ? 8'd0   :   // negative
                 (rounded > 22'sd255)        ? 8'd255 :   // overflow
                                               rounded[7:0];

endmodule