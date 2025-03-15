module fp32_sqrt (
    input  logic        clk,       // クロック
    input  logic        rst_n,     // リセット（負論理）
    input  logic [31:0] a,         // 入力: FP32
    input  logic [1:0]  rm,        // 丸めモード: 00=RNE, 01=RZ, 10=RP, 11=RM
    output logic [31:0] result     // 出力: FP32
);

    // パイプラインステージ間の構造体
    typedef struct packed {
        logic        sign;
        logic [7:0]  exp;
        logic [23:0] mant;  // 暗黙の1を含む
        logic        is_zero, is_inf, is_nan, is_neg;
        logic [1:0]  rm;
    } pipeline_t;

    pipeline_t stage1, stage2, stage3, stage4, stage5, stage6;
    logic [47:0] x0, x1, x2;  // Newton-Raphsonの近似値（48ビット精度）

    // ステージ1: 入力のデコード
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage1 <= '0;
        end else begin
            stage1.sign    <= a[31];
            stage1.exp     <= a[30:23];
            stage1.mant    <= (a[30:23] == 8'h00) ? {1'b0, a[22:0]} : {1'b1, a[22:0]};
            stage1.is_zero <= (a[30:23] == 8'h00) && (a[22:0] == 23'h0);
            stage1.is_inf  <= (a[30:23] == 8'hFF) && (a[22:0] == 23'h0);
            stage1.is_nan  <= (a[30:23] == 8'hFF) && (a[22:0] != 23'h0);
            stage1.is_neg  <= a[31] && !((a[30:23] == 8'h00) && (a[22:0] == 23'h0));
            stage1.rm      <= rm;
        end
    end

    // ステージ2: 前処理（非正規化数の正規化、指数調整）
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage2 <= '0;
        end else begin
            stage2 <= stage1;
            if (stage1.is_zero || stage1.is_inf || stage1.is_nan || stage1.is_neg) begin
                // 特殊値はそのまま通過
            end else begin
                logic [7:0]  exp_adj;
                logic [23:0] mant_norm;
                logic [4:0]  lz;
                if (stage1.exp == 8'h00) begin  // 非正規化数
                    lz = leading_zero_count(stage1.mant[22:0]);
                    mant_norm = stage1.mant << (lz + 1);
                    exp_adj = 8'd1 - lz;
                end else begin
                    mant_norm = stage1.mant;
                    exp_adj = stage1.exp - 8'd127;
                end
                stage2.exp  = (exp_adj >> 1) + 8'd127 - (exp_adj[0] ? 8'd1 : 8'd0);
                stage2.mant = exp_adj[0] ? (mant_norm << 1) : mant_norm;
            end
        end
    end

    // ステージ3: 初期近似値の取得（LUT使用）
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage3 <= '0;
            x0     <= '0;
        end else begin
            stage3 <= stage2;
            if (stage2.is_zero || stage2.is_inf || stage2.is_nan || stage2.is_neg) begin
                x0 <= '0;
            end else begin
                logic [15:0] inv_sqrt = lut_inv_sqrt(stage2.mant[23:16]);
                x0 <= (stage2.mant * inv_sqrt) >> 16;  // 48ビット精度
            end
        end
    end

    // ステージ4: Newton-Raphson反復1
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage4 <= '0;
            x1     <= '0;
        end else begin
            stage4 <= stage3;
            if (stage3.is_zero || stage3.is_inf || stage3.is_nan) begin
                x1 <= '0;
            end else begin
                logic [95:0] a_div_x0 = (stage3.mant << 48) / x0;
                x1 <= (x0 + a_div_x0[47:0]) >> 1;
            end
        end
    end

    // ステージ5: Newton-Raphson反復2
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage5 <= '0;
            x2     <= '0;
        end else begin
            stage5 <= stage4;
            if (stage4.is_zero || stage4.is_inf || stage4.is_nan) begin
                x2 <= '0;
            end else begin
                logic [95:0] a_div_x1 = (stage4.mant << 48) / x1;
                x2 <= (x1 + a_div_x1[47:0]) >> 1;
            end
        end
    end

    // ステージ6: 丸め処理と出力エンコード
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage6 <= '0;
            result <= '0;
        end else begin
            stage6 <= stage5;
            if (stage5.is_nan || stage5.is_neg) begin
                result <= {1'b0, 8'hFF, 23'h400000};  // NaN
            end else if (stage5.is_inf) begin
                result <= {1'b0, 8'hFF, 23'h0};       // +Inf
            end else if (stage5.is_zero) begin
                result <= {stage5.sign, 8'h00, 23'h0};  // ±0
            end else begin
                logic [47:0] mant_sqrt = x2;
                logic [22:0] mant_out;
                logic g = mant_sqrt[24];  // ガードビット
                logic r = mant_sqrt[23];  // ラウンドビット
                logic s = |mant_sqrt[22:0];  // スティッキービット
                mant_out = mant_sqrt[47:25];
                
                case (stage5.rm)
                    2'b00:  // RNE
                        if (g && (r || s || mant_out[0])) mant_out = mant_out + 1;
                    2'b01:  // RZ
                        mant_out = mant_out; // 切り捨て（何もしない）
                    2'b10:  // RP
                        if ((g || r || s) && !stage5.sign) mant_out = mant_out + 1;
                    2'b11:  // RM
                        if ((g || r || s) && stage5.sign) mant_out = mant_out + 1;
                endcase
                result <= {1'b0, stage5.exp, mant_out};
            end
        end
    end

    // 補助関数: Leading Zero Count
    function logic [4:0] leading_zero_count(input logic [22:0] mant);
        logic [4:0] count = 5'd23;
        for (int i = 22; i >= 0; i--) begin
            if (mant[i]) begin
                count = 5'd22 - i;
                break;
            end
        end
        leading_zero_count = count;
    endfunction

    // LUT: 仮数の上位8ビットに基づく1/√xの16ビット近似値
    function logic [15:0] lut_inv_sqrt(input logic [7:0] index);
        case (index)
            8'h00: lut_inv_sqrt = 16'hFFFF;  // 未使用（入力が0の場合を除外）
            8'h01: lut_inv_sqrt = 16'hB504;  // 1/√0.0078125 ≈ 11.3137
            8'h02: lut_inv_sqrt = 16'h7FFF;  // 1/√0.015625 ≈ 7.9999
            8'h03: lut_inv_sqrt = 16'h5A82;  // 1/√0.0234375 ≈ 5.6568
            8'h04: lut_inv_sqrt = 16'h4000;  // 1/√0.03125 ≈ 4.0000
            // 以下、256エントリまで事前計算が必要。ここでは一部のみ記載
            8'hFF: lut_inv_sqrt = 16'h0400;  // 1/√0.99609375 ≈ 1.0020
            default: lut_inv_sqrt = 16'h0400;  // 仮のデフォルト値
        endcase
    endfunction

endmodule
