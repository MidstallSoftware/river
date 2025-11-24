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
      'RiverCoreEmulatorState($pc, $ir, rd: $rd, rs1: $rs1, rs2: $rs2, imm: $imm, alu: $alu, sp: $sp)';
}

class RiverCoreEmulator {
  final RiverCore config;

  Map<Register, int> xregs;
  CsrFile csrs;
  PrivilegeMode _mode;
  List<int> _reservationSet;
  bool idle;

  List<InterruptControllerEmulator> _interrupts;

  PrivilegeMode get mode => _mode;
  UnmodifiableListView<InterruptControllerEmulator> get interrupts =>
      UnmodifiableListView(_interrupts);

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
       _mode = PrivilegeMode.machine,
       _reservationSet = [],
       _interrupts = config.interrupts
           .map((config) => InterruptControllerEmulator(config))
           .toList(),
       idle = false;

  void reset() {
    _mode = PrivilegeMode.machine;
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
    return state;
  }

  PrivilegeMode _selectTrapTargetMode(Trap trap) {
    if (_mode == PrivilegeMode.machine) {
      return PrivilegeMode.machine;
    }

    if (!config.hasSupervisor) {
      return PrivilegeMode.machine;
    }

    final int code = switch (_mode) {
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
    final oldMode = _mode;
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

    _mode = targetMode;
    final tvec = csrs.read(tvecCsr.address, this);

    if (tvec == 0)
      throw AbortException.illegalInstruction(
        'Double fault due to $tvecCsr being invalid ($tvec): $e',
      );

    final base = tvec & ~0x3;
    final mode = tvec & 0x3;

    if (mode == 1 && e.trap.interrupt) {
      final code = switch (_mode) {
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
    if (!op.allowedLevels.contains(_mode)) {
      state.pc = trap(state.pc, TrapException.illegalInstruction());
      return state;
    }

    for (final mop in op.microcode) {
      if (mop is WriteRegisterMicroOp) {
        final value = state.readSource(mop.source);
        final reg = Register.values[state.readField(mop.field)];
        if (reg == Register.x0) {
          state.pc = trap(state.pc, TrapException.illegalInstruction());
          return state;
        }

        xregs[reg] = value;
      } else if (mop is ReadRegisterMicroOp) {
        final reg = Register.values[state.readField(mop.source)];
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
          TrapException(switch (_mode) {
            PrivilegeMode.machine => mop.kindMachine,
            PrivilegeMode.supervisor => mop.kindSupervisor ?? mop.kindMachine,
            PrivilegeMode.user => mop.kindUser ?? mop.kindMachine,
          }),
        );
        return state;
      } else if (mop is BranchIfZeroMicroOp) {
        final condition = state.readField(mop.field);

        final value = mop.offsetField != null
            ? state.readField(mop.offsetField!)
            : mop.offset;

        if (condition == 0) {
          state.pc += value;
        }
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

                _mode = newMode;

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

                _mode = newMode;

                state.pc = csrs.read(CsrAddress.sepc.address, this);
                break;
              }
            case PrivilegeMode.user:
              {
                final upie = (mstatus >> 4) & 1;
                mstatus = (mstatus & ~1) | upie;

                mstatus |= (1 << 4);

                _mode = PrivilegeMode.user;

                csrs.write(CsrAddress.mstatus.address, mstatus, this);

                state.pc = csrs.read(CsrAddress.uepc.address, this);
                break;
              }
          }
        } on TrapException catch (e) {
          state.pc = trap(state.pc, e);
          return state;
        }
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

          var state = RiverCoreEmulatorState(pc, ir, xregs[Register.x2] ?? 0);
          state = _innerExecute(state, op);
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
