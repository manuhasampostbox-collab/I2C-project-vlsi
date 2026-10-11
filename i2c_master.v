// -----------------------------------------------------------------------------
// i2c_master.v
// Simple I2C master: single-byte write transaction
// (START -> 7-bit addr + W -> ACK -> 8-bit data -> ACK -> STOP).
// Open-drain style SDA/SCL with tri-state control, as on a real I2C bus.
// -----------------------------------------------------------------------------
module i2c_master #(
    parameter CLK_DIV = 20   // clk cycles per quarter SCL period
) (
    input  wire       clk,
    input  wire       rst_n,

    input  wire        start_txn,   // pulse high for 1 clk to begin
    input  wire [6:0]  slave_addr,
    input  wire [7:0]  write_data,

    output reg         busy,
    output reg         done,
    output reg         ack_error,   // 1 if a slave failed to ACK

    inout  wire        sda,
    output wire        scl
);

    localparam IDLE       = 4'd0,
               START      = 4'd1,
               ADDR       = 4'd2,
               ADDR_ACK   = 4'd3,
               WDATA      = 4'd4,
               WDATA_ACK  = 4'd5,
               STOP       = 4'd6,
               CLEAN      = 4'd7;

    reg [3:0]  state;
    reg [15:0] clk_count;
    reg [1:0]  quarter;           // 0..3 within one SCL period
    reg [2:0]  bit_index;
    reg [7:0]  shift_reg;
    reg        sda_out;
    reg        sda_oe;            // 1 = drive sda_out, 0 = release (input/high-Z)
    reg        scl_en;            // 1 once SCL is toggling

    assign sda = sda_oe ? sda_out : 1'bz;
    assign scl = (!rst_n) ? 1'b1 : (scl_en ? (quarter[1] ? 1'b1 : 1'b0) : 1'b1);
    // quarter 0,1 -> SCL low ; quarter 2,3 -> SCL high  (standard 4-phase I2C timing)

    wire sda_in = sda;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            clk_count <= 16'd0;
            quarter   <= 2'd0;
            bit_index <= 3'd0;
            shift_reg <= 8'd0;
            sda_out   <= 1'b1;
            sda_oe    <= 1'b1;
            scl_en    <= 1'b0;
            busy      <= 1'b0;
            done      <= 1'b0;
            ack_error <= 1'b0;
        end else begin
            done <= 1'b0;

            case (state)
                IDLE: begin
                    sda_out <= 1'b1;
                    sda_oe  <= 1'b1;
                    scl_en  <= 1'b0;
                    clk_count <= 16'd0;
                    quarter   <= 2'd0;
                    if (start_txn) begin
                        busy      <= 1'b1;
                        ack_error <= 1'b0;
                        shift_reg <= {slave_addr, 1'b0};  // address + write bit
                        state     <= START;
                    end else begin
                        busy <= 1'b0;
                    end
                end

                START: begin
                    // SDA falls while SCL is high = START condition
                    scl_en  <= 1'b0;   // keep SCL high during this phase
                    sda_oe  <= 1'b1;
                    if (clk_count < CLK_DIV) begin
                        sda_out   <= 1'b1;
                        clk_count <= clk_count + 1'b1;
                    end else if (clk_count < 2*CLK_DIV) begin
                        sda_out   <= 1'b0;   // START condition
                        clk_count <= clk_count + 1'b1;
                    end else begin
                        clk_count <= 16'd0;
                        bit_index <= 3'd7;
                        scl_en    <= 1'b1;
                        state     <= ADDR;
                    end
                end

                ADDR: begin
                    sda_oe  <= 1'b1;
                    sda_out <= shift_reg[bit_index];
                    if (clk_count < 4*CLK_DIV - 1) begin
                        clk_count <= clk_count + 1'b1;
                        quarter   <= clk_count / CLK_DIV;
                    end else begin
                        clk_count <= 16'd0;
                        quarter   <= 2'd0;
                        if (bit_index == 0) begin
                            state <= ADDR_ACK;
                        end else begin
                            bit_index <= bit_index - 1'b1;
                        end
                    end
                end

                ADDR_ACK: begin
                    sda_oe <= 1'b0;   // release SDA so slave can ACK (pull low)
                    if (clk_count < 4*CLK_DIV - 1) begin
                        clk_count <= clk_count + 1'b1;
                        quarter   <= clk_count / CLK_DIV;
                        if (quarter == 2'd2) begin  // sample mid-high phase
                            if (sda_in === 1'b1)
                                ack_error <= 1'b1;
                        end
                    end else begin
                        clk_count <= 16'd0;
                        quarter   <= 2'd0;
                        bit_index <= 3'd7;
                        shift_reg <= write_data;
                        state     <= WDATA;
                    end
                end

                WDATA: begin
                    sda_oe  <= 1'b1;
                    sda_out <= shift_reg[bit_index];
                    if (clk_count < 4*CLK_DIV - 1) begin
                        clk_count <= clk_count + 1'b1;
                        quarter   <= clk_count / CLK_DIV;
                    end else begin
                        clk_count <= 16'd0;
                        quarter   <= 2'd0;
                        if (bit_index == 0) begin
                            state <= WDATA_ACK;
                        end else begin
                            bit_index <= bit_index - 1'b1;
                        end
                    end
                end

                WDATA_ACK: begin
                    sda_oe <= 1'b0;
                    if (clk_count < 4*CLK_DIV - 1) begin
                        clk_count <= clk_count + 1'b1;
                        quarter   <= clk_count / CLK_DIV;
                        if (quarter == 2'd2) begin
                            if (sda_in === 1'b1)
                                ack_error <= 1'b1;
                        end
                    end else begin
                        clk_count <= 16'd0;
                        quarter   <= 2'd0;
                        state     <= STOP;
                    end
                end

                STOP: begin
                    sda_oe <= 1'b1;
                    scl_en <= 1'b0;   // force SCL high for STOP condition
                    if (clk_count < CLK_DIV) begin
                        sda_out   <= 1'b0;
                        clk_count <= clk_count + 1'b1;
                    end else if (clk_count < 2*CLK_DIV) begin
                        sda_out   <= 1'b1;   // SDA rises while SCL high = STOP
                        clk_count <= clk_count + 1'b1;
                    end else begin
                        clk_count <= 16'd0;
                        done      <= 1'b1;
                        state     <= CLEAN;
                    end
                end

                CLEAN: begin
                    busy  <= 1'b0;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
