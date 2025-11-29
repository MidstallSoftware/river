import 'dart:collection';
import 'package:riscv/riscv.dart';
import 'package:river/river.dart';
import 'csr.dart';
import 'dev.dart';
import 'mmu.dart';
import 'int.dart';

class AbortException extends TrapException {
  final String message;

  const AbortException(super.trap, this.message, [super.tval = null]);
  const AbortException.illegalInstruction(this.message)
    : super(Trap.illegal, null);

  @override
  String toString() => 'AbortException($trap, "$message", $tval)';
}

class TrapException implements Exception {
  final Trap trap;

  const TrapException(this.trap, [this.tval = null]);
  const TrapException.illegalInstruction() : trap = Trap.illegal, tval = null;

  final int? tval;

  @override
  String toString() => 'TrapException($trap, $tval)';
}

class RiverCoreEmulatorState {
  int pc;
  int? _rs1;
  int? _rs2;
  int? _rd;
  int? _imm;

  InstructionType ir;

  RiverCoreEmulatorState(this.pc, this.ir, this.sp) : alu = 0;

  int alu;
  int sp;
  int get rs1 => _rs1 ?? ir.toMap()['rs1'] ?? 0;
  int get rs2 => _rs2 ?? ir.toMap()['rs2'] ?? 0;
  int get rd => _rd ?? ir.toMap()['rd'] ?? 0;
  int get imm => _imm ?? ir.imm;

  int readSource(MicroOpSource source) {
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
      default:
        throw 'Invalid source $source';
    }
  }

  int readField(MicroOpField field, {bool register = true}) {
    switch (field) {
      case MicroOpField.rd:
        return register ? rd : (ir.toMap()['rd'] ?? 0);
      case MicroOpField.rs1:
        return register ? rs1 : (ir.toMap()['rs1'] ?? 0);
      case MicroOpField.rs2:
        return register ? rs2 : (ir.toMap()['rs2'] ?? 0);
      case MicroOpField.imm:
        return register ? imm : ir.imm;
      case MicroOpField.pc:
        return pc;
      case MicroOpField.sp:
        return sp;
      default:
        throw 'Invalid field $field';
    }
  }

  void clearField(MicroOpField field) {
    switch (field) {
      case MicroOpField.rd:
        _rd = null;
        break;
      case MicroOpField.rs1:
        _rs1 = null;
        break;
      case MicroOpField.rs2:
        _rs2 = null;
        break;
      case MicroOpField.imm:
        _imm = null;
        break;
      default:
        throw 'Invalid field $field';
    }
  }

  void writeField(MicroOpField field, int value) {
    switch (field) {
      case MicroOpField.rd:
        _rd = value;
        break;
      case MicroOpField.rs1:
        _rs1 = value;
        break;
      case MicroOpField.rs2:
        _rs2 = value;
        break;
      case MicroOpField.imm:
        _imm = value;
        break;
      case MicroOpField.sp:
        sp = value;
        break;
      default:
        throw 'Invalid field $field';
    }
  }

  @override
  String toString() =>
      'RiverCoreEmulatorState($pc, $ir, rd: $rd, rs1: $rs1, rs2: $rs2, imm: $imm, alu: $alu, sp: $sp, pc: $pc)';
}

class RiverCoreEmulator {
  final RiverCore config;

  Map<Register, int> xregs;
  CsrFile csrs;
  List<int> _reservationSet;
  bool idle;
  PrivilegeMode mode;

  List<InterruptControllerEmulator> _interrupts;

  UnmodifiableListView<InterruptControllerEmulator> get interrupts =>
      UnmodifiableListView(_interrupts);

  UnmodifiableListView<int> get reservationSet =>
      UnmodifiableListView(_reservationSet);

  final MmuEmulator mmu;

  RiverCoreEmulator(
    this.config, {
    Map<MemoryBlock, DeviceAccessorEmulator> memDevices = const {},
  }) : xregs = {},
       mmu = MmuEmulator(config.mmu, memDevices),
       csrs = CsrFile(
         config.mxlen,
         hasSupervisor: config.hasSupervisor,
         hasUser: config.hasUser,
       ),
       mode = PrivilegeMode.machine,
       _reservationSet = [],
       _interrupts = config.interrupts
           .map((config) => InterruptControllerEmulator(config))
           .toList(),
       idle = false;

  void clearReservationSet() => _reservationSet.clear();

  void reset() {
    mode = PrivilegeMode.machine;
    xregs = {};
    _reservationSet = [];
    idle = false;
    csrs.reset();
    mmu.reset();
  }

  InstructionType? decode(int instr) {
    for (final ext in config.extensions) {
      for (final op in ext.operations) {
        if (op.checkOpcode(instr)) {
          try {
            return op.decode(instr);
          } on DecodeException catch (_exception) {
            continue;
          }
        }
      }
    }
    return null;
  }

  Operation? findOperationByInstruction(InstructionType instr) {
    for (final ext in config.extensions) {
      for (final op in ext.operations) {
        if (op.matches(instr)) {
          return op;
        }
      }
    }

    return null;
  }

  RiverCoreEmulatorState execute(int pc, InstructionType instr) {
    final op = findOperationByInstruction(instr)!;
    var state = RiverCoreEmulatorState(pc, instr, xregs[Register.x2] ?? 0);
    state = _innerExecute(state, op);
    xregs[Register.x2] = state.sp;
    return state;
  }

  PrivilegeMode _selectTrapTargetMode(Trap trap) {
    if (mode == PrivilegeMode.machine) {
      return PrivilegeMode.machine;
    }

    if (!config.hasSupervisor) {
      return PrivilegeMode.machine;
    }

    final int code = switch (mode) {
      PrivilegeMode.machine => trap.mcauseCode,
      PrivilegeMode.supervisor => trap.scauseCode,
      PrivilegeMode.user => trap.ucauseCode,
    };

    if (trap.interrupt) {
      final mideleg = csrs.read(CsrAddress.mideleg.address, this);
      final delegated = ((mideleg >> code) & 1) != 0;
      return delegated ? PrivilegeMode.supervisor : PrivilegeMode.machine;
    } else {
      final medeleg = csrs.read(CsrAddress.medeleg.address, this);
      final delegated = ((medeleg >> code) & 1) != 0;
      return delegated ? PrivilegeMode.supervisor : PrivilegeMode.machine;
    }
  }

  int _encodeCause(
    Trap trap,
    PrivilegeMode oldMode,
    PrivilegeMode targetMode,
    int xlen,
  ) {
    final code = switch (oldMode) {
      PrivilegeMode.machine => trap.mcauseCode,
      PrivilegeMode.supervisor => trap.scauseCode,
      PrivilegeMode.user => trap.ucauseCode,
    };

    final interruptBit = trap.interrupt ? (1 << (xlen - 1)) : 0;
    return interruptBit | code;
  }

  int trap(int pc, TrapException e) {
    final oldMode = this.mode;
    final targetMode = _selectTrapTargetMode(e.trap);
    final xlen = config.mxlen.size;

    final causeValue = _encodeCause(e.trap, oldMode, targetMode, xlen);

    late final CsrAddress causeCsr;
    late final CsrAddress epcCsr;
    late final CsrAddress tvalCsr;
    late final CsrAddress tvecCsr;

    switch (targetMode) {
      case PrivilegeMode.machine:
        causeCsr = CsrAddress.mcause;
        epcCsr = CsrAddress.mepc;
        tvalCsr = CsrAddress.mtval;
        tvecCsr = CsrAddress.mtvec;
        break;
      case PrivilegeMode.supervisor:
        causeCsr = CsrAddress.scause;
        epcCsr = CsrAddress.sepc;
        tvalCsr = CsrAddress.stval;
        tvecCsr = CsrAddress.stvec;
        break;
      case PrivilegeMode.user:
        causeCsr = CsrAddress.ucause;
        epcCsr = CsrAddress.uepc;
        tvalCsr = CsrAddress.utval;
        tvecCsr = CsrAddress.utvec;
        break;
    }

    var mstatus = csrs.read(CsrAddress.mstatus.address, this);

    switch (targetMode) {
      case PrivilegeMode.machine:
        final mpp = oldMode.id;
        mstatus = (mstatus & ~(0x3 << 11)) | (mpp << 11);

        final mie = (mstatus >> 3) & 1;
        mstatus = (mstatus & ~(1 << 7)) | (mie << 7);
        mstatus &= ~(1 << 3);
        break;

      case PrivilegeMode.supervisor:
        final spp = (oldMode == PrivilegeMode.user) ? 0 : 1;
        mstatus = (mstatus & ~(1 << 8)) | (spp << 8);

        final sie = (mstatus >> 1) & 1;
        mstatus = (mstatus & ~(1 << 5)) | (sie << 5);
        mstatus &= ~(1 << 1);
        break;

      case PrivilegeMode.user:
        final uie = mstatus & 1;
        mstatus = (mstatus & ~(1 << 4)) | (uie << 4);
        mstatus &= ~1;
        break;
    }

    csrs.write(causeCsr.address, causeValue, this);
    csrs.write(epcCsr.address, pc, this);
    csrs.write(tvalCsr.address, e.tval ?? 0, this);
    csrs.write(CsrAddress.mstatus.address, mstatus, this);

    this.mode = targetMode;
    final tvec = csrs.read(tvecCsr.address, this);

    if (tvec == 0)
      throw AbortException.illegalInstruction(
        'Double fault due to $tvecCsr being invalid ($tvec): $e',
      );

    final base = tvec & ~0x3;
    final mode = tvec & 0x3;

    if (mode == 1 && e.trap.interrupt) {
      final code = switch (this.mode) {
        PrivilegeMode.machine => e.trap.mcauseCode,
        PrivilegeMode.supervisor => e.trap.scauseCode,
        PrivilegeMode.user => e.trap.ucauseCode,
      };

      return base + 4 * code;
    } else {
      return base;
    }
  }

  PrivilegeMode _effectiveMemPrivilege() {
    final mstatus = csrs.read(CsrAddress.mstatus.address, this);

    final mprv = (mstatus >> 17) & 1;
    if (mprv == 1 && mode == PrivilegeMode.machine) {
      final mpp = (mstatus >> 11) & 0x3;
      switch (mpp) {
        case 0:
          return PrivilegeMode.user;
        case 1:
          return PrivilegeMode.supervisor;
        case 3:
          return PrivilegeMode.machine;
        default:
          return PrivilegeMode.machine;
      }
    }

    return mode;
  }

  int translate(int addr, MemoryAccess access) {
    final eff = _effectiveMemPrivilege();

    int mstatus = csrs.read(CsrAddress.mstatus.address, this);
    final mxr = ((mstatus >> 19) & 1) != 0;
    final sum = ((mstatus >> 18) & 1) != 0;

    return mmu.translate(addr, access, privilege: eff, sum: sum, mxr: mxr);
  }

  int fetch(int pc) {
    final phys = translate(pc, MemoryAccess.instr);

    final mstatus = csrs.read(CsrAddress.mstatus.address, this);
    final mxr = ((mstatus >> 19) & 1) != 0;
    final sum = ((mstatus >> 18) & 1) != 0;

    return mmu.read(phys, pageTranslate: false, sum: sum, mxr: mxr);
  }

  int read(int addr) {
    final phys = translate(addr, MemoryAccess.read);

    final mstatus = csrs.read(CsrAddress.mstatus.address, this);
    final mxr = ((mstatus >> 19) & 1) != 0;
    final sum = ((mstatus >> 18) & 1) != 0;

    return mmu.read(phys, pageTranslate: false, sum: sum, mxr: mxr);
  }

  void write(int addr, int value) {
    final phys = translate(addr, MemoryAccess.write);

    if (_reservationSet.isNotEmpty) {
      if (!_reservationSet.contains(phys)) {
        _reservationSet.clear();
      }
    }

    _reservationSet.clear();

    final mstatus = csrs.read(CsrAddress.mstatus.address, this);
    final mxr = ((mstatus >> 19) & 1) != 0;
    final sum = ((mstatus >> 18) & 1) != 0;

    mmu.write(phys, value, pageTranslate: false, sum: sum, mxr: mxr);
  }

  RiverCoreEmulatorState _innerExecute(
    RiverCoreEmulatorState state,
    Operation op,
  ) {
    if (!op.allowedLevels.contains(mode)) {
      state.pc = trap(state.pc, TrapException.illegalInstruction());
      return state;
    }

    for (final mop in op.microcode) {
      if (mop is WriteRegisterMicroOp) {
        final value = state.readSource(mop.source);
        final reg = Register.values[mop.offset + state.readField(mop.field)];
        if (reg == Register.x0) {
          continue;
        }

        xregs[reg] = value;
      } else if (mop is ReadRegisterMicroOp) {
        final reg = Register.values[mop.offset + state.readField(mop.source)];
        final value = xregs[reg] ?? 0;
        state.writeField(mop.source, value);
      } else if (mop is AluMicroOp) {
        final a = state.readField(mop.a);
        final b = state.readField(mop.b);
        switch (mop.funct) {
          case MicroOpAluFunct.add:
            state.alu = a + b;
            break;
          case MicroOpAluFunct.sub:
            state.alu = a - b;
            break;
          case MicroOpAluFunct.mul:
            state.alu = a * b;
            break;
          case MicroOpAluFunct.and:
            state.alu = a & b;
            break;
          case MicroOpAluFunct.or:
            state.alu = a | b;
            break;
          case MicroOpAluFunct.xor:
            state.alu = a ^ b;
            break;
          case MicroOpAluFunct.sll:
            state.alu = a << b;
            break;
          case MicroOpAluFunct.srl:
          case MicroOpAluFunct.sra:
            state.alu = a >> b;
            break;
          case MicroOpAluFunct.slt:
            state.alu = a <= b ? 1 : 0;
            break;
          case MicroOpAluFunct.sltu:
            state.alu =
                a.toUnsigned(config.mxlen.size) <=
                    b.toUnsigned(config.mxlen.size)
                ? 1
                : 0;
            break;
          case MicroOpAluFunct.masked:
            state.alu = a & ~b;
            break;
          case MicroOpAluFunct.mulh:
            {
              final xlen = config.mxlen.size;
              final aS = a.toSigned(xlen);
              final bS = b.toSigned(xlen);
              final wide = BigInt.from(aS) * BigInt.from(bS);
              final high = wide >> xlen;
              state.alu = (high & ((BigInt.one << xlen) - BigInt.one)).toInt();
              break;
            }
          case MicroOpAluFunct.mulhsu:
            {
              final xlen = config.mxlen.size;
              final aS = a.toSigned(xlen);
              final bU = b.toUnsigned(xlen);
              final wide = BigInt.from(aS) * BigInt.from(bU);
              final high = wide >> xlen;
              state.alu = (high & ((BigInt.one << xlen) - BigInt.one)).toInt();
              break;
            }
          case MicroOpAluFunct.mulhu:
            {
              final xlen = config.mxlen.size;
              final aU = a.toUnsigned(xlen);
              final bU = b.toUnsigned(xlen);
              final wide = BigInt.from(aU) * BigInt.from(bU);
              final high = wide >> xlen;
              state.alu = (high & ((BigInt.one << xlen) - BigInt.one)).toInt();
              break;
            }
          case MicroOpAluFunct.div:
            {
              final xlen = config.mxlen.size;
              final dividend = a.toSigned(xlen);
              final divisor = b.toSigned(xlen);

              if (divisor == 0) {
                state.alu = -1;
              } else {
                final intMin = 1 << (xlen - 1);
                if (dividend == intMin && divisor == -1) {
                  state.alu = intMin;
                } else {
                  state.alu = (dividend ~/ divisor);
                }
              }
              break;
            }
          case MicroOpAluFunct.divu:
            {
              final xlen = config.mxlen.size;

              final mask = (BigInt.one << xlen) - BigInt.one;

              final dividend = BigInt.from(a) & mask;
              final divisor = BigInt.from(b) & mask;

              if (divisor == BigInt.zero) {
                state.alu = mask.toInt();
              } else {
                final q = dividend ~/ divisor;
                state.alu = (q & mask).toInt();
              }
              break;
            }
          case MicroOpAluFunct.rem:
            {
              final xlen = config.mxlen.size;
              final dividend = a.toSigned(xlen);
              final divisor = b.toSigned(xlen);

              if (divisor == 0) {
                state.alu = dividend;
              } else {
                final intMin = 1 << (xlen - 1);
                if (dividend == intMin && divisor == -1) {
                  state.alu = 0;
                } else {
                  final q = dividend ~/ divisor;
                  final r = dividend - q * divisor;
                  state.alu = r;
                }
              }
              break;
            }
          case MicroOpAluFunct.remu:
            {
              final xlen = config.mxlen.size;
              final dividend = a.toUnsigned(xlen);
              final divisor = b.toUnsigned(xlen);

              if (divisor == 0) {
                state.alu = dividend;
              } else {
                state.alu = (dividend % divisor);
              }
              break;
            }
          case MicroOpAluFunct.mulw:
            {
              final prod = (a.toSigned(32) * b.toSigned(32)) & 0xFFFFFFFF;
              state.alu = prod.toSigned(32);
              break;
            }
          case MicroOpAluFunct.divw:
            {
              final dividend = a.toSigned(32);
              final divisor = b.toSigned(32);

              if (divisor == 0) {
                state.alu = -1;
              } else if (dividend == -0x80000000 && divisor == -1) {
                state.alu = -0x80000000;
              } else {
                state.alu = (dividend ~/ divisor).toSigned(32);
              }
              break;
            }
          case MicroOpAluFunct.divuw:
            {
              final dividend = a.toUnsigned(32);
              final divisor = b.toUnsigned(32);

              if (divisor == 0) {
                state.alu = 0xFFFFFFFF;
              } else {
                final q = dividend ~/ divisor;
                state.alu = q.toUnsigned(32);
              }
              break;
            }
          case MicroOpAluFunct.remw:
            {
              final dividend = a.toSigned(32);
              final divisor = b.toSigned(32);

              if (divisor == 0) {
                state.alu = dividend.toSigned(32);
              } else if (dividend == -0x80000000 && divisor == -1) {
                state.alu = 0;
              } else {
                final q = dividend ~/ divisor;
                state.alu = (dividend - q * divisor).toSigned(32);
              }
              break;
            }
          case MicroOpAluFunct.remuw:
            {
              final dividend = a.toUnsigned(32);
              final divisor = b.toUnsigned(32);

              if (divisor == 0) {
                state.alu = dividend;
              } else {
                final r = dividend % divisor;
                state.alu = r.toUnsigned(32);
              }
              break;
            }
          default:
            throw 'Invalid ALU function ${mop.funct}';
        }
      } else if (mop is UpdatePCMicroOp) {
        final value = mop.offsetField != null
            ? state.readField(mop.offsetField!)
            : mop.offset;
        state.pc += value;
      } else if (mop is MemLoadMicroOp) {
        final base = state.readField(mop.base);
        final addr = base + state.imm;

        if (mop.size.bytes > 1 && (addr & (mop.size.bytes - 1)) != 0) {
          state.pc = trap(state.pc, TrapException(Trap.misalignedLoad, addr));
          return state;
        }

        try {
          final loaded = read(addr);

          final finalValue = mop.unsigned
              ? loaded.toUnsigned(mop.size.bits)
              : loaded.toSigned(mop.size.bits);

          state.writeField(mop.dest, finalValue);
        } on TrapException catch (e) {
          state.pc = trap(state.pc, e);
          return state;
        }
      } else if (mop is MemStoreMicroOp) {
        final base = state.readField(mop.base);
        final value = state.readField(mop.src);
        final addr = base + state.imm;

        if (mop.size.bytes > 1 && (addr & (mop.size.bytes - 1)) != 0) {
          state.pc = trap(state.pc, TrapException(Trap.misalignedStore, addr));
          return state;
        }

        try {
          write(addr, value.toUnsigned(mop.size.bits));
        } on TrapException catch (e) {
          state.pc = trap(state.pc, e);
          return state;
        }
      } else if (mop is TrapMicroOp) {
        state.pc = trap(
          state.pc,
          TrapException(switch (mode) {
            PrivilegeMode.machine => mop.kindMachine,
            PrivilegeMode.supervisor => mop.kindSupervisor ?? mop.kindMachine,
            PrivilegeMode.user => mop.kindUser ?? mop.kindMachine,
          }),
        );
        return state;
      } else if (mop is BranchIfMicroOp) {
        final target = state.readSource(mop.target);

        final value = mop.offsetField != null
            ? state.readField(mop.offsetField!)
            : mop.offset;

        final condition = switch (mop.condition) {
          MicroOpCondition.eq => target == 0,
          MicroOpCondition.ne => target != 0,
          MicroOpCondition.lt => target < 0,
          MicroOpCondition.gt => target > 0,
          MicroOpCondition.ge => target >= 0,
          MicroOpCondition.le => target <= 0,
        };

        if (condition) {
          state.pc += value;
        }
      } else if (mop is WriteLinkRegisterMicroOp) {
        xregs[mop.link.reg] = state.pc + mop.pcOffset;
      } else if (mop is ReadCsrMicroOp) {
        final reg = state.readField(mop.source);

        if (mode == PrivilegeMode.user) {
          state.pc = trap(state.pc, TrapException.illegalInstruction());
          return state;
        }

        try {
          final value = csrs.read(reg, this);
          state.writeField(mop.source, value);
        } on TrapException catch (e) {
          state.pc = trap(state.pc, e);
          return state;
        }
      } else if (mop is WriteCsrMicroOp) {
        final value = state.readSource(mop.source);
        final reg = state.readField(mop.field);

        if (mode == PrivilegeMode.user) {
          state.pc = trap(state.pc, TrapException.illegalInstruction());
          return state;
        }

        try {
          csrs.write(reg, value, this);
        } on TrapException catch (e) {
          state.pc = trap(state.pc, e);
          return state;
        }
      } else if (mop is ReturnMicroOp) {
        var mstatus = csrs.read(CsrAddress.mstatus.address, this);

        try {
          switch (mop.mode) {
            case PrivilegeMode.machine:
              {
                final mpp = (mstatus >> 11) & 0x3;

                final newMode =
                    PrivilegeMode.find(mpp) ??
                    (throw TrapException.illegalInstruction());

                final mpie = (mstatus >> 7) & 1;
                mstatus = (mstatus & ~(1 << 3)) | (mpie << 3);

                mstatus |= (1 << 7);
                mstatus &= ~(0x3 << 11);

                csrs.write(CsrAddress.mstatus.address, mstatus, this);

                mode = newMode;

                state.pc = csrs.read(CsrAddress.mepc.address, this);
                break;
              }
            case PrivilegeMode.supervisor:
              {
                final spp = (mstatus >> 8) & 1;
                final newMode = spp == 0
                    ? PrivilegeMode.user
                    : PrivilegeMode.supervisor;
                final spie = (mstatus >> 5) & 1;
                mstatus = (mstatus & ~(1 << 1)) | (spie << 1);

                mstatus |= (1 << 5);
                mstatus &= ~(1 << 8);

                csrs.write(CsrAddress.mstatus.address, mstatus, this);

                mode = newMode;

                state.pc = csrs.read(CsrAddress.sepc.address, this);
                break;
              }
            case PrivilegeMode.user:
              {
                final upie = (mstatus >> 4) & 1;
                mstatus = (mstatus & ~1) | upie;

                mstatus |= (1 << 4);

                mode = PrivilegeMode.user;

                csrs.write(CsrAddress.mstatus.address, mstatus, this);

                state.pc = csrs.read(CsrAddress.uepc.address, this);
                break;
              }
          }
        } on TrapException catch (e) {
          state.pc = trap(state.pc, e);
          return state;
        }
      } else if (mop is InterruptHoldMicroOp) {
        final mstatus = csrs.read(CsrAddress.mstatus.address, this);
        final mie = (mstatus >> 3) & 1;
        if (mie == 0) continue;

        final pending = _nextPendingIrq();
        if (pending != null) return state;

        idle = true;
      } else if (mop is ModifyLatchMicroOp) {
        if (mop.replace) {
          final value = state.readSource(mop.source);
          state.writeField(mop.field, value);
        } else {
          state.clearField(mop.field);
        }
      } else if (mop is LoadReservedMicroOp) {
        final base = state.readField(mop.base);
        final addr = base + state.imm;

        if (mop.size.bytes > 1 && (addr & (mop.size.bytes - 1)) != 0) {
          state.pc = trap(state.pc, TrapException(Trap.misalignedLoad, addr));
          return state;
        }

        try {
          final loaded = read(addr);

          final value = loaded.toSigned(mop.size.bits);

          final rd = Register.values[state.readField(mop.dest)];
          xregs[rd] = value;

          final phys = translate(addr, MemoryAccess.read);
          _reservationSet
            ..clear()
            ..add(phys);
        } on TrapException catch (e) {
          state.pc = trap(state.pc, e);
          return state;
        }
      } else if (mop is StoreConditionalMicroOp) {
        final base = state.readField(mop.base);
        final addr = base + state.imm;

        if (mop.size.bytes > 1 && (addr & (mop.size.bytes - 1)) != 0) {
          state.pc = trap(state.pc, TrapException(Trap.misalignedStore, addr));
          return state;
        }

        final srcValue = state.readField(mop.src);

        try {
          final phys = translate(addr, MemoryAccess.write);

          final hasReservation =
              _reservationSet.isNotEmpty && _reservationSet.contains(phys);

          int result;

          if (hasReservation) {
            final mstatus = csrs.read(CsrAddress.mstatus.address, this);
            final mxr = ((mstatus >> 19) & 1) != 0;
            final sum = ((mstatus >> 18) & 1) != 0;

            mmu.write(
              phys,
              srcValue.toUnsigned(mop.size.bits),
              pageTranslate: false,
              sum: sum,
              mxr: mxr,
            );

            result = 0;
            _reservationSet.clear();
          } else {
            result = 1;
            _reservationSet.clear();
          }

          final rdIndex = state.readField(mop.dest);
          final rdReg = Register.values[rdIndex];
          if (rdReg != Register.x0) {
            xregs[rdReg] = result;
          }
        } on TrapException catch (e) {
          state.pc = trap(state.pc, e);
          return state;
        }
      } else if (mop is AtomicMemoryMicroOp) {
        final base = state.readField(mop.base);
        final addr = base + state.imm;

        if (mop.size.bytes > 1 && (addr & (mop.size.bytes - 1)) != 0) {
          state.pc = trap(state.pc, TrapException(Trap.misalignedLoad, addr));
          return state;
        }

        final srcRaw = state.readField(mop.src);

        try {
          final phys = translate(addr, MemoryAccess.read);

          final mstatus = csrs.read(CsrAddress.mstatus.address, this);
          final mxr = ((mstatus >> 19) & 1) != 0;
          final sum = ((mstatus >> 18) & 1) != 0;

          final loaded = mmu.read(
            phys,
            pageTranslate: false,
            sum: sum,
            mxr: mxr,
          );

          final mask = (mop.size.bits == 64) ? -1 : ((1 << mop.size.bits) - 1);

          final oldVal = loaded & mask;
          final srcVal = srcRaw & mask;

          int newVal;

          int sx(int v) {
            return v.toSigned(mop.size.bits);
          }

          switch (mop.funct) {
            case MicroOpAtomicFunct.add:
              newVal = (sx(oldVal) + sx(srcVal)) & mask;
              break;
            case MicroOpAtomicFunct.swap:
              newVal = srcVal;
              break;
            case MicroOpAtomicFunct.xor:
              newVal = (oldVal ^ srcVal) & mask;
              break;
            case MicroOpAtomicFunct.and:
              newVal = (oldVal & srcVal) & mask;
              break;
            case MicroOpAtomicFunct.or:
              newVal = (oldVal | srcVal) & mask;
              break;
            case MicroOpAtomicFunct.min:
              newVal = sx(srcVal) < sx(oldVal) ? srcVal : oldVal;
              break;
            case MicroOpAtomicFunct.max:
              newVal = sx(srcVal) > sx(oldVal) ? srcVal : oldVal;
              break;
            case MicroOpAtomicFunct.minu:
              newVal =
                  srcVal.toUnsigned(mop.size.bits) <
                      oldVal.toUnsigned(mop.size.bits)
                  ? srcVal
                  : oldVal;
              break;
            case MicroOpAtomicFunct.maxu:
              newVal =
                  srcVal.toUnsigned(mop.size.bits) >
                      oldVal.toUnsigned(mop.size.bits)
                  ? srcVal
                  : oldVal;
              break;
          }

          mmu.write(phys, newVal, pageTranslate: false, sum: sum, mxr: mxr);

          final rdIndex = state.readField(mop.dest);
          final rdReg = Register.values[rdIndex];
          if (rdReg != Register.x0) {
            final xlen = config.mxlen.size;
            final oldXlen = oldVal.toSigned(mop.size.bits).toSigned(xlen);
            xregs[rdReg] = oldXlen;
          }
        } on TrapException catch (e) {
          state.pc = trap(state.pc, e);
          return state;
        }
      } else if (mop is ValidateFieldMicroOp) {
        final value = state.readField(mop.field);
        bool valid = true;

        switch (mop.condition) {
          case MicroOpCondition.eq:
            valid = value == mop.value;
            break;
          case MicroOpCondition.ne:
            valid = value != mop.value;
            break;
          case MicroOpCondition.lt:
            valid = value < mop.value;
            break;
          case MicroOpCondition.gt:
            valid = value > mop.value;
            break;
          case MicroOpCondition.ge:
            valid = value >= mop.value;
            break;
          case MicroOpCondition.le:
            valid = value <= mop.value;
            break;
          default:
            throw 'Invalid condition: ${mop.condition}';
        }

        if (!valid) {
          state.pc = trap(state.pc, TrapException.illegalInstruction());
          return state;
        }
      } else if (mop is SetFieldMicroOp) {
        state.writeField(mop.field, mop.value);
      } else if (mop is TlbFenceMicroOp) {
        // TODO: once MMU has a TLB
      } else if (mop is TlbInvalidateMicroOp) {
        // TODO: once MMU has a TLB
      } else if (mop is FenceMicroOp) {
        // Do nothing
      } else {
        throw 'Invalid micro-op $mop';
      }
    }

    return state;
  }

  int cycle(int pc, int instr) {
    for (final ext in config.extensions) {
      for (final op in ext.operations) {
        if (op.checkOpcode(instr)) {
          InstructionType? ir;
          try {
            ir = op.decode(instr);
          } on DecodeException catch (exception) {
            continue;
          }

          if (!op.matches(ir)) continue;

          var state = RiverCoreEmulatorState(pc, ir, xregs[Register.x2] ?? 0);
          state = _innerExecute(state, op);
          xregs[Register.x2] = state.sp;
          return state.pc;
        }
      }
    }

    return trap(pc, TrapException.illegalInstruction());
  }

  int? _nextPendingIrq() {
    int? bestIrq;
    InterruptControllerEmulator? bestCtl;

    for (final ctl in _interrupts) {
      final irq = ctl.nextPending();
      if (irq == null) continue;

      if (bestIrq == null || irq < bestIrq) {
        bestIrq = irq;
        bestCtl = ctl;
      }
    }

    return bestIrq;
  }

  Trap _selectExternalInterruptTrap() {
    if (!config.hasSupervisor) {
      return Trap.machineExternal;
    }

    final mideleg = csrs.read(CsrAddress.mideleg.address, this);
    final delegated = ((mideleg >> Trap.machineExternal.mcauseCode) & 1) != 0;
    return delegated ? Trap.supervisorExternal : Trap.machineExternal;
  }

  int runPipeline(int pc) {
    if (idle) return pc;

    final irq = _nextPendingIrq();
    if (irq != null) {
      final mie = csrs.read(CsrAddress.mie.address, this);
      final mstatus = csrs.read(CsrAddress.mstatus.address, this);

      final mieMeie = ((mie >> Trap.machineExternal.mcauseCode) & 1) != 0;
      final mstatusMie = ((mstatus >> 3) & 1) != 0;

      if (mieMeie && mstatusMie) {
        final trapTarget = _selectExternalInterruptTrap();
        return trap(pc, TrapException(trapTarget));
      }
    }

    try {
      int instr = fetch(pc);
      return cycle(pc, instr);
    } on TrapException catch (e) {
      return trap(pc, e);
    }
  }

  @override
  String toString() =>
      'RiverCoreEmulator(xregs: $xregs, mmu: $mmu, csrs: ${csrs.toStringWithCore(this)}, mode: $mode, interrupts: $interrupts)';
}
