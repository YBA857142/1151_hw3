module core (                       //Don't modify interface
	input      		i_clk,
	input      		i_rst_n,
	input    	  	i_in_valid,
	input 	[31: 0] i_in_data,

	output			o_in_ready,

	output	[ 7: 0]	o_out_data1,
	output	[ 7: 0]	o_out_data2,
	output	[ 7: 0]	o_out_data3,
	output	[ 7: 0]	o_out_data4,

	output	[11: 0] o_out_addr1,
	output	[11: 0] o_out_addr2,
	output	[11: 0] o_out_addr3,
	output	[11: 0] o_out_addr4,

	output 			o_out_valid1,
	output 			o_out_valid2,
	output 			o_out_valid3,
	output 			o_out_valid4,

	output 			o_exe_finish
);


	parameter SIZE_BIT = 6;
	parameter BC_WIDTH = 46;
	parameter DATA_WIDTH = 8;
	parameter K_MAX = 5;
	parameter MEM_CNT = 8;

	// K, W pattern
	parameter P34 = 46'b1101001110010010011000100100011001100011101011;
	parameter P38 = 46'b1101001110010010011000100011001001100011101011;
	parameter P44 = 46'b1101001110010010001100100100011001100011101011;
	parameter P48 = 46'b1101001110010010001100100011001001100011101011;
	parameter P54 = 46'b1101001110010001001100100100011001100011101011;
	parameter P58 = 46'b1101001110010001001100100011001001100011101011;

	integer i, j;

	reg [DATA_WIDTH-1: 0] w_w [0: K_MAX-1][0: K_MAX-1], w_r [0: K_MAX-1][0: K_MAX-1];

	reg [1: 0] state_w, state_r; // 0: read and find K, W, 1: convolution and output
	reg [2: 0] sctr_w, sctr_r;
	reg [7: 0] bctr_w, bctr_r; 
	reg [5: 0] col_ctr_w, col_ctr_r;
	reg [5: 0] last_col_w, last_col_r, two_last_col_w, two_last_col_r;
	reg [5: 0] row_ctr_w, row_ctr_r;
	reg [5: 0] last_row_w, last_row_r, two_last_row_w, two_last_row_r; 
	reg done_w, done_r, done_2_w, done_2_r;
	reg [4+2*SIZE_BIT - 1: 0] rec_w[0: 5], rec_r [0: 5]; // 0: 34, 1: 38, 2: 44, 3: 48, 4: 54, 5: 58, accm: 4, row: 6, col: 6
	reg [BC_WIDTH - 1: 0] bc_w, bc_r;
	reg [3: 0] k_size_w, k_size_r;
	reg [3: 0] batch_w, batch_r;

	reg [7: 0] win_w[0: 4][0: 7], win_r[0: 4][0: 7]; // 5x8 window for convolution
 
	reg [3:0] row_temp;

	reg in_ready_w, in_ready_r;

	reg [7: 0] out_data1_w, out_data2_w, out_data3_w, out_data4_w;
	reg [7: 0] out_data1_r, out_data2_r, out_data3_r, out_data4_r;
	reg [11: 0] out_addr1_w, out_addr2_w, out_addr3_w, out_addr4_w;
	reg [11: 0] out_addr1_r, out_addr2_r, out_addr3_r, out_addr4_r;
	reg out_valid1_w, out_valid2_w, out_valid3_w, out_valid4_w;
	reg out_valid1_r, out_valid2_r, out_valid3_r, out_valid4_r;
	reg exe_finish_w, exe_finish_r;

	wire [7: 0] sram_q[0: MEM_CNT-1];
	reg cen_w[0: MEM_CNT-1], cen_r[0: MEM_CNT-1];
	reg wen_w[0: MEM_CNT-1], wen_r[0: MEM_CNT-1];
	reg [8: 0] addr_w[0: MEM_CNT-1], addr_r[0: MEM_CNT-1];
	reg [7: 0] data_w[0: MEM_CNT-1], data_r[0: MEM_CNT-1];

	genvar m;
	generate
		for (m = 0; m < MEM_CNT; m = m + 1) begin: gen_sram
			sram_512x8 sr(
				.Q(sram_q[m]),
				.CLK(i_clk),
				.CEN(cen_r[m]),
				.WEN(wen_r[m]),
				.A(addr_r[m]),
				.D(data_r[m])
			);
		end
	endgenerate

	wire [7: 0] out_data_raw[0: 3];
	generate
		for (m = 0; m < 4; m = m + 1) begin: gen_mac
			mac mac_inst(
				.w0(w_r[0][0]), .w1(w_r[0][1]), .w2(w_r[0][2]), .w3(w_r[0][3]), .w4(w_r[0][4]),
				.w5(w_r[1][0]), .w6(w_r[1][1]), .w7(w_r[1][2]), .w8(w_r[1][3]), .w9(w_r[1][4]),
				.w10(w_r[2][0]), .w11(w_r[2][1]), .w12(w_r[2][2]), .w13(w_r[2][3]), .w14(w_r[2][4]),
				.w15(w_r[3][0]), .w16(w_r[3][1]), .w17(w_r[3][2]), .w18(w_r[3][3]), .w19(w_r[3][4]),
				.w20(w_r[4][0]), .w21(w_r[4][1]), .w22(w_r[4][2]), .w23(w_r[4][3]), .w24(w_r[4][4]),
				.a0(win_r[0][m]), .a1(win_r[1][m]), .a2(win_r[2][m]), .a3(win_r[3][m]), .a4(win_r[4][m]),
				.a5(win_r[0][m + 1]), .a6(win_r[1][m + 1]), .a7(win_r[2][m + 1]), .a8(win_r[3][m + 1]), .a9(win_r[4][m + 1]),
				.a10(win_r[0][m + 2]), .a11(win_r[1][m + 2]), .a12(win_r[2][m + 2]), .a13(win_r[3][m + 2]), .a14(win_r[4][m + 2]),
				.a15(win_r[0][m + 3]), .a16(win_r[1][m + 3]), .a17(win_r[2][m + 3]), .a18(win_r[3][m + 3]), .a19(win_r[4][m + 3]),
				.a20(win_r[0][m + 4]), .a21(win_r[1][m + 4]), .a22(win_r[2][m + 4]), .a23(win_r[3][m + 4]), .a24(win_r[4][m + 4]),
				.res(out_data_raw[m])
			);
		end
	endgenerate

	wire KW34;
	assign KW34 = (rec_r[0][2*SIZE_BIT+: 4] == 4'd10) ? 1'b1 : 1'b0;
	wire KW38;
	assign KW38 = (rec_r[1][2*SIZE_BIT+: 4] == 4'd10) ? 1'b1 : 1'b0;
	wire KW44;
	assign KW44 = (rec_r[2][2*SIZE_BIT+: 4] == 4'd10) ? 1'b1 : 1'b0;
	wire KW48;
	assign KW48 = (rec_r[3][2*SIZE_BIT+: 4] == 4'd10) ? 1'b1 : 1'b0;
	wire KW54;
	assign KW54 = (rec_r[4][2*SIZE_BIT+: 4] == 4'd10) ? 1'b1 : 1'b0;
	wire KW58;
	assign KW58 = (rec_r[5][2*SIZE_BIT+: 4] == 4'd10) ? 1'b1 : 1'b0;

	wire [5: 0] b_ind[0: 7];
	wire [2: 0] tlb_ind[0: 7];
	wire leg[0: 7];
	assign b_ind[0] = row_ctr_r - 3'd2;
	assign tlb_ind[0] = two_last_row_r - 3'd2;
	assign leg[0] = (two_last_row_r >= 3'd2);

	assign b_ind[1] = row_ctr_r - 3'd1;
	assign tlb_ind[1] = two_last_row_r - 3'd1;
	assign leg[1] = (two_last_row_r >= 3'd1);

	assign b_ind[2] = row_ctr_r;
	assign tlb_ind[2] = two_last_row_r;
	assign leg[2] = (two_last_row_r <= 6'd63);

	assign b_ind[3] = row_ctr_r + 3'd1;
	assign tlb_ind[3] = two_last_row_r + 3'd1;
	assign leg[3] = (two_last_row_r <= 6'd62);

	assign b_ind[4] = row_ctr_r + 3'd2;
	assign tlb_ind[4] = two_last_row_r + 3'd2;
	assign leg[4] = (two_last_row_r <= 6'd61);

	assign b_ind[5] = row_ctr_r + 3'd3;
	assign tlb_ind[5] = two_last_row_r + 3'd3;
	assign leg[5] = (two_last_row_r <= 6'd60);

	assign b_ind[6] = row_ctr_r + 3'd4;
	assign tlb_ind[6] = two_last_row_r + 3'd4;
	assign leg[6] = (two_last_row_r <= 6'd59);

	assign b_ind[7] = row_ctr_r + 3'd5;
	assign tlb_ind[7] = two_last_row_r + 3'd5;
	assign leg[7] = (two_last_row_r <= 6'd58);

	assign o_in_ready = in_ready_r;

	assign o_out_data1 = out_data1_r;
	assign o_out_data2 = out_data2_r;
	assign o_out_data3 = out_data3_r;
	assign o_out_data4 = out_data4_r;

	assign o_out_addr1 = out_addr1_r;
	assign o_out_addr2 = out_addr2_r;
	assign o_out_addr3 = out_addr3_r;
	assign o_out_addr4 = out_addr4_r;

	assign o_out_valid1 = out_valid1_r;
	assign o_out_valid2 = out_valid2_r;
	assign o_out_valid3 = out_valid3_r;
	assign o_out_valid4 = out_valid4_r;

	assign o_exe_finish = exe_finish_r;

	always @(*) begin
		case (state_r)
			2'b00: begin 
				
				for (i = 0; i < K_MAX; i = i + 1) begin
					for (j = 0; j < K_MAX; j = j + 1) begin
						w_w[i][j] = w_r[i][j];
					end
				end

				if (done_2_r == 1'b1) begin
					state_w = 2'b01;
				end
				else begin
					state_w = state_r;
				end

				if (i_in_valid) begin
					sctr_w = (sctr_r == 3'd3) ? 3'd0 : sctr_r + 1'b1;
					row_ctr_w = (col_ctr_r == 6'd63) ? row_ctr_r + 1'b1 : row_ctr_r;
					col_ctr_w = (col_ctr_r == 6'd63) ? 6'd0 : col_ctr_r + 1'b1;
					bc_w = {bc_r[BC_WIDTH-1-1: 0], i_in_data[(3-sctr_r)*DATA_WIDTH]};
					in_ready_w = (sctr_w == 3'd3) ? 1'b1 : 1'b0;
				end
				else begin
					sctr_w = sctr_r;
					row_ctr_w = row_ctr_r;
					col_ctr_w = col_ctr_r;
					bc_w = bc_r;
					in_ready_w = 1'b0;
				end
				bctr_w = bctr_r;
				last_row_w = last_row_r;
				two_last_row_w = two_last_row_r;
				last_col_w = last_col_r;
				two_last_col_w = two_last_col_r;


				done_w = (sctr_r == 3'd3 && row_ctr_r == 6'd63 && col_ctr_r == 6'd63) ? 1'b1 : 1'b0;
				done_2_w = (done_r == 1'b1) ? 1'b1 : 1'b0;

				for (i = 0; i < 6; i = i + 1) begin
					rec_w[i] = rec_r[i];
				end
				case (bc_r)
					P34: begin
						if (row_ctr_r == rec_r[0][SIZE_BIT+: SIZE_BIT] + 1'b1 && col_ctr_r == rec_r[0][0+: SIZE_BIT]) begin
							rec_w[0] = {rec_r[0][2*SIZE_BIT+: 4] + 1'd1, row_ctr_r, col_ctr_r};
						end
						else begin
							rec_w[0] = {4'd1, row_ctr_r, col_ctr_r};
						end
					end
					P38: begin
						if (row_ctr_r == rec_r[1][SIZE_BIT+: SIZE_BIT] + 1'b1 && col_ctr_r == rec_r[1][0+: SIZE_BIT]) begin
							rec_w[1] = {rec_r[1][2*SIZE_BIT+: 4] + 1'd1, row_ctr_r, col_ctr_r};
						end
						else begin
							rec_w[1] = {4'd1, row_ctr_r, col_ctr_r};
						end
					end
					P44: begin
						if (row_ctr_r == rec_r[2][SIZE_BIT+: SIZE_BIT] + 1'b1 && col_ctr_r == rec_r[2][0+: SIZE_BIT]) begin
							rec_w[2] = {rec_r[2][2*SIZE_BIT+: 4] + 1'd1, row_ctr_r, col_ctr_r};
						end
						else begin
							rec_w[2] = {4'd1, row_ctr_r, col_ctr_r};
						end
					end
					P48: begin
						if (row_ctr_r == rec_r[3][SIZE_BIT+: SIZE_BIT] + 1'b1 && col_ctr_r == rec_r[3][0+: SIZE_BIT]) begin
							rec_w[3] = {rec_r[3][2*SIZE_BIT+: 4] + 1'd1, row_ctr_r, col_ctr_r};
						end
						else begin
							rec_w[3] = {4'd1, row_ctr_r, col_ctr_r};
						end
					end
					P54: begin
						if (row_ctr_r == rec_r[4][SIZE_BIT+: SIZE_BIT] + 1'b1 && col_ctr_r == rec_r[4][0+: SIZE_BIT]) begin
							rec_w[4] = {rec_r[4][2*SIZE_BIT+: 4] + 1'd1, row_ctr_r, col_ctr_r};
						end
						else begin
							rec_w[4] = {4'd1, row_ctr_r, col_ctr_r};
						end 
					end
					P58: begin
						if (row_ctr_r == rec_r[5][SIZE_BIT+: SIZE_BIT] + 1'b1 && col_ctr_r == rec_r[5][0+: SIZE_BIT]) begin
							rec_w[5] = {rec_r[5][2*SIZE_BIT+: 4] + 1'd1, row_ctr_r, col_ctr_r};
						end
						else begin
							rec_w[5] = {4'd1, row_ctr_r, col_ctr_r};
						end
					end
				endcase
				batch_w = batch_r;

				for (i = 0; i < 5; i = i + 1) begin
					for (j = 0; j < 8; j = j + 1) begin
						win_w[i][j] = 8'b0;
					end
				end
				
				out_valid1_w = (done_2_r == 1'b1) ? 1'b1 : 1'b0;
				out_valid2_w = (done_2_r == 1'b1) ? 1'b1 : 1'b0;
				out_valid3_w = 1'b0;
				out_valid4_w = 1'b0;

				out_data1_w = out_data1_r;
				out_data2_w = out_data2_r;
				k_size_w = k_size_r;
				case ({KW34, KW38, KW44, KW48, KW54, KW58})
					6'b100000: begin
						out_data1_w = 8'd3;
						out_data2_w = 8'd4;
						k_size_w = 4'd3;
					end
					6'b010000: begin
						out_data1_w = 8'd3;
						out_data2_w = 8'd8;
						k_size_w = 4'd3;
					end
					6'b001000: begin
						out_data1_w = 8'd4;
						out_data2_w = 8'd4;
						k_size_w = 4'd4;
					end
					6'b000100: begin
						out_data1_w = 8'd4;
						out_data2_w = 8'd8;
						k_size_w = 4'd4;
					end
					6'b000010: begin
						out_data1_w = 8'd5;
						out_data2_w = 8'd4;
						k_size_w = 4'd5;
					end
					6'b000001: begin
						out_data1_w = 8'd5;
						out_data2_w = 8'd8;
						k_size_w = 4'd5;
					end
				endcase
				
				out_data3_w = 8'd0;
				out_data4_w = 8'd0;

				out_addr1_w = out_addr1_r;
				out_addr2_w = out_addr2_r;
				out_addr3_w = out_addr3_r;
				out_addr4_w = out_addr4_r;

				exe_finish_w = (done_2_r == 1'b1) ? 1'b1 : 1'b0;

				for (i = 0; i < MEM_CNT; i = i + 1) begin
					cen_w[i] = 1'b1;
					wen_w[i] = 1'b1;
					addr_w[i] = addr_r[i];
					data_w[i] = data_r[i];
				end
				cen_w[row_ctr_r[2:0]] = (i_in_valid == 1'b1) ? 1'b0 : 1'b1;
				
				// row_temp = (row_ctr_r[2:0] == 3'd0) ? 3'd7 : row_ctr_r[2:0] - 1'b1;
				// cen_w[row_temp] = (i_in_valid == 1'b1 && col_ctr_r == 6'd0) ? 1'b0 : 1'b1;

				wen_w[row_ctr_r[2:0]] = 1'b0;
				// wen_w[row_temp] = (i_in_valid == 1'b1 && col_ctr_r == 6'd0) ? 1'b0 : 1'b1;

				addr_w[row_ctr_r[2:0]] = {row_ctr_r[5:3], col_ctr_r};
				data_w[row_ctr_r[2:0]] = i_in_data[(3-sctr_r)*DATA_WIDTH+: DATA_WIDTH];
			end

			2'b01: begin
				for (i = 0; i < K_MAX; i = i + 1) begin
					for (j = 0; j < K_MAX; j = j + 1) begin
						w_w[i][j] = w_r[i][j];
					end
				end
				bctr_w = bctr_r;
				if (i_in_valid == 1'b1) begin
					sctr_w = (sctr_r == 3'd3) ? 3'd0 : sctr_r + 1'b1;
					
					case (k_size_r)
						4'd3: begin
							w_w[1+row_ctr_r[2:0]][1+col_ctr_r[2:0]] = i_in_data[(3-sctr_r)*DATA_WIDTH+: DATA_WIDTH];
							col_ctr_w = (batch_r == 3'd2 && sctr_r == 3'd3) ? 6'd0 : ((col_ctr_r == 6'd2) ? 6'd0 : col_ctr_r + 1'b1);
							row_ctr_w = (batch_r == 3'd2 && sctr_r == 3'd3) ? 6'd0 : ((col_ctr_r == 6'd2) ? row_ctr_r + 1'b1 : row_ctr_r);
						end
						4'd4: begin
							w_w[1+row_ctr_r[2:0]][1+col_ctr_r[2:0]] = i_in_data[(3-sctr_r)*DATA_WIDTH+: DATA_WIDTH];
							col_ctr_w = (batch_r == 3'd3 && sctr_r == 3'd3) ? 6'd0 : ((col_ctr_r == 6'd3) ? 6'd0 : col_ctr_r + 1'b1);
							row_ctr_w = (batch_r == 3'd3 && sctr_r == 3'd3) ? 6'd0 : ((col_ctr_r == 6'd3) ? row_ctr_r + 1'b1 : row_ctr_r);
						end
						4'd5: begin
							w_w[row_ctr_r[2:0]][col_ctr_r[2:0]] = i_in_data[(3-sctr_r)*DATA_WIDTH+: DATA_WIDTH];
							col_ctr_w = (batch_r == 3'd6 && sctr_r == 3'd3) ? 6'd0 : ((col_ctr_r == 6'd4) ? 6'd0 : col_ctr_r + 1'b1);
							row_ctr_w = (batch_r == 3'd6 && sctr_r == 3'd3) ? 6'd0 : ((col_ctr_r == 6'd4) ? row_ctr_r + 1'b1 : row_ctr_r);
						end
						default: begin
							col_ctr_w = col_ctr_r;
							row_ctr_w = row_ctr_r;
						end
					endcase
					in_ready_w = (sctr_w == 3'd3) ? 1'b1 : 1'b0;
				end
				else begin
					sctr_w = sctr_r;
					col_ctr_w = 6'b0;
					row_ctr_w = 6'b0;
					in_ready_w = 1'b0;
				end

				// if (row_ctr_r == {2'b0, k_size_r} && col_ctr_r == k_size_r - 1'b1) begin
				// if (row_ctr_r == k_size_r - 1 && col_ctr_r == k_size_r - 1) begin
				// 	state_w = 2'b10;
				// end
				// else begin
				// 	state_w = state_r;
				// end

				case (k_size_r)
						4'd3: begin
							state_w = (batch_r == 3'd2 && sctr_r == 3'd3) ? 2'b10 : state_r;
						end
						4'd4: begin
							state_w = (batch_r == 3'd3 && sctr_r == 3'd3) ? 2'b10 : state_r;
						end
						4'd5: begin
							state_w = (batch_r == 3'd6 && sctr_r == 3'd3) ? 2'b10 : state_r;
						end
						default: begin
							state_w = state_r;
						end
				endcase

				done_w = done_r;
				done_2_w = done_2_r;
				for (i = 0; i < 6; i = i + 1) begin
					rec_w[i] = rec_r[i];
				end
				bc_w = bc_r;
				k_size_w = k_size_r;
				batch_w = (sctr_r == 3'd3) ? batch_r + 1'b1 : batch_r;

				for (i = 0; i < 5; i = i + 1) begin
					for (j = 0; j < 8; j = j + 1) begin
						win_w[i][j] = 8'b0;
					end
				end
				

				out_data1_w = out_data1_r;
				out_data2_w = out_data2_r;
				out_data3_w = out_data3_r;
				out_data4_w = out_data4_r;

				out_addr1_w = out_addr1_r;
				out_addr2_w = out_addr2_r;
				out_addr3_w = out_addr3_r;
				out_addr4_w = out_addr4_r;

				out_valid1_w = 1'b0;
				out_valid2_w = 1'b0;
				out_valid3_w = 1'b0;
				out_valid4_w = 1'b0;

				for (i = 0; i < MEM_CNT; i = i + 1) begin
					cen_w[i] = 1'b1;
					wen_w[i] = 1'b1;
					addr_w[i] = addr_r[i];
					data_w[i] = data_r[i];
				end
				last_row_w = last_row_r;
				two_last_row_w = two_last_row_r;
				last_col_w = last_col_r;
				two_last_col_w = two_last_col_r;

				// exe_finish_w = (row_ctr_r == {2'b0, k_size_r}) ? 1'b1 : 1'b0;
				exe_finish_w = 1'b0;
			end

			2'b10: begin
				for (i = 0; i < K_MAX; i = i + 1) begin
					for (j = 0; j < K_MAX; j = j + 1) begin
						w_w[i][j] = w_r[i][j];
					end
				end //fx

				state_w = state_r;
				sctr_w = (sctr_r == 3'd4) ? ((col_ctr_r == 6'd63) ? 3'd0 : sctr_r) : sctr_r + 1'b1;
				bctr_w = (col_ctr_r == 6'd63) ? 7'd0 : bctr_r + 1'b1;

				row_ctr_w = (col_ctr_r == 6'd63) ? row_ctr_r + 3'd4 : row_ctr_r;
				last_row_w = row_ctr_r;
				two_last_row_w = last_row_r;

				col_ctr_w = (sctr_r == 3'd4) ? ((col_ctr_r == 6'd63) ? 3'd0 : col_ctr_r + 1'b1) : col_ctr_r;
				last_col_w = col_ctr_r;
				two_last_col_w = last_col_r;
				
				done_w = done_r; 
				done_2_w = done_2_r;
				for (i = 0; i < 6; i = i + 1) begin
					rec_w[i] = rec_r[i];
				end //fx
				bc_w = bc_r; //fx
				k_size_w = k_size_r; //fx
				batch_w = batch_r; //fx
				
				for (i = 0; i < 5; i = i + 1) begin
					for (j = 0; j < 8; j = j + 1) begin
						win_w[i][j] = 8'b0;
					end
				end
				if (sctr_r == 3'd1 || sctr_r == 3'd0) begin
					for (i = 0; i < 5; i = i + 1) begin
						for (j = 0; j < 8; j = j + 1) begin
							win_w[i][j] = 8'b0;
						end
					end
				end
				else if (col_ctr_r == 6'd63 || col_ctr_r == 6'd62) begin
					for (i = 0; i < 4; i = i + 1) begin
						for (j = 0; j < 8; j = j + 1) begin
							win_w[i][j] = win_r[i+1][j];
						end
					end
					for (j = 0; j < 8; j = j + 1) begin
							win_w[4][j] = 8'b0;
					end
				end
				else begin
					for (i = 0; i < 4; i = i + 1) begin
						for (j = 0; j < 8; j = j + 1) begin
							win_w[i][j] = win_r[i+1][j];
						end
					end
					for (j = 0; j < 8; j = j + 1) begin
							win_w[4][j] = leg[j] ? sram_q[tlb_ind[j]] : 8'b0;
					end
				end

				in_ready_w = 1'b0; //fx

				out_data1_w = out_data_raw[0];
				out_data2_w = out_data_raw[1];
				out_data3_w = out_data_raw[2];
				out_data4_w = out_data_raw[3];

				out_addr1_w = {two_last_row_r, two_last_col_r};
				out_addr2_w = {two_last_row_r + 3'd1, two_last_col_r};
				out_addr3_w = {two_last_row_r + 3'd2, two_last_col_r};
				out_addr4_w = {two_last_row_r + 3'd3, two_last_col_r};

				out_valid1_w = (bctr_r >= 7'd7 || bctr_r <= 7'd1) ? 1'b1 : 1'b0;
				out_valid2_w = (bctr_r >= 7'd7 || bctr_r <= 7'd1) ? 1'b1 : 1'b0;
				out_valid3_w = (bctr_r >= 7'd7 || bctr_r <= 7'd1) ? 1'b1 : 1'b0;
				out_valid4_w = (bctr_r >= 7'd7 || bctr_r <= 7'd1) ? 1'b1 : 1'b0;
				
				// exe_finish_w = exe_finish_r;
				exe_finish_w = (row_ctr_r == 6'd60 && col_ctr_r == 6'd63) ? 1'b1 : 1'b0;

				for (i = 0; i < MEM_CNT; i = i + 1) begin
					addr_w[i] = addr_r[i];
				end
				for (i = 0; i < MEM_CNT; i = i + 1) begin
					cen_w[i] = 1'b0;
					wen_w[i] = 1'b1;
					if (sctr_r == 3'd4) begin
						addr_w[b_ind[i][2:0]] = {b_ind[i][5:3], col_ctr_r+3'd4}; //row+i-2
					end
					else begin
						addr_w[b_ind[i][2:0]] = {b_ind[i][5:3], 3'b0, sctr_r[2:0]};
					end
					data_w[i] = data_r[i];
				end


			end

			default: begin
				for (i = 0; i < K_MAX; i = i + 1) begin
					for (j = 0; j < K_MAX; j = j + 1) begin
						w_w[i][j] = w_r[i][j];
					end
				end

				state_w = state_r;
				sctr_w = sctr_r;
				bctr_w = bctr_r;
				row_ctr_w = row_ctr_r;
				last_row_w = last_row_r;
				two_last_row_w = two_last_row_r;
				last_col_w = last_col_r;
				two_last_col_w = two_last_col_r;
				col_ctr_w = col_ctr_r;
				done_w = done_r;
				done_2_w = done_2_r;
				for (i = 0; i < 6; i = i + 1) begin
					rec_w[i] = rec_r[i];
				end
				bc_w = bc_r;
				k_size_w = k_size_r;
				batch_w = batch_r;

				for (i = 0; i < 5; i = i + 1) begin
					for (j = 0; j < 8; j = j + 1) begin
						win_w[i][j] = 8'b0;
					end
				end
				

				in_ready_w = in_ready_r;

				out_data1_w = out_data1_r;
				out_data2_w = out_data2_r;
				out_data3_w = out_data3_r;
				out_data4_w = out_data4_r;

				out_addr1_w = out_addr1_r;
				out_addr2_w = out_addr2_r;
				out_addr3_w = out_addr3_r;
				out_addr4_w = out_addr4_r;

				out_valid1_w = 1'b0;
				out_valid2_w = 1'b0;
				out_valid3_w = 1'b0;
				out_valid4_w = 1'b0;

				exe_finish_w = (row_ctr_r == 6'd63 && col_ctr_r == 6'd63) ? 1'b1 : 1'b0;

				for (i = 0; i < MEM_CNT; i = i + 1) begin
					cen_w[i] = 1'b0;
					wen_w[i] = 1'b1;
					addr_w[i] = addr_r[i];
					data_w[i] = data_r[i];
				end
			end	
		endcase
	end

	always @(posedge i_clk or negedge i_rst_n) begin
		if(!i_rst_n) begin
			for (i = 0; i < K_MAX; i = i + 1) begin
				for (j = 0; j < K_MAX; j = j + 1) begin
					w_r[i][j] <= {DATA_WIDTH{1'b0}};
				end
			end

			state_r <= 2'b00;
			sctr_r <= 3'b0;
			bctr_r <= 7'b0;
			col_ctr_r <= 6'b0;
			row_ctr_r <= 6'b0;
			last_row_r <= 6'b0;
			two_last_row_r <= 6'b0;
			last_col_r <= 6'b0;
			two_last_col_r <= 6'b0;
			done_r <= 1'b0;
			done_2_r <= 1'b0;
			for (i = 0; i < 6; i = i + 1) begin
				rec_r[i] <= {(2*SIZE_BIT + 4){1'b0}};
			end
			bc_r <= {BC_WIDTH{1'b0}};
			k_size_r <= 4'b0;
			batch_r <= 4'b0;

			for (i = 0; i < 5; i = i + 1) begin
				for (j = 0; j < 8; j = j + 1) begin
					win_r[i][j] <= 8'b0;
				end
			end		

			in_ready_r <= 1'b0;

			out_data1_r <= 8'd0;
			out_data2_r <= 8'd0;
			out_data3_r <= 8'd0;
			out_data4_r <= 8'd0;

			out_addr1_r <= 12'd0;
			out_addr2_r <= 12'd0;
			out_addr3_r <= 12'd0;
			out_addr4_r <= 12'd0;

			out_valid1_r <= 1'b0;
			out_valid2_r <= 1'b0;
			out_valid3_r <= 1'b0;
			out_valid4_r <= 1'b0;

			exe_finish_r <= 1'b0;

			for (i = 0; i < MEM_CNT; i = i + 1) begin
				cen_r[i] <= 1'b0;
				wen_r[i] <= 1'b1;
				addr_r[i] <= 9'd0;
				data_r[i] <= 8'd0;
			end
		end
		else begin
			for (i = 0; i < K_MAX; i = i + 1) begin
				for (j = 0; j < K_MAX; j = j + 1) begin
					w_r[i][j] <= w_w[i][j];
				end
			end

			state_r <= state_w;
			sctr_r <= sctr_w;
			bctr_r <= bctr_w;
			row_ctr_r <= row_ctr_w;
			last_row_r <= last_row_w;
			two_last_row_r <= two_last_row_w;
			last_col_r <= last_col_w;
			two_last_col_r <= two_last_col_w;
			col_ctr_r <= col_ctr_w;
			done_r <= done_w;
			done_2_r <= done_2_w;
			for (i = 0; i < 6; i = i + 1) begin
				rec_r[i] <= rec_w[i];
			end
			bc_r <= bc_w;
			k_size_r <= k_size_w;
			batch_r <= batch_w;

			for (i = 0; i < 5; i = i + 1) begin
				for (j = 0; j < 8; j = j + 1) begin
					win_r[i][j] <= win_w[i][j];
				end
			end
			

			in_ready_r <= in_ready_w;

			out_data1_r <= out_data1_w;
			out_data2_r <= out_data2_w;
			out_data3_r <= out_data3_w;
			out_data4_r <= out_data4_w;

			out_addr1_r <= out_addr1_w;
			out_addr2_r <= out_addr2_w;
			out_addr3_r <= out_addr3_w;
			out_addr4_r <= out_addr4_w;

			out_valid1_r <= out_valid1_w;
			out_valid2_r <= out_valid2_w;
			out_valid3_r <= out_valid3_w;
			out_valid4_r <= out_valid4_w;
			
			exe_finish_r <= exe_finish_w;

			for (i = 0; i < MEM_CNT; i = i + 1) begin
				cen_r[i] <= cen_w[i];
				wen_r[i] <= wen_w[i];
				addr_r[i] <= addr_w[i];
				data_r[i] <= data_w[i];
			end
		end
	end

endmodule
