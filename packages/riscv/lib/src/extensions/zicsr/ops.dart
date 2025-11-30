import '../../ops.dart';
import '../../riscv_isa_base.dart';
import 'decode.dart';
import 'isa.dart';

/// 32-bit Zicsr extension
///
/// {@category extensions}
const rv32Zicsr = RiscVExtension(
  [
    Operation<SystemIType>(
      mnemonic: 'csrrw',
      opcode: 0x73,
      funct3: 0x1,
      struct: SystemIType.STRUCT,
      constructor: SystemIType.map,
      microcode: [
        ReadRegisterMicroOp(MicroOpField.rs1),
        ReadCsrMicroOp(MicroOpField.imm),
        WriteRegisterMicroOp(MicroOpField.rd, MicroOpSource.imm),
        ModifyLatchMicroOp(MicroOpField.imm, MicroOpSource.imm, false),
        WriteCsrMicroOp(MicroOpField.imm, MicroOpSource.rs1),
        UpdatePCMicroOp(MicroOpField.pc, offset: 4),
      ],
    ),
    Operation<SystemIType>(
      mnemonic: 'csrrs',
      opcode: 0x73,
      funct3: 0x2,
      struct: SystemIType.STRUCT,
      constructor: SystemIType.map,
      microcode: [
        ReadCsrMicroOp(MicroOpField.imm),
        WriteRegisterMicroOp(MicroOpField.rd, MicroOpSource.imm),
        ReadRegisterMicroOp(MicroOpField.rs1),
        AluMicroOp(MicroOpAluFunct.or, MicroOpField.imm, MicroOpField.rs1),
        ModifyLatchMicroOp(MicroOpField.imm, MicroOpSource.imm, false),
        WriteCsrMicroOp(MicroOpField.imm, MicroOpSource.alu),
        UpdatePCMicroOp(MicroOpField.pc, offset: 4),
      ],
    ),
    Operation<SystemIType>(
      mnemonic: 'csrrc',
      opcode: 0x73,
      funct3: 0x3,
      struct: SystemIType.STRUCT,
      constructor: SystemIType.map,
      microcode: [
        ReadCsrMicroOp(MicroOpField.imm),
        WriteRegisterMicroOp(MicroOpField.rd, MicroOpSource.imm),
        ReadRegisterMicroOp(MicroOpField.rs1),
        BranchIfMicroOp(MicroOpCondition.eq, MicroOpSource.rs1, offset: 2),
        AluMicroOp(MicroOpAluFunct.masked, MicroOpField.imm, MicroOpField.rs1),
        ModifyLatchMicroOp(MicroOpField.imm, MicroOpSource.imm, false),
        WriteCsrMicroOp(MicroOpField.imm, MicroOpSource.alu),
        UpdatePCMicroOp(MicroOpField.pc, offset: 4),
      ],
    ),
    Operation<SystemIType>(
      mnemonic: 'csrrwi',
      opcode: 0x73,
      funct3: 0x5,
      struct: SystemIType.STRUCT,
      constructor: SystemIType.map,
      microcode: [
        ReadCsrMicroOp(MicroOpField.imm),
        WriteRegisterMicroOp(MicroOpField.rd, MicroOpSource.imm),
        ModifyLatchMicroOp(MicroOpField.imm, MicroOpSource.imm, false),
        WriteCsrMicroOp(MicroOpField.imm, MicroOpSource.rs1),
        UpdatePCMicroOp(MicroOpField.pc, offset: 4),
      ],
    ),
    Operation<SystemIType>(
      mnemonic: 'csrrsi',
      opcode: 0x73,
      funct3: 0x6,
      struct: SystemIType.STRUCT,
      constructor: SystemIType.map,
      microcode: [
        ReadCsrMicroOp(MicroOpField.imm),
        WriteRegisterMicroOp(MicroOpField.rd, MicroOpSource.imm),
        AluMicroOp(MicroOpAluFunct.or, MicroOpField.imm, MicroOpField.rs1),
        ModifyLatchMicroOp(MicroOpField.imm, MicroOpSource.imm, false),
        WriteCsrMicroOp(MicroOpField.imm, MicroOpSource.alu),
        UpdatePCMicroOp(MicroOpField.pc, offset: 4),
      ],
    ),
    Operation<SystemIType>(
      mnemonic: 'csrrci',
      opcode: 0x73,
      funct3: 0x7,
      struct: SystemIType.STRUCT,
      constructor: SystemIType.map,
      microcode: [
        ReadCsrMicroOp(MicroOpField.imm),
        WriteRegisterMicroOp(MicroOpField.rd, MicroOpSource.imm),
        AluMicroOp(MicroOpAluFunct.masked, MicroOpField.imm, MicroOpField.rs1),
        ModifyLatchMicroOp(MicroOpField.imm, MicroOpSource.imm, false),
        WriteCsrMicroOp(MicroOpField.imm, MicroOpSource.alu),
        UpdatePCMicroOp(MicroOpField.pc, offset: 4),
      ],
    ),
  ],
  name: 'Zicsr',
  key: '_zicsr',
);
