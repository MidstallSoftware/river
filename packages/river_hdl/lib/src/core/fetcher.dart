import 'package:rohd/rohd.dart';
import 'package:rohd_hcl/rohd_hcl.dart';

class FetchUnit extends Module {
  final bool hasCompressed;

  Logic get done => output('done');
  Logic get compressed => output('compressed');
  Logic get result => output('result');

  FetchUnit(
    Logic clk,
    Logic reset,
    Logic enable,
    Logic pc,
    DataPortInterface memRead, {
    this.hasCompressed = false,
  }) {
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);
    enable = addInput('enable', enable);
    pc = addInput('pc', pc, width: pc.width);

    memRead = memRead.clone()
      ..connectIO(
        this,
        memRead,
        outputTags: {DataPortGroup.control},
        inputTags: {DataPortGroup.data},
        uniquify: (og) => 'memRead_$og',
      );

    addOutput('done');
    if (hasCompressed) addOutput('compressed');
    addOutput('result', width: 32);

    Logic temp = Logic(name: 'temp', width: 32);

    final halfwordMask = Const(0xFFFF, width: 32);

    Sequential(clk, [
      If(
        reset,
        then: [
          if (hasCompressed) ...[temp < 0, compressed < 0],
          memRead.en < 0,
          memRead.addr < 0,
          result < 0,
          done < 0,
        ],
        orElse: [
          If(
            enable,
            then: [
              memRead.en < 1,
              memRead.addr < pc,

              if (hasCompressed) ...[
                temp < memRead.data,
                compressed <
                    ((temp & halfwordMask) & Const(0x3, width: 32)).neq(0x3),
                If(compressed, then: [result < temp & halfwordMask]),
              ] else
                result < memRead.data,

              done < 1,
            ],
            orElse: [
              memRead.en < 0,
              result < 0,
              if (hasCompressed) ...[temp < 0, compressed < 0],
            ],
          ),
        ],
      ),
    ]);
  }
}
