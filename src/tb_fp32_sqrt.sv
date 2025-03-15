module tb_fp32_sqrt;

    logic clk, rst_n;
    logic [31:0] a;
    logic [1:0] rm;
    logic [31:0] result;

    fp32_sqrt uut (
        .clk(clk),
        .rst_n(rst_n),
        .a(a),
        .rm(rm),
        .result(result)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n = 0;
        #10 rst_n = 1;

        // テスト1: 0
        a = 32'h00000000;  // 0
        rm = 2'b00;  // RNE
        #60 $display("Test 1: a = %h, result = %h (expected 00000000)", a, result);
        assert(result == 32'h00000000) else $error("Test 1 failed");

        // テスト2: 1.0
        a = 32'h3F800000;  // 1.0
        rm = 2'b00;
        #60 $display("Test 2: a = %h, result = %h (expected 3F800000)", a, result);
        assert(result == 32'h3F800000) else $error("Test 2 failed");

        // テスト3: 4.0
        a = 32'h40800000;  // 4.0
        rm = 2'b00;
        #60 $display("Test 3: a = %h, result = %h (expected 40000000)", a, result);
        assert(result == 32'h40000000) else $error("Test 3 failed");

        // テスト4: 負の数
        a = 32'hBF800000;  // -1.0
        rm = 2'b00;
        #60 $display("Test 4: a = %h, result = %h (expected 7FC00000)", a, result);
        assert(result == 32'h7FC00000) else $error("Test 4 failed");

        // テスト5: 非正規化数
        a = 32'h00000001;  // 最小の非正規化数
        rm = 2'b00;
        #60 $display("Test 5: a = %h, result = %h", a, result);
        // 期待値は計算が必要（例: √(2^-149) ≈ 2^-74.5）

        // テスト6: 無限大
        a = 32'h7F800000;  // +Inf
        rm = 2'b00;
        #60 $display("Test 6: a = %h, result = %h (expected 7F800000)", a, result);
        assert(result == 32'h7F800000) else $error("Test 6 failed");

        // テスト7: NaN
        a = 32'h7FC00000;  // NaN
        rm = 2'b00;
        #60 $display("Test 7: a = %h, result = %h (expected 7FC00000)", a, result);
        assert(result == 32'h7FC00000) else $error("Test 7 failed");

        $finish;
    end

endmodule
