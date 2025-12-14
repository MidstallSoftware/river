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

    final halfwordMask = Const(0xFFFF, width: pc.width);

    memRead.en <= enable;
    memRead.addr <= pc;

    final instrReg = FlipFlop(
      clk,
      memRead.data,
      en: enable,
      reset: reset,
      resetValue: 0,
      name: 'instrReg',
    );

    done <= enable & memRead.done & memRead.valid;

    if (hasCompressed) {
      compressed <=
          (((instrReg.q & halfwordMask) & Const(0x3, width: pc.width)).neq(
            0x3,
          ));
      result <=
          mux(compressed, (instrReg.q & halfwordMask), instrReg.q).slice(31, 0);
    } else {
      result <= instrReg.q.slice(31, 0);
    }
  }
}
