`timescale 1ns/1ps

module TOP_tb;

    reg Clk;
    reg Rst_n;
    reg [7:0] TxData;
    reg TxEn;
    wire Tx;
    wire [7:0] RxData;
    reg Rx;

    // Instantiate TOP
    TOP uut (
        .Clk(Clk),
        .Rst_n(Rst_n),
        .Rx(Rx),
        .Tx(Tx),
        .RxData(RxData),
        .TxData(TxData),
        .TxEn(TxEn)
    );

    // Clock generation: 50MHz
    initial Clk = 0;
    always #10 Clk = ~Clk; // 20ns period

    // Loopback TX -> RX
    always @(posedge Clk) begin
        Rx <= Tx;
    end

    // Test procedure
    initial begin
        Rst_n = 0;
        TxData = 8'h00;
        TxEn = 0;
        #100;
        Rst_n = 1;
        #100;

        // Send bytes one by one
      send_byte(8'h25);
      send_byte(8'h3A);
      send_byte(8'h5F);
      send_byte(8'h71);

        #5000000; // wait some time for last byte
        $finish;
    end

    // Task to send a byte respecting UART timing
    task send_byte(input [7:0] data);
        integer wait_cycles;
        begin
            // Drive TX signals
            @(posedge Clk);
            TxData <= data;
            TxEn <= 1'b1;
            @(posedge Clk);
            TxEn <= 1'b0;

            // Wait until TX is done
            wait(uut.I_RS232TX.TxDone == 1);

            // Wait until RX is done
            wait(uut.I_RS232RX.RxDone == 1);

            // Add small extra delay to ensure FSMs reset before next byte
            wait_cycles = 1000; // can adjust based on baud rate
            repeat(wait_cycles) @(posedge Clk);

            // Print result
            $display("TX: %h, RX: %h at time %0t", data, RxData, $time);
        end
    endtask

endmodule
