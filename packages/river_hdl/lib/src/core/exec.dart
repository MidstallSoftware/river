import 'package:rohd/rohd.dart';
import 'package:rohd_hcl/rohd_hcl.dart';
import 'package:riscv/riscv.dart';

class ExecutionUnit extends Module {
  final Microcode microcode;
  final Mxlen mxlen;

  Logic get done => output('done');
  Logic get nextSp => output('nextSp');
  Logic get nextPc => output('nextPc');
  Logic get nextMode => output('nextMode');
  Logic get trap => output('trap');
  Logic get trapCause => output('trapCause');
  Logic get trapTval => output('trapTval');
  Logic get fence => output('fence');

  ExecutionUnit(
    Logic clk,
    Logic reset,
    Logic enable,
    Logic currentSp,
    Logic currentPc,
    Logic currentMode,
    Logic instrIndex,
    Map<String, Logic> instrTypeMap,
    Map<String, Logic> fields,
    DataPortInterface? csrRead,
    DataPortInterface? csrWrite,
    DataPortInterface memRead,
    DataPortInterface memWrite,
    DataPortInterface rs1Read,
    DataPortInterface rs2Read,
    DataPortInterface rdWrite, {
    bool hasSupervisor = false,
    required this.microcode,
    required this.mxlen,
    List<String> staticInstructions = const [],
    super.name = 'river_execution_unit',
  }) {
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);
    enable = addInput('enable', enable);

    currentSp = addInput('currentSp', currentSp, width: mxlen.size);
    currentPc = addInput('currentPc', currentPc, width: mxlen.size);
    currentMode = addInput('currentMode', currentMode, width: 3);

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

    memRead = memRead.clone()
      ..connectIO(
        this,
        memRead,
        outputTags: {DataPortGroup.control},
        inputTags: {DataPortGroup.data, DataPortGroup.integrity},
        uniquify: (og) => 'memRead_$og',
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

    addOutput('done');
    addOutput('nextSp', width: mxlen.size);
    addOutput('nextPc', width: mxlen.size);
    addOutput('nextMode', width: 3);
    addOutput('trap');
    addOutput('trapCause', width: 6);
    addOutput('trapTval', width: mxlen.size);
    addOutput('fence');

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
        .map((s) => s.ops.length * 2)
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
          return rd < value.zeroExtend(mxlen.size);
        case MicroOpField.rs1:
          return rs1 < value.zeroExtend(mxlen.size);
        case MicroOpField.rs2:
          return rs2 < value.zeroExtend(mxlen.size);
        case MicroOpField.imm:
          return imm < value.zeroExtend(mxlen.size);
        case MicroOpField.sp:
          return nextSp < value.zeroExtend(mxlen.size);
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

    Logic compareCurrentMode(PrivilegeMode target) =>
        currentMode.eq(Const(target.id, width: 3));

    Logic selectTrapTargetMode(
      Logic trapInterrupt,
      Logic causeCode,
      Logic mode,
      Logic mideleg,
      Logic medeleg,
    ) {
      final machine = Const(PrivilegeMode.machine.id, width: 3);
      if (csrRead == null || csrWrite == null) return machine;

      final supervisor = Const(PrivilegeMode.supervisor.id, width: 3);

      final isMachine = mode.eq(machine);
      final noSup = ~Const(hasSupervisor ? 1 : 0);

      final delegatedInterrupt = mideleg[causeCode];
      final delegatedException = medeleg[causeCode];

      final goesToSupervisor = mux(
        trapInterrupt,
        delegatedInterrupt,
        delegatedException,
      );

      final notMachineAndHasSup = ~isMachine & Const(hasSupervisor ? 1 : 0);

      return mux(
        notMachineAndHasSup,
        mux(goesToSupervisor, supervisor, machine),
        machine,
      );
    }

    Logic encodeCause(Logic trapInterrupt, Logic causeCode) =>
        (trapInterrupt.zeroExtend(mxlen.size) << (mxlen.size - 1)) |
        causeCode.zeroExtend(mxlen.size);

    Logic computeTrapVectorPc(
      Logic tvec,
      Logic causeCode,
      Logic trapInterrupt,
    ) {
      final base = tvec & Const(~0x3, width: mxlen.size);
      final mode = tvec.slice(1, 0);

      final isVectored = mode.eq(Const(1, width: 2));

      final vecOffset = (causeCode << 2).zeroExtend(mxlen.size);

      return mux(isVectored & trapInterrupt, base + vecOffset, base);
    }

    List<Conditional> trap(Trap t, [Logic? tval]) {
      final trapInterrupt = Const(t.interrupt ? 1 : 0);
      final causeCode = Const(t.mcauseCode, width: 6);

      if (csrRead == null || csrWrite == null) {
        return [
          trapCause < encodeCause(trapInterrupt, causeCode).slice(5, 0),
          trapTval < (tval ?? Const(0, width: mxlen.size)),
          output('trap') < 1,
          done < 1,
        ];
      }

      final mideleg = Logic(width: mxlen.size);
      final medeleg = Logic(width: mxlen.size);
      final mtvec = Logic(width: mxlen.size);
      final stvec = Logic(width: mxlen.size);
      final tvec = Logic(width: mxlen.size);

      final newMode = selectTrapTargetMode(
        trapInterrupt,
        causeCode,
        currentMode,
        mideleg,
        medeleg,
      );

      return [
        csrRead!.en < 1,
        csrRead!.addr < CsrAddress.mideleg.address,
        mideleg < csrRead!.data,

        csrRead!.en < 1,
        csrRead!.addr < CsrAddress.medeleg.address,
        medeleg < csrRead!.data,

        csrRead!.en < 1,
        csrRead!.addr < CsrAddress.mtvec.address,
        mtvec < csrRead!.data,

        csrRead!.en < 1,
        csrRead!.addr < CsrAddress.stvec.address,
        stvec < csrRead!.data,

        nextMode < newMode,
        trapCause < encodeCause(trapInterrupt, causeCode).slice(5, 0),
        trapTval < (tval ?? Const(0, width: mxlen.size)),

        tvec <
            mux(
              newMode.eq(Const(PrivilegeMode.machine.id, width: 3)),
              mtvec,
              stvec,
            ),

        nextPc < computeTrapVectorPc(tvec, causeCode, trapInterrupt),

        output('trap') < 1,
        done < 1,
      ];
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
          fence < 0,
          nextPc < currentPc,
          nextSp < currentSp,
        ],
        orElse: [
          If(
            enable,
            then: [
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
                          writeField(
                            mop.source,
                            port.data +
                                Const(mop.valueOffset, width: mxlen.size),
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
                              (switch (mop.alu) {
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
                                  (readField(mop.a) -
                                          readField(mop.b))[mxlen.size - 1]
                                      .zeroExtend(mxlen.size),
                                MicroOpAluFunct.masked =>
                                  readField(mop.a) & ~readField(mop.b),
                                MicroOpAluFunct.mul =>
                                  readField(mop.a) * readField(mop.b),
                                MicroOpAluFunct.mulw =>
                                  readField(mop.a) * readField(mop.b),
                                MicroOpAluFunct.mulh =>
                                  readField(mop.a) * readField(mop.b),
                                MicroOpAluFunct.mulhsu =>
                                  readField(mop.a) * readField(mop.b),
                                MicroOpAluFunct.mulhu =>
                                  readField(mop.a) * readField(mop.b),
                                MicroOpAluFunct.div =>
                                  readField(mop.a) / readField(mop.b),
                                MicroOpAluFunct.divu =>
                                  readField(mop.a) / readField(mop.b),
                                MicroOpAluFunct.divuw =>
                                  readField(mop.a) / readField(mop.b),
                                MicroOpAluFunct.divw =>
                                  readField(mop.a) / readField(mop.b),
                                MicroOpAluFunct.rem =>
                                  readField(mop.a) % readField(mop.b),
                                MicroOpAluFunct.remu =>
                                  readField(mop.a) % readField(mop.b),
                                MicroOpAluFunct.remuw =>
                                  readField(mop.a) % readField(mop.b),
                                MicroOpAluFunct.remw =>
                                  readField(mop.a) % readField(mop.b),
                                _ => throw 'Invalid ALU function ${mop.alu}',
                              }).named(
                                'alu_${op.mnemonic}_${mop.alu.name}_${mop.a.name}_${mop.b.name}',
                              ),
                          mopStep < mopStep + 1,
                        ]),
                      );
                    } else if (mop is UpdatePCMicroOp) {
                      Logic value = Const(mop.offset, width: mxlen.size);
                      if (mop.offsetField != null)
                        value = readField(mop.offsetField!);
                      if (mop.offsetSource != null)
                        value = readSource(mop.offsetSource!);
                      if (mop.align) value &= ~Const(1, width: mxlen.size);

                      steps.add(
                        CaseItem(Const(i, width: maxLen.bitLength), [
                          nextPc < (mop.absolute ? value : (currentPc + value)),
                          mopStep < mopStep + 1,
                        ]),
                      );
                    } else if (mop is MemLoadMicroOp) {
                      final base = readField(mop.base);
                      final addr = base + imm;

                      final unaligned =
                          (addr & Const(mop.size.bytes - 1, width: mxlen.size))
                              .neq(0);

                      steps.add(
                        CaseItem(Const(i, width: maxLen.bitLength), [
                          If(
                            unaligned,
                            then: trap(Trap.misalignedLoad, addr),
                            orElse: [
                              memRead.en < 1,
                              memRead.addr < addr,
                              mopStep < mopStep + 1,
                            ],
                          ),
                        ]),
                      );

                      steps.add(
                        CaseItem(Const(i + 1, width: maxLen.bitLength), [
                          If(memRead.done, then: [mopStep < mopStep + 1]),
                        ]),
                      );

                      final raw = memRead.data.slice(mop.size.bits - 1, 0);

                      steps.add(
                        CaseItem(Const(i + 2, width: maxLen.bitLength), [
                          writeField(
                            mop.dest,
                            mop.unsigned
                                ? raw.zeroExtend(mxlen.size)
                                : raw.signExtend(mxlen.size),
                          ),
                        ]),
                      );
                    } else if (mop is MemStoreMicroOp) {
                      final base = readField(mop.base);
                      final value = readField(mop.src);
                      final addr = base + imm;

                      final unaligned =
                          (addr & Const(mop.size.bytes - 1, width: mxlen.size))
                              .neq(0);

                      steps.add(
                        CaseItem(Const(i, width: maxLen.bitLength), [
                          If(
                            unaligned,
                            then: trap(Trap.misalignedStore, addr),
                            orElse: [
                              memWrite.en < 1,
                              memWrite.addr < addr,
                              memWrite.data <
                                  [
                                    Const(mop.size.bytes, width: 7),
                                    value,
                                  ].swizzle(),
                              mopStep < mopStep + 1,
                            ],
                          ),
                        ]),
                      );

                      steps.add(
                        CaseItem(Const(i + 1, width: maxLen.bitLength), [
                          If(memWrite.done, then: [mopStep < mopStep + 1]),
                        ]),
                      );
                    } else if (mop is TrapMicroOp) {
                      steps.add(
                        CaseItem(Const(i, width: maxLen.bitLength), [
                          Case(currentMode, [
                            CaseItem(
                              Const(PrivilegeMode.machine.id, width: 3),
                              trap(mop.kindMachine),
                            ),
                            CaseItem(
                              Const(PrivilegeMode.supervisor.id, width: 3),
                              trap(mop.kindSupervisor ?? mop.kindMachine),
                            ),
                            CaseItem(
                              Const(PrivilegeMode.user.id, width: 3),
                              trap(mop.kindUser ?? mop.kindMachine),
                            ),
                          ]),
                        ]),
                      );
                    } else if (mop is BranchIfMicroOp) {
                      final target = readSource(mop.target);

                      final value = mop.offsetField != null
                          ? readField(mop.offsetField!)
                          : Const(mop.offset, width: mxlen.size);

                      final condition = switch (mop.condition) {
                        MicroOpCondition.eq => target.eq(0),
                        MicroOpCondition.ne => target.neq(0),
                        MicroOpCondition.lt => target.lt(0),
                        MicroOpCondition.gt => target.gt(0),
                        MicroOpCondition.ge => target.gte(0),
                        MicroOpCondition.le => target.lte(0),
                      };

                      steps.add(
                        CaseItem(Const(i, width: maxLen.bitLength), [
                          If(
                            condition,
                            then: [nextPc < value, done < 1],
                            orElse: [mopStep < mopStep + 1],
                          ),
                        ]),
                      );
                    } else if (mop is WriteLinkRegisterMicroOp) {
                      final value =
                          nextPc + Const(mop.pcOffset, width: mxlen.size);

                      Logic reg = Const(Register.x0.value, width: 5);
                      if (mop.link.reg != null) {
                        reg = Const(mop.link.reg!.value, width: 5);
                      } else if (mop.link.source != null) {
                        reg = readSource(mop.link.source!);
                      }

                      steps.add(
                        CaseItem(Const(i, width: maxLen.bitLength), [
                          If(
                            reg.neq(Register.x0.value),
                            then: [
                              rdWrite.addr < reg.slice(4, 0),
                              rdWrite.data < value,
                              rdWrite.en < 1,
                            ],
                          ),
                          mopStep < mopStep + 1,
                        ]),
                      );
                    } else if (mop is FenceMicroOp) {
                      steps.add(
                        CaseItem(Const(i, width: maxLen.bitLength), [
                          rs1Read.en < 0,
                          rs2Read.en < 0,
                          if (csrRead != null) csrRead.en < 0,
                          if (csrWrite != null) csrWrite.en < 0,
                          memRead.en < 0,
                          memWrite.en < 0,
                          rdWrite.en < 0,
                          fence < 1,
                          mopStep < mopStep + 1,
                        ]),
                      );
                    } else {
                      print(mop);
                    }
                  }

                  return CaseItem(
                    Const(entry.value + 1, width: instrIndex.width),
                    [
                      Case(mopStep, [
                        CaseItem(Const(0, width: maxLen.bitLength), [
                          alu < 0,
                          fence < 0,
                          rs1 < fields['rs1']!.zeroExtend(mxlen.size),
                          rs2 < fields['rs2']!.zeroExtend(mxlen.size),
                          rd < fields['rd']!.zeroExtend(mxlen.size),
                          imm < fields['imm']!.zeroExtend(mxlen.size),
                          mopStep < 1,
                        ]),
                        ...steps,
                        CaseItem(
                          Const(steps.length + 1, width: maxLen.bitLength),
                          [done < 1],
                        ),
                      ]),
                    ],
                  );
                }).toList(),
              ),
            ],
            orElse: [
              alu < 0,
              mopStep < 0,
              done < 0,
              rs1Read.en < 0,
              rs1Read.addr < 0,
              rs2Read.en < 0,
              rs2Read.addr < 0,
              rdWrite.en < 0,
              rdWrite.addr < 0,
              fence < 0,
            ],
          ),
        ],
      ),
    ], reset: reset);
  }
}
