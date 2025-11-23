import 'package:riscv/riscv.dart';
import 'package:river/river.dart';
import 'csr.dart';
import 'dev.dart';
import 'mmu.dart';

enum PrivilegeMode { machine, supervisor, user }

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
  RiverCoreEmulator core;

  RiverCoreEmulatorState(this.pc, this.ir, this.core) : alu = 0;

  int alu;
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
      default:
        throw 'Invalid field $field';
    }
  }

  @override
  String toString() =>
      'RiverCoreEmulatorState($pc, $ir, rd: $rd, rs1: $rs1, rs2: $rs2, imm: $imm, alu: $alu)';
}

class RiverCoreEmulator {
  final RiverCore config;

  Map<Register, int> xregs;
  CsrFile csrs;
  PrivilegeMode _mode;
  List<int> _reservationSet;
  bool idle;

  PrivilegeMode get mode => _mode;

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
    var state = RiverCoreEmulatorState(pc, instr, this);
    state = _innerExecute(state, op);
    return state;
  }

  int trap(int pc, TrapException e) {
    csrs[CsrAddress.mcause.address].write(this, e.trap.mcause);
    csrs[CsrAddress.mepc.address].write(this, pc);
    csrs[CsrAddress.mtval.address].write(this, e.tval ?? 0);

    return csrs[CsrAddress.mtvec.address].read(this);
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
    final phys = translate(addr, MemoryAccess.read);

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
    for (final mop in op.microcode) {
      if (mop is WriteRegisterMicroOp) {
        final value = state.readSource(mop.source);
        final reg = Register.values[state.readField(mop.field)];
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
        state.pc = trap(state.pc, TrapException(mop.kind));
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

          var state = RiverCoreEmulatorState(pc, ir, this);
          state = _innerExecute(state, op);
          return state.pc;
        }
      }
    }

    return trap(pc, TrapException.illegalInstruction());
  }

  int runPipeline(int pc) {
    if (idle) return pc;

    try {
      int instr = fetch(pc);
      return cycle(pc, instr);
    } on TrapException catch (e) {
      return trap(pc, e);
    }
  }

  @override
  String toString() =>
      'RiverCoreEmulator(xregs: $xregs, mmu: $mmu, csrs: ${csrs.toStringWithCore(this)}, mode: $mode)';
}
