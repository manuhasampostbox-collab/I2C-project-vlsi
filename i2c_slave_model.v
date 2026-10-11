// -----------------------------------------------------------------------------
// i2c_slave_model.v
// Minimal behavioral I2C slave used only for testbench verification.
// Explicit state machine (address -> ACK -> data -> ACK) driven on SCL edges:
// bits are sampled on SCL rising edges, ACK is driven on SCL falling edges,
// and the ACK clock pulse itself is never mistaken for a data bit.
// This is a test model, not synthesizable RTL.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module i2c_slave_model #(
    parameter [6:0] MY_ADDR = 7'h50
) (
    inout  wire sda,
    input  wire scl,
    output reg  [6:0] last_addr,
    output reg  [7:0] last_data,
    output reg        byte_received
);

    localparam S_WAIT     = 3'd0,
               S_ADDR      = 3'd1,
               S_ADDR_ACK  = 3'd2,
               S_DATA      = 3'd3,
               S_DATA_ACK  = 3'd4;

    reg [2:0] state;
    reg [7:0] shift;
    reg [2:0] bit_cnt;

    reg       sda_drive;
    reg       sda_val;
    assign sda = sda_drive ? sda_val : 1'bz;

    reg sda_prev, scl_prev;

    initial begin
        state         = S_WAIT;
        bit_cnt       = 3'd0;
        shift         = 8'd0;
        sda_drive     = 1'b0;
        sda_val       = 1'b0;
        byte_received = 1'b0;
        last_addr     = 7'd0;
        last_data     = 8'd0;
        sda_prev      = 1'b1;
        scl_prev      = 1'b1;
    end

    // START/STOP detection (SDA transitions while SCL is high)
    always @(sda or scl) begin
        if (scl === 1'b1 && scl_prev === 1'b1) begin
            if (sda_prev === 1'b1 && sda === 1'b0) begin       // START
                state   <= S_ADDR;
                bit_cnt <= 3'd0;
            end else if (sda_prev === 1'b0 && sda === 1'b1) begin  // STOP
                state <= S_WAIT;
            end
        end
        sda_prev <= sda;
        scl_prev <= scl;
    end

    // Sample bits on SCL rising edge
    always @(posedge scl) begin
        case (state)
            S_ADDR: begin
                shift   <= {shift[6:0], sda};
                if (bit_cnt == 3'd7) begin
                    state <= S_ADDR_ACK;
                end else begin
                    bit_cnt <= bit_cnt + 1'b1;
                end
            end
            S_ADDR_ACK: begin
                last_addr <= shift[7:1];
                bit_cnt   <= 3'd0;
                state     <= S_DATA;
            end
            S_DATA: begin
                shift   <= {shift[6:0], sda};
                if (bit_cnt == 3'd7) begin
                    state <= S_DATA_ACK;
                end else begin
                    bit_cnt <= bit_cnt + 1'b1;
                end
            end
            S_DATA_ACK: begin
                last_data     <= shift;
                byte_received <= 1'b1;
                bit_cnt       <= 3'd0;
                state         <= S_DATA;   // ready for another byte, or ended by STOP
            end
            default: ;
        endcase
    end

    // Drive ACK (SDA low) during the ACK bit's low phase; release otherwise
    always @(negedge scl) begin
        if (state == S_ADDR_ACK || state == S_DATA_ACK) begin
            sda_drive <= 1'b1;
            sda_val   <= 1'b0;
        end else begin
            sda_drive <= 1'b0;
        end
        if (state != S_DATA_ACK)
            byte_received <= 1'b0;
    end

endmodule
