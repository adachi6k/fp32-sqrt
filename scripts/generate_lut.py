import math

def generate_lut():
    """LUTを生成する関数。1/√xの16ビット近似値を計算"""
    lut = []
    for i in range(256):
        # インデックスiに対応するxを計算（1.0 ≤ x < 2.0）
        x = 1.0 + i / 256.0
        # 1/√xを計算
        inv_sqrt = 1.0 / math.sqrt(x)
        # 16ビット固定小数点に変換（小数部15ビット）
        inv_sqrt_fixed = int(inv_sqrt * (1 << 15))
        # 16ビットに丸める（オーバーフロー対策）
        if inv_sqrt_fixed > 0xFFFF:
            inv_sqrt_fixed = 0xFFFF
        lut.append(inv_sqrt_fixed)
    return lut

def print_lut_verilog(lut):
    """LUTをSystemVerilogのcase文形式で出力"""
    print("function logic [15:0] lut_inv_sqrt(input logic [7:0] index);")
    print("    case (index)")
    for i, val in enumerate(lut):
        print(f"        8'h{i:02X}: lut_inv_sqrt = 16'h{val:04X};")
    print("        default: lut_inv_sqrt = 16'h0000;")
    print("    endcase")
    print("endfunction")

if __name__ == "__main__":
    lut = generate_lut()
    print_lut_verilog(lut)
