import 'package:rohd/rohd.dart';
import 'package:rohd_hcl/rohd_hcl.dart';
import 'package:riscv/riscv.dart';

import 'decoder.dart';
import 'exec.dart';
import 'fetcher.dart';

class RiverPipeline extends Module {
  final Microcode microcode;
  final Mxlen mxlen;

  Logic get done => output('done');
  Logic get valid => output('valid');
  Logic get nextSp => output('nextSp');
  Logic get nextPc => output('nextPc');
  Logic get nextMode => output('nextMode');
  Logic get trap => output('trap');
  Logic get trapCause => output('trapCause');
  Logic get trapTval => output('trapTval');
  Logic get fence => output('fence');
  Logic get interruptHold => output('interruptHold');

  late final FetchUnit fetcher;

  RiverPipeline(
    Logic clk,
    Logic reset,
    Logic enable,
    Logic currentSp,
    Logic currentPc,
    Logic currentMode,
    DataPortInterface? csrRead,
    DataPortInterface? csrWrite,
    DataPortInterface memFetchRead,
    DataPortInterface memExecRead,
    DataPortInterface memWrite,
    DataPortInterface rs1Read,
    DataPortInterface rs2Read,
    DataPortInterface rdWrite, {
    bool hasSupervisor = false,
    bool hasUser = false,
    bool hasCompressed = false,
    required this.microcode,
    required this.mxlen,
    Logic? mideleg,
    Logic? medeleg,
    Logic? mtvec,
    Logic? stvec,
    List<String> staticInstructions = const [],
    super.name = 'river_pipeline',
  }) {
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);
    enable = addInput('enable', enable);

    currentSp = addInput('currentSp', currentSp, width: mxlen.size);
    currentPc = addInput('currentPc', currentPc, width: mxlen.size);
    currentMode = addInput('currentMode', currentMode, width: 3);

    if (csrRead != null) {
      csrRead = csrRead!.clone()
        ..connectIO(
          this,
          csrRead!,
          outputTags: {DataPortGroup.control},
          inputTags: {DataPortGroup.data, DataPortGroup.integrity},
          uniquify: (og) => 'csrRead_$og',
        );
    }

    if (csrWrite != null) {
      csrWrite = csrWrite!.clone()
        ..connectIO(
          this,
          csrWrite!,
          outputTags: {DataPortGroup.control, DataPortGroup.data},
          inputTags: {DataPortGroup.integrity},
          uniquify: (og) => 'csrWrite_$og',
        );
    }

    memFetchRead = memFetchRead.clone()
      ..connectIO(
        this,
        memFetchRead,
        outputTags: {DataPortGroup.control},
        inputTags: {DataPortGroup.data, DataPortGroup.integrity},
        uniquify: (og) => 'memFetchRead_$og',
      );
    memExecRead = memExecRead.clone()
      ..connectIO(
        this,
        memExecRead,
        outputTags: {DataPortGroup.control},
        inputTags: {DataPortGroup.data, DataPortGroup.integrity},
        uniquify: (og) => 'memExecRead_$og',
      );
    memWrite = memWrite.clone()
      ..connectIO(
        this,
        memWrite,
        outputTags: {DataPortGroup.control, DataPortGroup.data},
        inputTags: {DataPortGroup.integrity},
        uniquify: (og) => 'memWrite_$og',
      );

    rs1Read = rs1Read.clone()
      ..connectIO(
        this,
        rs1Read,
        outputTags: {DataPortGroup.control},
        inputTags: {DataPortGroup.data, DataPortGroup.integrity},
        uniquify: (og) => 'rs1Read_$og',
      );
    rs2Read = rs2Read.clone()
      ..connectIO(
        this,
        rs2Read,
        outputTags: {DataPortGroup.control},
        inputTags: {DataPortGroup.data, DataPortGroup.integrity},
        uniquify: (og) => 'rs2Read_$og',
      );
    rdWrite = rdWrite.clone()
      ..connectIO(
        this,
        rdWrite,
        outputTags: {DataPortGroup.control, DataPortGroup.data},
        inputTags: {DataPortGroup.integrity},
        uniquify: (og) => 'rdWrite_$og',
      );

    if (mideleg != null)
      mideleg = addInput('mideleg', mideleg, width: mxlen.size);
    if (medeleg != null)
      medeleg = addInput('medeleg', medeleg, width: mxlen.size);
    if (mtvec != null) mtvec = addInput('mtvec', mtvec, width: mxlen.size);
    if (stvec != null) stvec = addInput('stvec', stvec, width: mxlen.size);

    addOutput('done');
    addOutput('valid');
    addOutput('nextSp', width: mxlen.size);
    addOutput('nextPc', width: mxlen.size);
    addOutput('nextMode', width: 3);
    addOutput('trap');
    addOutput('trapCause', width: 6);
    addOutput('trapTval', width: mxlen.size);
    addOutput('fence');
    addOutput('interruptHold');

    fetcher = FetchUnit(
      clk,
      reset,
      enable,
      currentPc,
      memFetchRead,
      hasCompressed: hasCompressed,
    );

    final decoder = InstructionDecoder(
      clk,
      reset,
      fetcher.done & fetcher.valid,
      fetcher.result,
      microcode: microcode,
      mxlen: mxlen,
      staticInstructions: staticInstructions,
    );

    final readyExecution =
        (fetcher.valid & fetcher.done & decoder.valid & decoder.done).named(
          'readyExecution',
        );

    final exec = ExecutionUnit(
      clk,
      reset,
      readyExecution,
      currentSp,
      currentPc,
      currentMode,
      decoder.index,
      decoder.instrTypeMap,
      decoder.fields,
      csrRead,
      csrWrite,
      memExecRead,
      memWrite,
      rs1Read,
      rs2Read,
      rdWrite,
      hasSupervisor: hasSupervisor,
      hasUser: hasUser,
      microcode: microcode,
      mxlen: mxlen,
      mideleg: mideleg,
      medeleg: medeleg,
      mtvec: mtvec,
      stvec: stvec,
      staticInstructions: staticInstructions,
    );

    Sequential(clk, [
      If(
        reset | ~exec.done,
        then: [
          done < 0,
          valid < 0,
          nextSp < 0,
          nextPc < 0,
          nextMode < 0,
          trap < 0,
          trapCause < 0,
          trapTval < 0,
          fence < 0,
        ],
        orElse: [
          done < fetcher.done & decoder.done & exec.done,
          valid < fetcher.valid & decoder.valid,
          nextSp < exec.nextSp,
          nextPc < exec.nextPc,
          nextMode < exec.nextMode,
          trap < exec.trap,
          trapCause < exec.trapCause,
          trapTval < exec.trapTval,
          fence < exec.fence,
          interruptHold < exec.interruptHold,
        ],
      ),
    ]);
  }
}
