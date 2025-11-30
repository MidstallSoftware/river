import 'helpers.dart';
import 'riscv_isa_base.dart';
import 'riscv_isa_decode.dart';
import 'ops.dart';

class SystemType extends InstructionType {
  final int rd;
  final int rs1;

  const SystemType({
    required super.opcode,
    required this.rd,
    required super.funct3,
    required this.rs1,
    required super.funct12,
  });

  const SystemType.map(Map<String, int> map)
    : rd = map['rd']!,
      rs1 = map['rs1']!,
      super.map(map);

  @override
  int get imm => funct12!;

  @override
  Map<String, int> toMap() => {
    'opcode': opcode,
    'rd': rd,
    'funct3': funct3!,
    'rs1': rs1,
    'funct12': funct12!,
  };

  @override
  String toString() =>
      'SystemType(opcode: $opcode, rd: $rd, funct3: $funct3, rs1: $rs1, funct12: $funct12)';

  static const BitStruct STRUCT = BitStruct({
    'opcode': Instruction.opcodeRange,
    'rd': BitRange(7, 11),
    'funct3': BitRange(12, 14),
    'rs1': BitRange(15, 19),
    'funct12': BitRange(20, 31),
  });

  static SystemType decode(int instr) =>
      SystemType.map(SystemType.STRUCT.decode(instr));
}

/// 32-bit base privilege extension
///
/// {@category extensions}
const rv32BasePrivilege = RiscVExtension([
  Operation<SystemType>(
    mnemonic: 'mret',
    opcode: 0x73,
    funct3: 0x0,
    funct12: 0x302,
    struct: SystemType.STRUCT,
    constructor: SystemType.map,
    allowedLevels: [PrivilegeMode.machine],
    microcode: [ReturnMicroOp(PrivilegeMode.machine)],
  ),
  Operation<SystemType>(
    mnemonic: 'sret',
    opcode: 0x73,
    funct3: 0x0,
    funct12: 0x102,
    struct: SystemType.STRUCT,
    constructor: SystemType.map,
    allowedLevels: [PrivilegeMode.supervisor, PrivilegeMode.machine],
    microcode: [ReturnMicroOp(PrivilegeMode.supervisor)],
  ),
  Operation<SystemType>(
    mnemonic: 'wfi',
    opcode: 0x73,
    funct3: 0x0,
    funct7: 0x08,
    struct: SystemType.STRUCT,
    constructor: SystemType.map,
    microcode: [
      const InterruptHoldMicroOp(),
      UpdatePCMicroOp(MicroOpField.pc, offset: 4),
    ],
  ),
  Operation<SType>(
    mnemonic: 'sfence.vma',
    opcode: 0x73,
    funct3: 0x1,
    struct: SType.STRUCT,
    constructor: SType.map,
    allowedLevels: [PrivilegeMode.supervisor, PrivilegeMode.machine],
    microcode: [
      ReadRegisterMicroOp(MicroOpField.rs1),
      ReadRegisterMicroOp(MicroOpField.rs2),
      TlbFenceMicroOp(),
      TlbInvalidateMicroOp(
        addrField: MicroOpField.rs1,
        asidField: MicroOpField.rs2,
      ),
      UpdatePCMicroOp(MicroOpField.pc, offset: 4),
    ],
  ),
]);
