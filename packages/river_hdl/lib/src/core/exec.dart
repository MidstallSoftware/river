import 'package:rohd/rohd.dart';
import 'package:rohd_hcl/rohd_hcl.dart';
import 'package:riscv/riscv.dart';

class ExecutionUnit extends Module {
  final Microcode microcode;
  final Mxlen mxlen;

  Logic get done => output('done');
  Logic get nextSp => output('nextSp');
  Logic get nextPc => output('nextPc');
  Logic get trap => output('trap');
  Logic get trapCause => output('trapCause');
  Logic get trapTval => output('trapTval');

  ExecutionUnit(
    Logic clk,
    Logic reset,
    Logic currentSp,
    Logic currentPc,
    Logic instrIndex,
    Map<String, Logic> instrTypeMap,
    Map<String, Logic> fields,
    DataPortInterface csrRead,
    DataPortInterface csrWrite,
    DataPortInterface memRead,
    DataPortInterface memWrite,
    DataPortInterface rs1Read,
    DataPortInterface rs2Read,
    DataPortInterface rdWrite, {
    required this.microcode,
    required this.mxlen,
    super.name = 'river_execution_unit',
  }) {
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);

    currentSp = addInput('currentSp', currentSp, width: mxlen.size);

    currentPc = addInput('currentPc', currentPc, width: mxlen.size);

    instrIndex = addInput(
      'instrIndex',
      instrIndex,
      width: microcode.map.length.bitLength,
    );

    instrTypeMap = Map.fromEntries(
      instrTypeMap.entries.map(
        (entry) =>
            MapEntry(entry.key, addInput(entry.value.name!, entry.value)),
      ),
    );

    fields = Map.fromEntries(
      fields.entries.map(
        (entry) => MapEntry(
          entry.key,
          addInput(entry.value.name!, entry.value, width: entry.value.width),
        ),
      ),
    );

    csrRead = csrRead.clone()
      ..connectIO(
        this,
        csrRead,
        outputTags: {DataPortGroup.control},
        inputTags: {DataPortGroup.data},
        uniquify: (og) => 'csrRead_$og',
      );
    csrWrite = csrWrite.clone()
      ..connectIO(
        this,
        csrWrite,
        outputTags: {DataPortGroup.control, DataPortGroup.data},
        inputTags: {},
        uniquify: (og) => 'csrWrite_$og',
      );

    memRead = memRead.clone()
      ..connectIO(
        this,
        memRead,
        outputTags: {DataPortGroup.control},
        inputTags: {DataPortGroup.data},
        uniquify: (og) => 'memRead_$og',
      );
    memWrite = memWrite.clone()
      ..connectIO(
        this,
        memWrite,
        outputTags: {DataPortGroup.control, DataPortGroup.data},
        inputTags: {},
        uniquify: (og) => 'memWrite_$og',
      );

    rs1Read = rs1Read.clone()
      ..connectIO(
        this,
        rs1Read,
        outputTags: {DataPortGroup.control},
        inputTags: {DataPortGroup.data},
        uniquify: (og) => 'rs1Read_$og',
      );
    rs2Read = rs2Read.clone()
      ..connectIO(
        this,
        rs2Read,
        outputTags: {DataPortGroup.control},
        inputTags: {DataPortGroup.data},
        uniquify: (og) => 'rs2Read_$og',
      );
    rdWrite = rdWrite.clone()
      ..connectIO(
        this,
        rdWrite,
        outputTags: {DataPortGroup.control, DataPortGroup.data},
        inputTags: {},
        uniquify: (og) => 'rdWrite_$og',
      );

    addOutput('done');
    addOutput('nextSp', width: mxlen.size);
    addOutput('nextPc', width: mxlen.size);
    addOutput('trap', width: 1);
    addOutput('trapCause', width: 6);
    addOutput('trapTval', width: mxlen.size);

    final opIndices = microcode.opIndices;

    final mopMap = Map.fromEntries(
      microcode.indices.entries.map(
        (entry) => MapEntry(
          entry.key,
          microcode.map[entry.key]!.microcode
              .map((mop) => opIndices[mop.runtimeType.toString()]!)
              .toList(),
        ),
      ),
    );

    final maxLen = microcode.microOpSequences.values
        .map((s) => s.ops.length + 4)
        .fold(0, (a, b) => a > b ? a : b);

    final mopStep = Logic(name: 'mopStep', width: maxLen.bitLength);

    final alu = Logic(name: 'aluState', width: mxlen.size);
    final rs1 = Logic(name: 'rs1State', width: mxlen.size);
    final rs2 = Logic(name: 'rs2State', width: mxlen.size);
    final rd = Logic(name: 'rdState', width: mxlen.size);
    final imm = Logic(name: 'immState', width: mxlen.size);

    Logic readSource(MicroOpSource source) {
      switch (source) {
        case MicroOpSource.imm:
          return imm;
        case MicroOpSource.alu:
          return alu;
        case MicroOpSource.rs1:
          return rs1;
        case MicroOpSource.rs2:
          return rs2;
        case MicroOpSource.rd:
          return rd;
        case MicroOpSource.pc:
          return nextPc;
        default:
          throw 'Invalid source $source';
      }
    }

    Logic readField(MicroOpField field, {bool register = true}) {
      switch (field) {
        case MicroOpField.rd:
          return (register ? rd : fields['rd']!).zeroExtend(mxlen.size);
        case MicroOpField.rs1:
          return (register ? rs1 : fields['rs1']!).zeroExtend(mxlen.size);
        case MicroOpField.rs2:
          return (register ? rs2 : fields['rs2']!).zeroExtend(mxlen.size);
        case MicroOpField.imm:
          return register ? imm : fields['imm']!;
        case MicroOpField.pc:
          return nextPc;
        case MicroOpField.sp:
          return nextSp;
        default:
          throw 'Invalid field $field';
      }
    }

    Conditional writeField(MicroOpField field, Logic value) {
      switch (field) {
        case MicroOpField.rd:
          return rd < value;
        case MicroOpField.rs1:
          return rs1 < value;
        case MicroOpField.rs2:
          return rs2 < value;
        case MicroOpField.imm:
          return imm < value;
        case MicroOpField.sp:
          return nextSp < value;
        default:
          throw 'Invalid field $field';
      }
    }

    Conditional clearField(MicroOpField field) {
      switch (field) {
        case MicroOpField.rd:
          return rd < fields['rd']!.zeroExtend(mxlen.size);
        case MicroOpField.rs1:
          return rs1 < fields['rs1']!.zeroExtend(mxlen.size);
        case MicroOpField.rs2:
          return rs2 < fields['rs2']!.zeroExtend(mxlen.size);
        case MicroOpField.imm:
          return imm < fields['imm']!.zeroExtend(mxlen.size);
        default:
          throw 'Invalid field $field';
      }
    }

    Sequential(clk, [
      If(
        reset,
        then: [
          alu < 0,
          mopStep < 0,
          done < 0,
          rs1Read.en < 0,
          rs1Read.addr < 0,
          rs2Read.en < 0,
          rs2Read.addr < 0,
          rdWrite.en < 0,
          rdWrite.addr < 0,
        ],
        orElse: [
          Case(
            instrIndex,
            microcode.indices.entries.map((entry) {
              final op = microcode.map[entry.key]!;
              final steps = <CaseItem>[];

              for (final mop in op.indexedMicrocode.values) {
                final i = steps.length + 1;

                if (mop is ReadRegisterMicroOp) {
                  final port = mop.source == MicroOpSource.rs2
                      ? rs2Read
                      : rs1Read;
                  steps.add(
                    CaseItem(Const(i, width: maxLen.bitLength), [
                      port.addr <
                          (readField(mop.source) +
                                  Const(mop.offset, width: mxlen.size))
                              .slice(4, 0),
                      port.en < 1,
                      mopStep < mopStep + 1,
                    ]),
                  );

                  steps.add(
                    CaseItem(Const(i + 1, width: maxLen.bitLength), [
                      mopStep < mopStep + 1,
                    ]),
                  );

                  steps.add(
                    CaseItem(Const(i + 2, width: maxLen.bitLength), [
                      writeField(
                        mop.source,
                        port.data + Const(mop.valueOffset, width: mxlen.size),
                      ),
                      mopStep < mopStep + 1,
                    ]),
                  );
                } else if (mop is WriteRegisterMicroOp) {
                  final addr =
                      (readField(mop.field) +
                              Const(mop.offset, width: mxlen.size))
                          .slice(4, 0);

                  steps.add(
                    CaseItem(Const(i, width: maxLen.bitLength), [
                      rdWrite.addr < addr,
                      rdWrite.data <
                          (readSource(mop.source) +
                              Const(mop.valueOffset, width: mxlen.size)),
                      rdWrite.en < addr.gt(0),
                      mopStep < mopStep + 1,
                    ]),
                  );
                } else if (mop is AluMicroOp) {
                  steps.add(
                    CaseItem(Const(i, width: maxLen.bitLength), [
                      alu <
                          (switch (mop.funct) {
                            MicroOpAluFunct.add =>
                              readField(mop.a) + readField(mop.b),
                            MicroOpAluFunct.sub =>
                              readField(mop.a) - readField(mop.b),
                            MicroOpAluFunct.and =>
                              readField(mop.a) & readField(mop.b),
                            MicroOpAluFunct.or =>
                              readField(mop.a) | readField(mop.b),
                            MicroOpAluFunct.xor =>
                              readField(mop.a) ^ readField(mop.b),
                            MicroOpAluFunct.sll =>
                              readField(mop.a) << readField(mop.b),
                            MicroOpAluFunct.srl =>
                              readField(mop.a) >> readField(mop.b),
                            MicroOpAluFunct.sra =>
                              readField(mop.a) >> readField(mop.b),
                            MicroOpAluFunct.slt => readField(
                              mop.a,
                            ).lte(readField(mop.b)).zeroExtend(mxlen.size),
                            MicroOpAluFunct.sltu =>
                              (readField(mop.a) - readField(mop.b))[mxlen.size -
                                      1]
                                  .zeroExtend(mxlen.size),
                            _ => throw 'Invalid ALU function ${mop.funct}',
                          }).named(
                            'alu_${op.mnemonic}_${mop.funct.name}_${mop.a.name}_${mop.b.name}',
                          ),
                      mopStep < mopStep + 1,
                    ]),
                  );
                }
              }

              return CaseItem(Const(entry.value + 1, width: instrIndex.width), [
                Case(mopStep, [
                  CaseItem(Const(0, width: maxLen.bitLength), [
                    alu < 0,
                    rs1 < fields['rs1']!.zeroExtend(mxlen.size),
                    rs2 < fields['rs2']!.zeroExtend(mxlen.size),
                    rd < fields['rd']!.zeroExtend(mxlen.size),
                    imm < fields['imm']!.zeroExtend(mxlen.size),
                    mopStep < 1,
                  ]),
                  ...steps,
                  CaseItem(Const(steps.length + 1, width: maxLen.bitLength), [
                    // Indicate status of execution unit
                    done < 1,
                  ]),
                ]),
              ]);
            }).toList(),
          ),
        ],
      ),
    ]);
  }
}
