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
	parameter SIZE = 1 << SIZE_BIT;
	parameter BC_WIDTH = 46;
	parameter DATA_WIDTH = 8;
	parameter THRES = 6'd44;
	parameter K_MAX = 5;
	parameter MEM_CNT = 8;

	// K, W pattern
	parameter P34 = 46'b1101001110010010011000100100011001100011101011;
	parameter P38 = 46'b1101001110010010011000100011001001100011101011;
	parameter P44 = 46'b1101001110010010001100100100011001100011101011;
	parameter P48 = 46'b1101001110010010001100100011001001100011101011;
	parameter P54 = 46'b1101001110010001001100100100011001100011101011;
	parameter P58 = 46'b1101001110010001001100100011001001100011101011;

	
	reg [DATA_WIDTH-1: 0] w_w [0: K_MAX-1][0: K_MAX-1], w_r [0: K_MAX-1][0: K_MAX-1];

	reg state_w, state_r; // 0: read and find K, W, 1: convolution and output
	reg [2: 0] sctr_w, sctr_r; 
	reg [5: 0] col_ctr_w, col_ctr_r;
	reg [5: 0] row_ctr_w, row_ctr_r;
	reg [5: 0] last_row_w, last_row_r, two_last_row_w, two_last_row_r; 
	reg done_w, done_r, done_2_w, done_2_r;
	reg [4+2*SIZE_BIT - 1: 0] rec_w[0: 5], rec_r [0: 5]; // 0: 34, 1: 38, 2: 44, 3: 48, 4: 54, 5: 58, accm: 4, row: 6, col: 6
	reg [BC_WIDTH - 1: 0] bc_w, bc_r;

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

	reg[8:0] tempdata_w, tempdata_r;

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

	integer i, j;

	always @(*) begin
		case (state_r)
			1'b0: begin 
				
				for (i = 0; i < K_MAX; i = i + 1) begin
					for (j = 0; j < K_MAX; j = j + 1) begin
						w_w[i][j] = w_r[i][j];
					end
				end

				if (done_2_r == 1'b1) begin
					state_w = 1'b1;
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
					in_ready_w = (done_2_r == 1'b1) ? 1'b1 : 1'b0;
				end
				two_last_row_w = last_row_r;
				last_row_w = row_ctr_r;

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
				
				out_valid1_w = (done_2_r == 1'b1) ? 1'b1 : 1'b0;
				out_valid2_w = (done_2_r == 1'b1) ? 1'b1 : 1'b0;
				out_valid3_w = 1'b0;
				out_valid4_w = 1'b0;

				out_data1_w = out_data1_r;
				out_data2_w = out_data2_r;
				case ({KW34, KW38, KW44, KW48, KW54, KW58})
					6'b100000: begin
						out_data1_w = 8'd3;
						out_data2_w = 8'd4;
					end
					6'b010000: begin
						out_data1_w = 8'd3;
						out_data2_w = 8'd8;
					end
					6'b001000: begin
						out_data1_w = 8'd4;
						out_data2_w = 8'd4;
					end
					6'b000100: begin
						out_data1_w = 8'd4;
						out_data2_w = 8'd8;
					end
					6'b000010: begin
						out_data1_w = 8'd5;
						out_data2_w = 8'd4;
					end
					6'b000001: begin
						out_data1_w = 8'd5;
						out_data2_w = 8'd8;
					end
				endcase
				
				out_data3_w = 8'd0;
				out_data4_w = 8'd0;

				out_addr1_w = out_addr1_r;
				out_addr2_w = out_addr2_r;
				out_addr3_w = out_addr3_r;
				out_addr4_w = out_addr4_r;

				// exe_finish_w = (done_2_r == 1'b1) ? 1'b1 : 1'b0; //temp
				exe_finish_w = 1'b0;

				for (i = 0; i < MEM_CNT; i = i + 1) begin
					cen_w[i] = 1'b1;
					wen_w[i] = 1'b1;
					addr_w[i] = addr_r[i];
					data_w[i] = data_r[i];
				end
				cen_w[row_ctr_r[2:0]] = (i_in_valid == 1'b1) ? 1'b0 : 1'b1;
				
				row_temp = (row_ctr_r[2:0] == 3'd0) ? 3'd7 : row_ctr_r[2:0] - 1'b1;
				cen_w[row_temp] = (i_in_valid == 1'b1 && col_ctr_r == 6'd0) ? 1'b0 : 1'b1;

				wen_w[row_ctr_r[2:0]] = 1'b0;
				wen_w[row_temp] = (i_in_valid == 1'b1 && col_ctr_r == 6'd0) ? 1'b0 : 1'b1;

				addr_w[row_ctr_r[2:0]] = {row_ctr_r[5:3], col_ctr_r};
				data_w[row_ctr_r[2:0]] = i_in_data[(3-sctr_r)*DATA_WIDTH+: DATA_WIDTH];

				tempdata_w = tempdata_r;
			end

			1'b1: begin
				
				for (i = 0; i < K_MAX; i = i + 1) begin
					for (j = 0; j < K_MAX; j = j + 1) begin
						w_w[i][j] = w_r[i][j];
					end
				end

				state_w = state_r;
				sctr_w = sctr_r;


				done_w = done_r;
				done_2_w = done_2_r;
				for (i = 0; i < 6; i = i + 1) begin
					rec_w[i] = rec_r[i];
				end
				bc_w = bc_r;

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

				for (i = 0; i < MEM_CNT; i = i + 1) begin
					cen_w[i] = 1'b1;
					wen_w[i] = 1'b1;
					addr_w[i] = addr_r[i];
					data_w[i] = data_r[i];
				end
				cen_w[row_ctr_r[2:0]] = 1'b0;

				row_temp = (row_ctr_r[2:0] == 3'd0) ? 3'd7 : row_ctr_r[2:0] - 1'b1;
				cen_w[row_temp] = (col_ctr_r == 6'd0) ? 1'b0 : 1'b1;
				
				wen_w[row_ctr_r[2:0]] = 1'b1;

				addr_w[row_ctr_r[2:0]] = {row_ctr_r[5:3], col_ctr_r};

				row_ctr_w = (col_ctr_r == 6'd63) ? row_ctr_r + 1'b1 : row_ctr_r;
				col_ctr_w = (col_ctr_r == 6'd63) ? 6'd0 : col_ctr_r + 1'b1;
				last_row_w = row_ctr_r;
				two_last_row_w = last_row_r;
				
				tempdata_w = sram_q[two_last_row_r[2:0]];

				exe_finish_w = (row_ctr_r == 6'd63 && col_ctr_r == 6'd63) ? 1'b1 : 1'b0;
			end
			default: begin
				for (i = 0; i < K_MAX; i = i + 1) begin
					for (j = 0; j < K_MAX; j = j + 1) begin
						w_w[i][j] = w_r[i][j];
					end
				end

				state_w = state_r;
				sctr_w = sctr_r;
				row_ctr_w = row_ctr_r;
				last_row_w = last_row_r;
				two_last_row_w = two_last_row_r;
				col_ctr_w = col_ctr_r;
				done_w = done_r;
				done_2_w = done_2_r;
				for (i = 0; i < 6; i = i + 1) begin
					rec_w[i] = rec_r[i];
				end
				bc_w = bc_r;

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

				exe_finish_w = exe_finish_r;

				for (i = 0; i < MEM_CNT; i = i + 1) begin
					cen_w[i] = cen_r[i];
					wen_w[i] = wen_r[i];
					addr_w[i] = addr_r[i];
					data_w[i] = data_r[i];
				end
				tempdata_w = tempdata_r;
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

			state_r <= 1'b0;
			sctr_r <= 3'b0;
			col_ctr_r <= 6'b0;
			row_ctr_r <= 6'b0;
			last_row_r <= 6'b0;
			two_last_row_r <= 6'b0;
			done_r <= 1'b0;
			done_2_r <= 1'b0;
			for (i = 0; i < 6; i = i + 1) begin
				rec_r[i] <= {(2*SIZE_BIT + 4){1'b0}};
			end
			bc_r <= {BC_WIDTH{1'b0}};

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

			tempdata_r <= 9'd0;
		end
		else begin
			for (i = 0; i < K_MAX; i = i + 1) begin
				for (j = 0; j < K_MAX; j = j + 1) begin
					w_r[i][j] <= w_w[i][j];
				end
			end

			state_r <= state_w;
			sctr_r <= sctr_w;
			row_ctr_r <= row_ctr_w;
			last_row_r <= last_row_w;
			two_last_row_r <= two_last_row_w;
			col_ctr_r <= col_ctr_w;
			done_r <= done_w;
			done_2_r <= done_2_w;
			for (i = 0; i < 6; i = i + 1) begin
				rec_r[i] <= rec_w[i];
			end
			bc_r <= bc_w;

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

			tempdata_r <= tempdata_w;
		end
	end

endmodule
