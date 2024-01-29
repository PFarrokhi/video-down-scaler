`timescale 1 ns / 1 ps

module video_down_scaler_v1_5_data #
(
	parameter integer CTRL_AXI_DATA_WIDTH	= 32,
	parameter integer MAX_INPUT_WIDTH = 3840,
	parameter integer MAX_OUTPUT_WIDTH = 1920,
	parameter integer SCALE_TYPE = 1,
	parameter integer OPERATOIN_DATA_WIDTH = 32,
	parameter integer INPUT_DATA_WIDTH = 32,
	parameter integer OUTPUT_DATA_WIDTH	= 32,
	parameter integer IMAGE_READ_REGISTER_DEPTH = 4,
	parameter integer LOGO_READ_REGISTER_DEPTH = 16,
	parameter integer INVISIBLE_PIXEL = 0,
	parameter integer WRITE_REGISTER_DEPTH = 4
)
(
	/*****************************************************************************
	* internal signals
	*****************************************************************************/
	input wire run,
	input wire reset,
	output wire done,
	input wire logo_valid,
	input wire [CTRL_AXI_DATA_WIDTH-1:0] src_width,
	input wire [CTRL_AXI_DATA_WIDTH-1:0] src_heigth,
	input wire [CTRL_AXI_DATA_WIDTH-1:0] dst_width,
	input wire [CTRL_AXI_DATA_WIDTH-1:0] dst_heigth,
	output wire [CTRL_AXI_DATA_WIDTH-1:0] hlocation_in,
	output wire [CTRL_AXI_DATA_WIDTH-1:0] vlocation_in,
	output wire [CTRL_AXI_DATA_WIDTH-1:0] hlocation_out,
	output wire [CTRL_AXI_DATA_WIDTH-1:0] vlocation_out,
	input wire [CTRL_AXI_DATA_WIDTH-1:0] logo_hlocation_begin,
	input wire [CTRL_AXI_DATA_WIDTH-1:0] logo_hlocation_end,
	input wire [CTRL_AXI_DATA_WIDTH-1:0] logo_vlocation_begin,
	input wire [CTRL_AXI_DATA_WIDTH-1:0] logo_vlocation_end,
	/*****************************************************************************
	* signals of data ports
	*****************************************************************************/
	input wire  M_AXI_ACLK,
	input wire  M_AXI_ARESETN,

	input wire [INPUT_DATA_WIDTH-1 : 0] S_AXIS_TDATA_INPUT,
	input wire S_AXIS_TVALID_INPUT,
	output wire S_AXIS_TREADY_INPUT,
	input wire S_AXIS_TLAST_INPUT,

	output wire [OUTPUT_DATA_WIDTH-1 : 0] S_AXIS_TDATA_LOGO,
	output wire S_AXIS_TVALID_LOGO,
	input wire S_AXIS_TREADY_LOGO,
	output wire S_AXIS_TLAST_LOGO,

	output wire [OUTPUT_DATA_WIDTH-1 : 0] M_AXIS_TDATA_OUTPUT,
	output wire M_AXIS_TVALID_OUTPUT,
	input wire M_AXIS_TREADY_OUTPUT,
	output wire M_AXIS_TLAST_OUTPUT
);

	/*****************************************************************************
	* for byte wise operations
	*****************************************************************************/
	integer byte_index;
	localparam BYTE_NUM = (OPERATOIN_DATA_WIDTH >> 3);

	/*****************************************************************************
	* first part is heigth part and second part is width part
	*****************************************************************************/
	localparam scale_2to1_2to1 = 0;
	localparam scale_3to2_3to2 = 1;
	localparam scale_3to2_2to1 = 2;

	/*****************************************************************************
	* first part is heigth part and second part is width part
	*****************************************************************************/
	/*****************************************************************************
	* ready0 is for when pixel is ready to go directly in that direction
	* ready1 is for when pixel is ready to go undirectly in that direction
	* nready is for when pixel must wait next pixel to go in that direction
	*****************************************************************************/
	localparam STATE_NUM = 9;
	localparam ready0_ready0 = 9'b000000001;
	localparam ready0_ready1 = 9'b000000010;
	localparam ready0_nready = 9'b000000100;
	localparam ready1_ready0 = 9'b000001000;
	localparam ready1_ready1 = 9'b000010000;
	localparam ready1_nready = 9'b000100000;
	localparam nready_ready0 = 9'b001000000;
	localparam nready_ready1 = 9'b010000000;
	localparam nready_nready = 9'b100000000;

	/*****************************************************************************
	* data registeration wires and registers
	*****************************************************************************/
	reg [OPERATOIN_DATA_WIDTH - 1:0] last_pixel;
	reg last_row_read;
	reg last_row_write;
	reg [OPERATOIN_DATA_WIDTH - 1:0] last_row_data_in;
	wire [OPERATOIN_DATA_WIDTH - 1:0] last_row_data_out;

	/*****************************************************************************
	* location wires and registers
	*****************************************************************************/
	reg [$clog2(MAX_INPUT_WIDTH):0] hlocation_in_reg;
	reg [$clog2(MAX_INPUT_WIDTH):0] vlocation_in_reg;
	reg [$clog2(MAX_OUTPUT_WIDTH):0] hlocation_out_reg;
	reg [$clog2(MAX_OUTPUT_WIDTH):0] vlocation_out_reg;
	reg [STATE_NUM - 1:0] state;

	/*****************************************************************************
	* input buffer wires and registers
	*****************************************************************************/
	reg get_pixel;
	reg read_from_logo;
	wire [OPERATOIN_DATA_WIDTH-1 : 0] input_in;
	wire [OPERATOIN_DATA_WIDTH-1 : 0] logo_in;
	reg [OPERATOIN_DATA_WIDTH-1 : 0] pixel_in;
	wire pixel_in_not_ready;
	wire logo_not_ready;
	wire input_read_not_ready;
	wire logo_read_not_ready;

	/*****************************************************************************
	* output buffer wires and registers
	*****************************************************************************/
	reg set_pixel;
	reg [OPERATOIN_DATA_WIDTH-1 : 0] pixel_out;
	wire write_not_ready;
	wire pixel_out_not_ready;

	/*****************************************************************************
	* I/O Connections assignments
	*****************************************************************************/
	assign S_AXIS_TREADY_INPUT = (!input_read_not_ready) && run;
	assign S_AXIS_TREADY_LOGO = (!logo_read_not_ready) && run;
	assign M_AXIS_TVALID_OUTPUT = (!write_not_ready);
	assign M_AXIS_TLAST_OUTPUT = done;
	assign hlocation_in = hlocation_in_reg;
	assign vlocation_in = vlocation_in_reg;
	assign hlocation_out = hlocation_out_reg;
	assign vlocation_out = vlocation_out_reg;

	/*****************************************************************************
	* done signal
	*****************************************************************************/
	assign done = (hlocation_in_reg == (src_width - 1)) &&
		(vlocation_in_reg == (src_heigth - 1)) && write_not_ready;

	/*****************************************************************************
	* operation of each state
	*****************************************************************************/
	always @(*)
	begin
		get_pixel = 1;
		case(state)
		ready0_ready0:
		begin
			pixel_out = pixel_in;
			set_pixel = 1;
		end
		ready0_ready1:
		begin
			for(byte_index = 0; byte_index < BYTE_NUM; byte_index = byte_index+1)
			begin
				pixel_out[(byte_index << 3) +: 8] =
					(pixel_in[(byte_index << 3) +: 8] >> 1) +
					(last_pixel[(byte_index << 3) +: 8] >> 1);
			end
			set_pixel = 1;
		end
		ready1_ready0:
		begin
			for(byte_index = 0; byte_index < BYTE_NUM; byte_index = byte_index+1)
			begin
				pixel_out[(byte_index << 3) +: 8] =
					(pixel_in[(byte_index << 3) +: 8] >> 1) +
					(last_row_data_out[(byte_index << 3) +: 8] >> 1);
			end
			set_pixel = 1;
		end
		ready1_ready1:
		begin
			for(byte_index = 0; byte_index < BYTE_NUM; byte_index = byte_index+1)
			begin
				pixel_out[(byte_index << 3) +: 8] =
					(pixel_in[(byte_index << 3) +: 8] >> 2) +
					(last_pixel[(byte_index << 3) +: 8] >> 2) +
					(last_row_data_out[(byte_index << 3) +: 8] >> 1);
			end
			set_pixel = 1;
		end
		default:
		begin
			pixel_out = 0;
			set_pixel = 0;
		end
		endcase
	end

	/*****************************************************************************
	* last pixel keeper
	*****************************************************************************/
	always @(posedge M_AXI_ACLK)
	begin
		if((M_AXI_ARESETN == 0) || (reset == 1))
		begin
			last_pixel <= 0;
		end
		else if(run && (!pixel_in_not_ready) && (!pixel_out_not_ready) && ((!logo_not_ready) || (!logo_valid)))
		begin
			last_pixel <= pixel_in;
		end
	end

	/*****************************************************************************
	* state flow
	*****************************************************************************/
	always @(posedge M_AXI_ACLK)
	begin
		if((M_AXI_ARESETN == 0) || (reset == 1))
		begin
			hlocation_in_reg <= 0;
			vlocation_in_reg <= 0;
			hlocation_out_reg <= 0;
			vlocation_out_reg <= 0;
			case(SCALE_TYPE)
			scale_2to1_2to1: state <= nready_nready;
			scale_3to2_3to2: state <= ready0_ready0;
			scale_3to2_2to1: state <= ready0_nready;
			default: state <= ready0_ready0;
			endcase
		end
		else if(run && (!pixel_in_not_ready) && (!pixel_out_not_ready) && ((!logo_not_ready) || (!logo_valid)))
		begin
			if(hlocation_in_reg < (src_width - 1))
			begin
				hlocation_in_reg <= hlocation_in_reg + 1;
			end
			else if(vlocation_in_reg < (src_heigth - 1))
			begin
				vlocation_in_reg <= vlocation_in_reg + 1;
				hlocation_in_reg <= 0;
			end
			case(state)
			ready0_ready0:
			begin
				if(hlocation_in_reg < (src_width - 1))
				begin
					hlocation_out_reg <= hlocation_out_reg + 1;
					vlocation_out_reg <= vlocation_out_reg;
					case(SCALE_TYPE)
					scale_2to1_2to1: state <= nready_nready;
					scale_3to2_3to2: state <= ready0_nready;
					scale_3to2_2to1: state <= ready0_nready;
					default: state <= ready0_ready0;
					endcase
				end
				else if(vlocation_in_reg < (src_heigth - 1))
				begin
					hlocation_out_reg <= 0;
					vlocation_out_reg <= vlocation_out_reg + 1;
					case(SCALE_TYPE)
					scale_2to1_2to1: state <= nready_nready;
					scale_3to2_3to2: state <= nready_ready0;
					scale_3to2_2to1: state <= nready_nready;
					default: state <= ready0_ready0;
					endcase
				end
			end
			ready0_ready1:
			begin
				if(hlocation_in_reg < (src_width - 1))
				begin
					hlocation_out_reg <= hlocation_out_reg + 1;
					vlocation_out_reg <= vlocation_out_reg;
					case(SCALE_TYPE)
					scale_2to1_2to1: state <= nready_nready;
					scale_3to2_3to2: state <= ready0_ready0;
					scale_3to2_2to1: state <= ready0_nready;
					default: state <= ready0_ready0;
					endcase
				end
				else if(vlocation_in_reg < (src_heigth - 1))
				begin
					hlocation_out_reg <= 0;
					vlocation_out_reg <= vlocation_out_reg + 1;
					case(SCALE_TYPE)
					scale_2to1_2to1: state <= nready_nready;
					scale_3to2_3to2: state <= nready_ready0;
					scale_3to2_2to1: state <= nready_nready;
					default: state <= ready0_ready0;
					endcase
				end
			end
			ready0_nready:
			begin
				if(hlocation_in_reg < (src_width - 1))
				begin
					case(SCALE_TYPE)
					scale_2to1_2to1: state <= nready_nready;
					scale_3to2_3to2: state <= ready0_ready1;
					scale_3to2_2to1: state <= ready0_ready1;
					default: state <= ready0_ready0;
					endcase
				end
				else if(vlocation_in_reg < (src_heigth - 1))
				begin
					hlocation_out_reg <= 0;
					vlocation_out_reg <= vlocation_out_reg + 1;
					case(SCALE_TYPE)
					scale_2to1_2to1: state <= nready_nready;
					scale_3to2_3to2: state <= nready_ready0;
					scale_3to2_2to1: state <= nready_nready;
					default: state <= ready0_ready0;
					endcase
				end
			end
			ready1_ready0:
			begin
				if(hlocation_in_reg < (src_width - 1))
				begin
					hlocation_out_reg <= hlocation_out_reg + 1;
					vlocation_out_reg <= vlocation_out_reg;
					case(SCALE_TYPE)
					scale_2to1_2to1: state <= ready1_nready;
					scale_3to2_3to2: state <= ready1_nready;
					scale_3to2_2to1: state <= ready1_nready;
					default: state <= ready0_ready0;
					endcase
				end
				else if(vlocation_in_reg < (src_heigth - 1))
				begin
					hlocation_out_reg <= 0;
					vlocation_out_reg <= vlocation_out_reg + 1;
					case(SCALE_TYPE)
					scale_2to1_2to1: state <= nready_nready;
					scale_3to2_3to2: state <= ready0_ready0;
					scale_3to2_2to1: state <= ready0_nready;
					default: state <= ready0_ready0;
					endcase
				end
			end
			ready1_ready1:
			begin
				if(hlocation_in_reg < (src_width - 1))
				begin
					hlocation_out_reg <= hlocation_out_reg + 1;
					vlocation_out_reg <= vlocation_out_reg;
					case(SCALE_TYPE)
					scale_2to1_2to1: state <= ready1_nready;
					scale_3to2_3to2: state <= ready1_ready0;
					scale_3to2_2to1: state <= ready1_nready;
					default: state <= ready0_ready0;
					endcase
				end
				else if(vlocation_in_reg < (src_heigth - 1))
				begin
					hlocation_out_reg <= 0;
					vlocation_out_reg <= vlocation_out_reg + 1;
					case(SCALE_TYPE)
					scale_2to1_2to1: state <= nready_nready;
					scale_3to2_3to2: state <= ready0_ready0;
					scale_3to2_2to1: state <= ready0_nready;
					default: state <= ready0_ready0;
					endcase
				end
			end
			ready1_nready:
			begin
				if(hlocation_in_reg < (src_width - 1))
				begin
					case(SCALE_TYPE)
					scale_2to1_2to1: state <= ready1_ready1;
					scale_3to2_3to2: state <= ready1_ready1;
					scale_3to2_2to1: state <= ready1_ready1;
					default: state <= ready0_ready0;
					endcase
					state <= ready1_ready1;
				end
				else if(vlocation_in_reg < (src_heigth - 1))
				begin
					hlocation_out_reg <= 0;
					vlocation_out_reg <= vlocation_out_reg + 1;
					case(SCALE_TYPE)
					scale_2to1_2to1: state <= nready_nready;
					scale_3to2_3to2: state <= ready0_ready0;
					scale_3to2_2to1: state <= ready0_nready;
					default: state <= ready0_ready0;
					endcase
				end
			end
			nready_ready0:
			begin
				if(hlocation_in_reg < (src_width - 1))
				begin
					case(SCALE_TYPE)
					scale_2to1_2to1: state <= nready_nready;
					scale_3to2_3to2: state <= nready_nready;
					scale_3to2_2to1: state <= nready_nready;
					default: state <= ready0_ready0;
					endcase
				end
				else if(vlocation_in_reg < (src_heigth - 1))
				begin
					case(SCALE_TYPE)
					scale_2to1_2to1: state <= ready1_nready;
					scale_3to2_3to2: state <= ready1_ready0;
					scale_3to2_2to1: state <= ready1_nready;
					default: state <= ready0_ready0;
					endcase
				end
			end
			nready_ready1:
			begin
				if(hlocation_in_reg < (src_width - 1))
				begin
					case(SCALE_TYPE)
					scale_2to1_2to1: state <= nready_nready;
					scale_3to2_3to2: state <= nready_ready0;
					scale_3to2_2to1: state <= nready_nready;
					default: state <= ready0_ready0;
					endcase
				end
				else if(vlocation_in_reg < (src_heigth - 1))
				begin
					case(SCALE_TYPE)
					scale_2to1_2to1: state <= ready1_nready;
					scale_3to2_3to2: state <= ready1_ready0;
					scale_3to2_2to1: state <= ready1_nready;
					default: state <= ready0_ready0;
					endcase
				end
			end
			nready_nready:
			begin
				if(hlocation_in_reg < (src_width - 1))
				begin
					case(SCALE_TYPE)
					scale_2to1_2to1: state <= nready_ready1;
					scale_3to2_3to2: state <= nready_ready1;
					scale_3to2_2to1: state <= nready_ready1;
					default: state <= ready0_ready0;
					endcase
				end
				else if(vlocation_in_reg < (src_heigth - 1))
				begin
					case(SCALE_TYPE)
					scale_2to1_2to1: state <= ready1_nready;
					scale_3to2_3to2: state <= ready1_ready0;
					scale_3to2_2to1: state <= ready1_nready;
					default: state <= ready0_ready0;
					endcase
				end
			end
			endcase
		end
	end

	/*****************************************************************************
	* dummy signal for reserved full and empty signal of last row buffer
	*****************************************************************************/
	wire dummy_empty;
	wire dummy_full;

	/*****************************************************************************
	* FIFO for quick read and write to last_row
	*****************************************************************************/
	FIFO #
	(
	  .RESET_TRIGGER(1),
	  .DATA_WIDTH(OPERATOIN_DATA_WIDTH),
	  .DATA_DEPTH(MAX_OUTPUT_WIDTH)
	) LAST_ROW_FIFO
	(
	  .CLK(M_AXI_ACLK),
	  .RESET((M_AXI_ARESETN == 0) || (reset == 1)),
		.ENABLE(run && (!pixel_in_not_ready) && (!pixel_out_not_ready) && ((!logo_not_ready) || (!logo_valid))),
	  .READ(last_row_read),
	  .WRITE(last_row_write),
	  .DATA_IN(last_row_data_in),
	  .DATA_OUT(last_row_data_out),
	  .EMPTY(dummy_empty),
	  .FULL(dummy_full)
	);

	/*****************************************************************************
	* last row fifo signal controller
	*****************************************************************************/
	always @(*)
	begin
		case(state)
			ready1_ready0:
			begin
				last_row_read = 1;
				last_row_write = 0;
				last_row_data_in = 0;
			end
			ready1_ready1:
			begin
				last_row_read = 1;
				last_row_write = 0;
				last_row_data_in = 0;
			end
			nready_ready0:
			begin
				last_row_read = 0;
				last_row_write = 1;
				last_row_data_in = pixel_in;
			end
			nready_ready1:
			begin
				last_row_read = 0;
				last_row_write = 1;
				for(byte_index = 0; byte_index < BYTE_NUM; byte_index = byte_index+1)
				begin
					last_row_data_in[(byte_index << 3) +: 8] =
						(pixel_in[(byte_index << 3) +: 8] >> 1) +
						(last_pixel[(byte_index << 3) +: 8] >> 1);
				end
			end
			default:
			begin
				last_row_read = 0;
				last_row_write = 0;
				last_row_data_in = 0;
			end
		endcase
	end

	/*****************************************************************************
	* FIFO for independent and fast read data from image
	*****************************************************************************/
	FIFO #
	(
	  .RESET_TRIGGER(1),
	  .DATA_WIDTH(INPUT_DATA_WIDTH),
	  .DATA_DEPTH(IMAGE_READ_REGISTER_DEPTH)
	) IMAGE_READ_FIFO
	(
	  .CLK(M_AXI_ACLK),
	  .RESET((M_AXI_ARESETN == 0) || (reset == 1)),
		.ENABLE(run),
	  .READ(get_pixel && (!pixel_in_not_ready) && (!pixel_out_not_ready) && ((!logo_not_ready) || (!logo_valid))),
	  .WRITE(S_AXIS_TREADY_INPUT && S_AXIS_TVALID_INPUT),
	  .DATA_IN(S_AXIS_TDATA_INPUT),
	  .DATA_OUT(input_in),
	  .EMPTY(pixel_in_not_ready),
	  .FULL(input_read_not_ready)
	);

	/*****************************************************************************
	* FIFO for independent and fast read data from logo
	*****************************************************************************/
	FIFO #
	(
	  .RESET_TRIGGER(1),
	  .DATA_WIDTH(INPUT_DATA_WIDTH),
	  .DATA_DEPTH(LOGO_READ_REGISTER_DEPTH)
	) LOGO_READ_FIFO
	(
	  .CLK(M_AXI_ACLK),
	  .RESET((M_AXI_ARESETN == 0) || (reset == 1)),
		.ENABLE(run),
	  .READ(read_from_logo),
	  .WRITE(S_AXIS_TREADY_LOGO && S_AXIS_TVALID_LOGO),
	  .DATA_IN(S_AXIS_TDATA_LOGO),
	  .DATA_OUT(logo_in),
	  .EMPTY(logo_not_ready),
	  .FULL(logo_read_not_ready)
	);

	/*****************************************************************************
	*input pixel of scaler
	*****************************************************************************/
	always @(*)
	begin
		if(
			(hlocation_in_reg >= logo_hlocation_begin) &&
			(hlocation_in < logo_hlocation_end) &&
			(vlocation_in_reg >= logo_vlocation_begin) &&
			(vlocation_in_reg < logo_vlocation_end) &&
			get_pixel &&
			(!pixel_in_not_ready) &&
			(!pixel_out_not_ready) &&
			(!logo_not_ready) &&
			logo_valid
			)
		begin
			read_from_logo = 1;
			if(logo_in == INVISIBLE_PIXEL)
			begin
				pixel_in = input_in;
			end
			else
			begin
				pixel_in = logo_in;
			end
		end
		else
		begin
			read_from_logo = 0;
			pixel_in = input_in;
		end
	end

	/*****************************************************************************
	* FIFO for independent and fast write data
	*****************************************************************************/
	FIFO #
	(
	  .RESET_TRIGGER(1),
	  .DATA_WIDTH(OUTPUT_DATA_WIDTH),
	  .DATA_DEPTH(WRITE_REGISTER_DEPTH)
	) WRITE_FIFO
	(
	  .CLK(M_AXI_ACLK),
	  .RESET((M_AXI_ARESETN == 0) || (reset == 1)),
		.ENABLE(1),
	  .READ(M_AXIS_TREADY_OUTPUT && M_AXIS_TVALID_OUTPUT),
	  .WRITE(set_pixel && (!pixel_in_not_ready) && (!pixel_out_not_ready) && ((!logo_not_ready) || (!logo_valid)) && run),
	  .DATA_IN(pixel_out),
	  .DATA_OUT(M_AXIS_TDATA_OUTPUT),
	  .EMPTY(write_not_ready),
	  .FULL(pixel_out_not_ready)
	);

endmodule
