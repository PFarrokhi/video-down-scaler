
`timescale 1ns / 1ns

module FIFO #
(
  parameter integer RESET_TRIGGER = 0,
  parameter integer DATA_WIDTH = 32,
  parameter integer DATA_DEPTH = 7
)
(
  input wire CLK,
  input wire RESET,
  input wire ENABLE,
  input wire READ,
  input wire WRITE,
  input wire [DATA_WIDTH - 1 : 0] DATA_IN,
  output wire [DATA_WIDTH - 1 : 0] DATA_OUT,
  output wire EMPTY,
  output wire FULL
);

  localparam ADDRESS_WIDTH = $clog2(DATA_DEPTH);

  reg empty;
  reg full;
  reg [DATA_WIDTH - 1 : 0] memory [DATA_DEPTH - 1 : 0];
  reg [ADDRESS_WIDTH - 1 : 0] read_pointer;
  reg [ADDRESS_WIDTH - 1 : 0] write_pointer;

  assign DATA_OUT = memory[read_pointer];
  assign EMPTY = empty;
  assign FULL = full;

  always @(posedge CLK)
  begin
    if(RESET == RESET_TRIGGER)
    begin
      empty <= 1;
      full <= 0;
      read_pointer <= 0;
      write_pointer <= 0;
    end
    else if(ENABLE)
    begin
      // empty functions
      if((EMPTY && (!WRITE)) || (((read_pointer == (write_pointer - 1)) ||
        ((read_pointer == (DATA_DEPTH - 1)) && (write_pointer == 0))) && READ &&
        (!WRITE)))
      begin
        empty <= 1;
      end
      else
      begin
        empty <= 0;
      end
      // full functions
      if((FULL && (!READ)) || (((write_pointer == (read_pointer - 1)) ||
        ((write_pointer == (DATA_DEPTH - 1)) && (read_pointer == 0))) && WRITE &&
        (!READ)))
      begin
        full <= 1;
      end
      else
      begin
        full <= 0;
      end
      // read_pointer functions
      if((!EMPTY) && READ)
      begin
        if(read_pointer == (DATA_DEPTH -1))
        begin
          read_pointer <= 0;
        end
        else
        begin
          read_pointer <= read_pointer + 1;
        end
      end
      // write_pointer functions
      if((!FULL) && WRITE)
      begin
        memory[write_pointer] <= DATA_IN;
        if(write_pointer == (DATA_DEPTH -1))
        begin
          write_pointer <= 0;
        end
        else
        begin
          write_pointer <= write_pointer + 1;
        end
      end
    end
  end

endmodule
