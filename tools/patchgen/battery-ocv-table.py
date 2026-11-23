#!/usr/bin/env python3
# Convert a stock Qualcomm QG battery profile (qcom,pc-temp-v1-lut) into a
# mainline simple-battery ocv-capacity-table for one temperature column.
# Usage: battery-ocv-table.py <decompiled stock dtbo .dts> <profile node name> [temp C]
import re, sys
dts, node, temp = sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 25
s = open(dts).read()
blk = s[s.index(node + " {"):]
lut = blk[blk.index("qcom,pc-temp-v1-lut {"):]
lut = lut[:lut.index("};")]
nums = lambda key: [int(x, 16) for x in re.search(key + r" = <([^>]*)>", lut).group(1).split()]
cols, rows, data = nums("qcom,lut-col-legend"), nums("qcom,lut-row-legend"), nums("qcom,lut-data")
assert len(data) == len(cols) * len(rows)
c = cols.index(temp)
pairs = [(data[r * len(cols) + c] * 100, rows[r] // 100) for r in range(len(rows))]  # 0.1 mV -> uV, 0.01 % -> %
assert all(p % 1 == 0 for _, p in pairs)
print(f"/* {node}: qcom,pc-temp-v1-lut, {temp} degC column */")
print("ocv-capacity-table-0 = " + ",\n\t\t\t\t       ".join(f"<{uv} {pc}>" for uv, pc in pairs) + ";")
