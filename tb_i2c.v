// -----------------------------------------------------------------------------
// tb_i2c.v
// Drives i2c_master against a behavioral i2c_slave_model, runs several
// write transactions, and checks that the slave received the correct
// address and data each time. Reports PASS/FAIL per transaction and a
// final summary.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_i2c;

    localparam CLK_DIV   = 5;
    localparam NUM_TESTS = 5;

    reg        clk;
    reg        rst_n;
    reg        start_txn;
    reg [6:0]  slave_addr;
    reg [7:0]  write_data;
    wire       busy;
    wire       done;
    wire       ack_error;

    wire       sda;
    wire       scl;

    wire [6:0] s_last_addr;
    wire [7:0] s_last_data;
    wire       s_byte_received;

    integer    pass_count;
    integer    fail_count;
    integer    i;

    reg [6:0] addr_vec [0:NUM_TESTS-1];
    reg [7:0] data_vec [0:NUM_TESTS-1];

    always #5 clk = ~clk;

    i2c_master #(.CLK_DIV(CLK_DIV)) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .start_txn  (start_txn),
        .slave_addr (slave_addr),
        .write_data (write_data),
        .busy       (busy),
        .done       (done),
        .ack_error  (ack_error),
        .sda        (sda),
        .scl        (scl)
    );

    i2c_slave_model #(.MY_ADDR(7'h50)) slave (
        .sda           (sda),
        .scl           (scl),
        .last_addr     (s_last_addr),
        .last_data     (s_last_data),
        .byte_received (s_byte_received)
    );

    pullup(sda);   // model the external pull-up resistor on the open-drain bus

    task do_write(input [6:0] a, input [7:0] d);
        begin
            @(posedge clk);
            slave_addr <= a;
            write_data <= d;
            start_txn  <= 1'b1;
            @(posedge clk);
            start_txn  <= 1'b0;
            @(posedge done);
        end
    endtask

    initial begin
        clk        = 1'b0;
        rst_n      = 1'b0;
        start_txn  = 1'b0;
        slave_addr = 7'd0;
        write_data = 8'd0;
        pass_count = 0;
        fail_count = 0;

        addr_vec[0] = 7'h50; data_vec[0] = 8'h00;
        addr_vec[1] = 7'h50; data_vec[1] = 8'hFF;
        addr_vec[2] = 7'h50; data_vec[2] = 8'hA5;
        addr_vec[3] = 7'h50; data_vec[3] = 8'h3C;
        addr_vec[4] = 7'h50; data_vec[4] = 8'h99;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);

        for (i = 0; i < NUM_TESTS; i = i + 1) begin
            do_write(addr_vec[i], data_vec[i]);

            if (ack_error) begin
                $display("[FAIL] test %0d: ack_error asserted (slave did not ACK)", i);
                fail_count = fail_count + 1;
            end else if (s_last_addr === addr_vec[i] && s_last_data === data_vec[i]) begin
                $display("[PASS] test %0d: addr 0x%02h data 0x%02h received correctly", i, addr_vec[i], data_vec[i]);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] test %0d: expected addr 0x%02h data 0x%02h, got addr 0x%02h data 0x%02h",
                          i, addr_vec[i], data_vec[i], s_last_addr, s_last_data);
                fail_count = fail_count + 1;
            end

            repeat (10) @(posedge clk);
        end

        $display("--------------------------------------------------");
        $display("I2C master write test summary: %0d passed, %0d failed (of %0d)", pass_count, fail_count, NUM_TESTS);
        $display("--------------------------------------------------");

        if (fail_count == 0)
            $display("RESULT: ALL TESTS PASSED");
        else
            $display("RESULT: %0d TEST(S) FAILED", fail_count);

        $finish;
    end

    initial begin
        #200000;
        $display("ERROR: testbench timeout -- simulation did not finish");
        $finish;
    end

endmodule
