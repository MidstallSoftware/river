import 'package:rohd/rohd.dart';
import 'package:rohd_hcl/rohd_hcl.dart';
import 'package:riscv/riscv.dart';
import 'package:river/river.dart';

import 'core/csr.dart';
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
    final interruptHold = Logic(name: 'interruptHold');

    final rs1Read = DataPortInterface(config.mxlen.size, 5);
    final rs2Read = DataPortInterface(config.mxlen.size, 5);
    final rdWrite = DataPortInterface(config.mxlen.size, 5);

    final csrRead = DataPortInterface(config.mxlen.size, 12);
    final csrWrite = DataPortInterface(config.mxlen.size, 12);

    final csrs = config.type.hasCsrs
        ? RiscVCsrFile(
            clk,
            reset,
            mode,
            mxlen: config.mxlen,
            misa:
                config.extensions
                    .map((ext) => ext.mask)
                    .fold(0, (t, i) => t | i) |
                config.mxlen.misa |
                ((config.hasSupervisor ? 1 : 0) << 18) |
                ((config.hasUser ? 1 : 0) << 20),
            mvendorid: config.vendorId,
            marchid: config.archId,
            mimpid: config.impId,
            mhartid: config.hartId,
            hasSupervisor: config.hasSupervisor,
            hasUser: config.hasUser,
            csrRead: csrRead,
            csrWrite: csrWrite,
          )
        : null;

    regs = RegisterFile(
      clk,
      reset,
      [rdWrite],
      [rs1Read, rs2Read],
      numEntries: 32,
      name: 'riscv_regfile',
    );

    pipeline = RiverPipeline(
      clk,
      reset,
      pipelineEnable,
      sp,
      pc,
      mode,
      config.type.hasCsrs ? csrRead : null,
      config.type.hasCsrs ? csrWrite : null,
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
      hasUser: config.hasUser,
      hasCompressed: config.extensions.any((e) => e.name == 'RVC'),
      mideleg: csrs?.mideleg,
      medeleg: csrs?.medeleg,
      mtvec: csrs?.mtvec,
      stvec: csrs?.stvec,
    );

    Sequential(clk, [
      If(
        reset,
        then: [
          pipelineEnable < 0,
          pc < config.resetVector,
          sp < 0,
          mode < 0,
          interruptHold < 0,
        ],
        orElse: [
          If(
            enable & ~interruptHold,
            then: [
              If(
                pipeline.done,
                then: [
                  pc < pipeline.nextPc,
                  sp < pipeline.nextSp,
                  mode < pipeline.nextMode,
                  interruptHold < pipeline.interruptHold,
                  pipelineEnable < 0,
                ],
                orElse: [pipelineEnable < 1],
              ),
            ],
            orElse: [
              pipelineEnable < 0,
              // TODO: if interrupt hold & interrupt is fired, re-enable pipeline.
            ],
          ),
          // TODO: trap handling circuitry
        ],
      ),
    ]);
  }
}
