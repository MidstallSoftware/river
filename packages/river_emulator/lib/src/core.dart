import 'package:riscv/riscv.dart';
import 'package:river/river.dart';

class RiverCoreEmulatorState {
  int? _rs1;
  int? _rs2;
  int? _rd;
  int? _imm;

  InstructionType ir;
  RiverCoreEmulator core;

  RiverCoreEmulatorState(this.ir, this.core) : alu = 0;

  int alu;
  int get rs1 => _rs1 ?? ir.toMap()['rs1'] ?? 0;
  int get rs2 => _rs2 ?? ir.toMap()['rs2'] ?? 0;
  int get rd => _rd ?? ir.toMap()['rd'] ?? 0;
  int get imm => _imm ?? ir.imm;

  int readSource(MicroOpSource source) {
    switch (source) {
      case MicroOpSource.imm:
        return ir.imm;
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
        return core.pc;
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
      'RiverCoreEmulatorState($ir, rd: $rd, rs1: $rs1, rs2: $rs2, imm: $imm, alu: $alu)';
}

class RiverCoreEmulator {
  final RiverCore config;

  int pc;
  RiverCoreEmulatorState? state;
  Map<Register, int> xregs;

  RiverCoreEmulator(this.config) : pc = 0, state = null, xregs = {};

  void reset() {
    xregs = {};
    pc = config.resetVector;
    state = null;
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

  void execute(InstructionType instr) {
    final op = findOperationByInstruction(instr)!;
    state = RiverCoreEmulatorState(instr, this);
    _innerExecute(op);
  }

  void _innerExecute(Operation op) {
    assert(state != null);

    for (final mop in op.microcode) {
      if (mop is WriteRegisterMicroOp) {
        final value = state!.readSource(mop.source);
        final reg = Register.values[state!.readField(mop.field)];
        xregs[reg] = value;
      } else if (mop is ReadRegisterMicroOp) {
        final reg = Register.values[state!.readField(mop.source)];
        final value = xregs[reg] ?? 0;
        state!.writeField(mop.source, value);
      } else if (mop is AluMicroOp) {
        final a = state!.readField(mop.a);
        final b = state!.readField(mop.b);
        switch (mop.funct) {
          case MicroOpAluFunct.add:
            state!.alu = a + b;
            break;
          case MicroOpAluFunct.sub:
            state!.alu = a - b;
            break;
          case MicroOpAluFunct.mul:
            state!.alu = a * b;
            break;
          case MicroOpAluFunct.and:
            state!.alu = a & b;
            break;
          case MicroOpAluFunct.or:
            state!.alu = a | b;
            break;
          case MicroOpAluFunct.xor:
            state!.alu = a ^ b;
            break;
          case MicroOpAluFunct.sll:
            state!.alu = a << b;
            break;
          case MicroOpAluFunct.srl:
            state!.alu = a >> b;
            break;
          case MicroOpAluFunct.slt:
            state!.alu = a <= b ? 1 : 0;
            break;
          case MicroOpAluFunct.sltu:
            state!.alu =
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
            ? state!.readField(mop.offsetField!)
            : mop.offset;
        pc += value;
      } else {
        throw 'Invalid micro-op $mop';
      }
    }
  }

  bool cycle(int instr) {
    for (final ext in config.extensions) {
      for (final op in ext.operations) {
        if (op.checkOpcode(instr)) {
          InstructionType? ir;
          try {
            ir = op.decode(instr);
          } on DecodeException catch (exception) {
            print(exception);
            continue;
          }

          state = RiverCoreEmulatorState(ir, this);

          _innerExecute(op);
          return true;
        }
      }
    }

    return false;
  }

  @override
  String toString() => 'RiverCoreEmulator(pc: $pc, xregs: $xregs)';
}
