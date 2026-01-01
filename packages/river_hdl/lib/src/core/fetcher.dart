import 'package:rohd/rohd.dart';
import 'package:rohd_hcl/rohd_hcl.dart';

class FetchUnit extends Module {
  final bool hasCompressed;

  Logic get done => output('done');
  Logic get valid => output('valid');
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
    addOutput('valid');
    if (hasCompressed) addOutput('compressed');
    addOutput('result', width: 32);

    final halfwordMask = Const(0xFFFF, width: 32);

    final fetchAlignBits = switch (memRead.data.width) {
      32 => 2,
      64 => 3,
      _ => throw 'Unsupported XLEN=${pc.width}',
    };

    final alignment = Const(~((1 << fetchAlignBits) - 1), width: pc.width);

    final enableRead = Logic(name: 'enableRead');
    memRead.en <= enableRead;

    final halfSelect = Logic(name: 'halfSelect');
    final readData = Logic(name: 'readData', width: memRead.data.width);

    final complete = Logic(name: 'complete');
    final pcLatch = Logic(name: 'pcLatch', width: pc.width);

    final instr32 = Logic(name: 'instr32', width: 32);

    instr32 <=
        ((memRead.data.width == 32)
            ? memRead.data.slice(31, 0)
            : mux(
                halfSelect,
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
          pcLatch < 0,
          enableRead < 0,
          memRead.addr < 0,
          done < 0,
          valid < 0,
          result < 0,
          complete < 0,
          readData < 0,
          if (memRead.data.width == 64) halfSelect < 0,
          if (hasCompressed) compressed < 0,
        ],
        orElse: [
          done < 0,
          valid < 0,
          result < 0,
          If.block([
            Iff(enable & ~complete & ~enableRead, [
              pcLatch < pc,
              if (memRead.data.width == 64) halfSelect < pc[2],
              enableRead < 1,
              memRead.addr < (pc & alignment),
            ]),
            Iff(enable & ~complete & ~memRead.done, [
              enableRead < 1,
              memRead.addr < (pcLatch & alignment),
            ]),
            Iff(enable & ~complete & memRead.done, [
              enableRead < 1,
              memRead.addr < (pcLatch & alignment),
              If(
                memRead.valid,
                then: [complete < 1, readData < memRead.data, result < 0],
                orElse: [done < 1, valid < 0, enableRead < 0],
              ),
            ]),
            Iff(enable & complete, [
              done < 1,
              valid < 1,
              enableRead < 1,
              memRead.addr < (pcLatch & alignment),
              if (hasCompressed) ...[
                compressed < isCompressed,
                result < mux(isCompressed, (instr32 & halfwordMask), instr32),
              ] else ...[
                result < instr32,
              ],
            ]),
            Iff(~enable, [
              complete < 0,
              pcLatch < pc,
              if (memRead.data.width == 64) halfSelect < 0,
              if (hasCompressed) compressed < 0,
              enableRead < 0,
              memRead.addr < 0,
            ]),
          ]),
        ],
      ),
    ]);
  }
}
