import 'package:rohd/rohd.dart';
import 'package:rohd_hcl/rohd_hcl.dart';
import 'package:riscv/riscv.dart';
import 'package:river/river.dart';

import 'core/pipeline.dart';

class RiverCoreHDL extends Module {
  final RiverCore config;

  late final RegisterFile regs;
  late final RiverPipeline pipeline;

  RiverCoreHDL(
    this.config,
    Logic clk,
    Logic reset,
    Logic enable,
    DataPortInterface memFetchRead,
    DataPortInterface memExecRead,
    DataPortInterface memWrite, {
    super.name = 'river_core',
  }) {
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);
    enable = addInput('enable', enable);

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

    final pipelineEnable = Logic(name: 'pipelineEnable');
    final pc = Logic(name: 'pc', width: config.mxlen.size);
    final sp = Logic(name: 'sp', width: config.mxlen.size);
    final mode = Logic(name: 'mode', width: 3);

    final rs1Read = DataPortInterface(config.mxlen.size, 5);
    final rs2Read = DataPortInterface(config.mxlen.size, 5);
    final rdWrite = DataPortInterface(config.mxlen.size, 5);

    regs = RegisterFile(
      clk,
      reset,
      [rdWrite],
      [rs1Read, rs2Read],
      numEntries: 32,
    );

    pipeline = RiverPipeline(
      clk,
      reset,
      pipelineEnable,
      sp,
      pc,
      mode,
      // TODO: CSR's
      null,
      null,
      // TODO: have a cache backed memory interface
      memFetchRead,
      memExecRead,
      memWrite,
      rs1Read,
      rs2Read,
      rdWrite,
      microcode: config.microcode,
      mxlen: config.mxlen,
      hasSupervisor: config.hasSupervisor,
      hasCompressed: config.extensions.any((e) => e.name == 'RVC'),
    );

    Sequential(clk, [
      If(
        reset,
        then: [pipelineEnable < 0, pc < config.resetVector, sp < 0, mode < 0],
        orElse: [
          If(
            enable,
            then: [
              If(
                pipeline.done,
                then: [
                  pc < pipeline.nextPc,
                  sp < pipeline.nextSp,
                  mode < pipeline.nextMode,
                  pipelineEnable < 0,
                ],
                orElse: [pipelineEnable < 1],
              ),
            ],
            orElse: [pipelineEnable < 0],
          ),
          // TODO: trap handling circuitry
        ],
      ),
    ]);
  }
}
