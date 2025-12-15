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
    super.name = 'river_fetch_unit',
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
        inputTags: {DataPortGroup.data, DataPortGroup.integrity},
        uniquify: (og) => 'memRead_$og',
      );

    addOutput('done');
    if (hasCompressed) addOutput('compressed');
    addOutput('result', width: 32);

    final halfwordMask = Const(0xFFFF, width: 32);

    final fetchAlignBits = switch (pc.width) {
      32 => 2,
      64 => 3,
      _ => throw 'Unsupported XLEN=${pc.width}',
    };

    final alignment = Const(~((1 << fetchAlignBits) - 1), width: pc.width);

    final pcFetch = Logic(name: 'pcFetch', width: pc.width);
    pcFetch <= pc & alignment;

    final instr32 = Logic(name: 'instr32', width: 32);

    instr32 <=
        ((pc.width == 32)
            ? memRead.data.slice(31, 0)
            : mux(
                pc[2],
                memRead.data.slice(63, 32),
                memRead.data.slice(31, 0),
              ));

    final isCompressed = Logic(name: 'isCompressed');
    isCompressed <=
        (((instr32 & halfwordMask) & Const(0x3, width: 32)).neq(0x3));

    Sequential(clk, [
      If(
        reset,
        then: [
          memRead.en < 0,
          memRead.addr < 0,
          done < 0,
          result < 0,
          if (hasCompressed) compressed < 0,
        ],
        orElse: [
          If(
            enable,
            then: [
              memRead.en < 1,
              memRead.addr < pcFetch,

              If(
                memRead.done & memRead.valid,
                then: [
                  done < 1,
                  if (hasCompressed) ...[
                    compressed < isCompressed,
                    result <
                        mux(
                          isCompressed,
                          (instr32 & halfwordMask),
                          instr32,
                        ).slice(31, 0),
                  ] else ...[
                    result < instr32,
                  ],
                ],
                orElse: [
                  done < 0,
                  result < 0,
                  if (hasCompressed) compressed < 0,
                ],
              ),
            ],
            orElse: [
              memRead.en < 0,
              memRead.addr < 0,
              done < 0,
              result < 0,
              if (hasCompressed) compressed < 0,
            ],
          ),
        ],
      ),
    ]);
  }
}
