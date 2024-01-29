`timescale 1 ns / 1 ps

module video_down_scaler_v1_5 #
(
	parameter integer MAX_INPUT_WIDTH = 3840,
	parameter integer MAX_OUTPUT_WIDTH = 1920,
	/*****************************************************************************
	* SCALE_TYPE is about what the module do
	* SCALE_TYPE 0 is for scale down 2:1. for example 3840*2160 to 1920*1080
	* SCALE_TYPE 1 is for scale down 3:2. for example 1920*1080 to 1280*720
	* SCALE_TYPE 2 is for scale down 3:2 beside transform 16:9 to 4:3.
	* for example if you want to have 640*480 resolution, then you must scale
	* 1280*720 to 640*480 by this scale type.
	* invalid SCALE_TYPE send input video directly to output
	*****************************************************************************/
	parameter integer SCALE_TYPE = 1,
	parameter integer CTRL_AXI_DATA_WIDTH	= 32,
	parameter integer CTRL_AXI_ADDR_WIDTH	= 8,
	// diffrent data width in master not available for now
	parameter integer DATA_WIDTH	= 32,
	// parameter integer OPERATOIN_DATA_WIDTH	= 32,
	// parameter integer INPUT_DATA_WIDTH	= 32,
	// parameter integer OUTPUT_DATA_WIDTH	= 32,
	parameter integer IMAGE_READ_REGISTER_DEPTH = 4,
	parameter integer LOGO_READ_REGISTER_DEPTH = 16,
	parameter integer INVISIBLE_PIXEL = 0,
	parameter integer WRITE_REGISTER_DEPTH = 4
)
(
	// diffrent clock domain between slave and master require double clock FIFO
	input wire axi_aclk,
	input wire axi_aresetn,

	/*****************************************************************************
	* control port signals
	*****************************************************************************/
	// input wire ctrl_axi_aclk,
	// input wire ctrl_axi_aresetn,
	input wire [CTRL_AXI_ADDR_WIDTH-1 : 0] ctrl_axi_awaddr,
	input wire ctrl_axi_awvalid,
	output wire ctrl_axi_awready,
	input wire [CTRL_AXI_DATA_WIDTH-1 : 0] ctrl_axi_wdata,
	input wire ctrl_axi_wvalid,
	output wire ctrl_axi_wready,
	output wire [1 : 0] ctrl_axi_bresp,
	output wire ctrl_axi_bvalid,
	input wire ctrl_axi_bready,
	input wire [CTRL_AXI_ADDR_WIDTH-1 : 0] ctrl_axi_araddr,
	input wire ctrl_axi_arvalid,
	output wire ctrl_axi_arready,
	output wire [CTRL_AXI_DATA_WIDTH-1 : 0] ctrl_axi_rdata,
	output wire ctrl_axi_rvalid,
	input wire ctrl_axi_rready,

	/*****************************************************************************
	* data ports signals
	*****************************************************************************/
	// input wire data_axi_aclk,
	// input wire data_axi_aresetn,
	input wire [DATA_WIDTH-1 : 0] s_axis_tdata_input,
	input wire s_axis_tvalid_input,
	output wire s_axis_tready_input,
	input wire s_axis_tlast_input,

	input wire [DATA_WIDTH-1 : 0] s_axis_tdata_logo,
	input wire s_axis_tvalid_logo,
	output wire s_axis_tready_logo,
	input wire s_axis_tlast_logo,

	output wire [DATA_WIDTH-1 : 0] m_axis_tdata_output,
	output wire m_axis_tvalid_output,
	input wire m_axis_tready_output,
	output wire m_axis_tlast_output
);

	/*****************************************************************************
	* internal signals
	*****************************************************************************/
	wire run;
	wire reset;
	wire done;
	wire logo_valid;
	wire [CTRL_AXI_DATA_WIDTH-1:0] src_width;
	wire [CTRL_AXI_DATA_WIDTH-1:0] src_heigth;
	wire [CTRL_AXI_DATA_WIDTH-1:0] dst_width;
	wire [CTRL_AXI_DATA_WIDTH-1:0] dst_heigth;
	wire [CTRL_AXI_DATA_WIDTH-1:0] hlocation_in;
	wire [CTRL_AXI_DATA_WIDTH-1:0] vlocation_in;
	wire [CTRL_AXI_DATA_WIDTH-1:0] hlocation_out;
	wire [CTRL_AXI_DATA_WIDTH-1:0] vlocation_out;
	wire [CTRL_AXI_DATA_WIDTH-1:0] logo_hlocation_begin;
	wire [CTRL_AXI_DATA_WIDTH-1:0] logo_hlocation_end;
	wire [CTRL_AXI_DATA_WIDTH-1:0] logo_vlocation_begin;
	wire [CTRL_AXI_DATA_WIDTH-1:0] logo_vlocation_end;

	/*****************************************************************************
	* control ports module
	*****************************************************************************/
	video_down_scaler_v1_5_ctrl #
	(
		.CTRL_AXI_DATA_WIDTH(CTRL_AXI_DATA_WIDTH),
		.CTRL_AXI_ADDR_WIDTH(CTRL_AXI_ADDR_WIDTH)
	) video_down_scaler_v1_5_ctrl_inst
	(
		.run(run),
		.reset(reset),
		.done(done),
		.logo_valid(logo_valid),
		.src_width(src_width),
		.src_heigth(src_heigth),
		.dst_width(dst_width),
		.dst_heigth(dst_heigth),
		.hlocation_in(hlocation_in),
		.vlocation_in(vlocation_in),
		.hlocation_out(hlocation_out),
		.vlocation_out(vlocation_out),
		.logo_hlocation_begin(logo_hlocation_begin),
		.logo_hlocation_end(logo_hlocation_end),
		.logo_vlocation_begin(logo_vlocation_begin),
		.logo_vlocation_end(logo_vlocation_end),
		.S_AXI_ACLK(axi_aclk),
		.S_AXI_ARESETN(axi_aresetn),
		.S_AXI_AWADDR(ctrl_axi_awaddr),
		.S_AXI_AWVALID(ctrl_axi_awvalid),
		.S_AXI_AWREADY(ctrl_axi_awready),
		.S_AXI_WDATA(ctrl_axi_wdata),
		.S_AXI_WVALID(ctrl_axi_wvalid),
		.S_AXI_WREADY(ctrl_axi_wready),
		.S_AXI_BRESP(ctrl_axi_bresp),
		.S_AXI_BVALID(ctrl_axi_bvalid),
 		.S_AXI_BREADY(ctrl_axi_bready),
		.S_AXI_ARADDR(ctrl_axi_araddr),
		.S_AXI_ARVALID(ctrl_axi_arvalid),
		.S_AXI_ARREADY(ctrl_axi_arready),
		.S_AXI_RDATA(ctrl_axi_rdata),
		.S_AXI_RVALID(ctrl_axi_rvalid),
		.S_AXI_RREADY(ctrl_axi_rready)
	);

	/*****************************************************************************
	* data ports module
	*****************************************************************************/
	video_down_scaler_v1_5_data #
	(
		.CTRL_AXI_DATA_WIDTH(CTRL_AXI_DATA_WIDTH),
		.MAX_INPUT_WIDTH(MAX_INPUT_WIDTH),
		.MAX_OUTPUT_WIDTH(MAX_OUTPUT_WIDTH),
		.SCALE_TYPE(SCALE_TYPE),
		.OPERATOIN_DATA_WIDTH(DATA_WIDTH),
		.INPUT_DATA_WIDTH(DATA_WIDTH),
		.OUTPUT_DATA_WIDTH(DATA_WIDTH),
		.IMAGE_READ_REGISTER_DEPTH(IMAGE_READ_REGISTER_DEPTH),
		.LOGO_READ_REGISTER_DEPTH(LOGO_READ_REGISTER_DEPTH),
		.INVISIBLE_PIXEL(INVISIBLE_PIXEL),
		.WRITE_REGISTER_DEPTH(WRITE_REGISTER_DEPTH)
	) video_down_scaler_v1_5_data_inst
	(
		.run(run),
		.reset(reset),
		.done(done),
		.logo_valid(logo_valid),
		.src_width(src_width),
		.src_heigth(src_heigth),
		.dst_width(dst_width),
		.dst_heigth(dst_heigth),
		.hlocation_in(hlocation_in),
		.vlocation_in(vlocation_in),
		.hlocation_out(hlocation_out),
		.vlocation_out(vlocation_out),
		.logo_hlocation_begin(logo_hlocation_begin),
		.logo_hlocation_end(logo_hlocation_end),
		.logo_vlocation_begin(logo_vlocation_begin),
		.logo_vlocation_end(logo_vlocation_end),
		.M_AXI_ACLK(axi_aclk),
		.M_AXI_ARESETN(axi_aresetn),
		.S_AXIS_TDATA_INPUT(s_axis_tdata_input),
		.S_AXIS_TVALID_INPUT(s_axis_tvalid_input),
		.S_AXIS_TREADY_INPUT(s_axis_tready_input),
		.S_AXIS_TLAST_INPUT(s_axis_tlast_input),
		.S_AXIS_TDATA_LOGO(s_axis_tdata_logo),
		.S_AXIS_TVALID_LOGO(s_axis_tvalid_logo),
		.S_AXIS_TREADY_LOGO(s_axis_tready_logo),
		.S_AXIS_TLAST_LOGO(s_axis_tlast_logo),
		.M_AXIS_TDATA_OUTPUT(m_axis_tdata_output),
		.M_AXIS_TVALID_OUTPUT(m_axis_tvalid_output),
		.M_AXIS_TREADY_OUTPUT(m_axis_tready_output),
		.M_AXIS_TLAST_OUTPUT(m_axis_tlast_output)
	);

endmodule
