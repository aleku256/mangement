from pathlib import Path

p = Path('/tmp/appsacco_native/lib/main.dart')
lines = p.read_text().splitlines()

for i, line in enumerate(lines):
    if "fontSize:10,color:Color(0xFF778078)))]]))])," in line:
        line = line.replace("fontSize:10,color:Color(0xFF778078)))]]))]),", "fontSize:10,color:Color(0xFF778078)))]))]),")
    if line.strip() == "]))))]));}":
        line = line.replace("]))))]));}", "])))]));}")
    if line.strip() == "]))));}":
        line = line.replace("]))));}", "])));}")
    if "class _ReceiptsPageState extends State<ReceiptsPage>" in line:
        line = line.replace("]))));}", "])));}")
    if "class _DividendsPageState extends State<DividendsPage>" in line:
        line = line.replace("]))));}", "])));}")
    if "class _WithdrawalsPageState extends State<WithdrawalsPage>" in line:
        line = line.replace("]))));}", "])));}")
    if "title:const Text('My Documents')" in line:
        line = line.replace("]))));}", "])));}")
    lines[i] = line

p.write_text('\n'.join(lines) + '\n')
print('Applied v2.1 syntax fixes')
