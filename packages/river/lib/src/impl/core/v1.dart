import 'package:riscv/riscv.dart';
import '../../clock.dart';
import '../../mem.dart';
import '../../river_base.dart';

/// RC1 - River Core V1
class RiverCoreV1 extends RiverCore {
  /// RC1.n - River Core V1 nano
  ///
  /// A RV32IC core using the River design.
  const RiverCoreV1.nano({
    super.vendorId = 0,
    super.archId = 0,
    super.hartId = 0,
    super.resetVector = 0,
    required super.mmu,
    required super.interrupts,
    required super.clock,
    super.l1cache,
  }) : super(
         mxlen: Mxlen.mxlen_32,
         extensions: const [rvc, rv32i],
         hasSupervisor: false,
         hasUser: false,
       );

  /// RC1.mi - River Core V1 micro
  ///
  /// A RV32IMAC core using the River design.
  const RiverCoreV1.micro({
    super.vendorId = 0,
    super.archId = 0,
    super.hartId = 0,
    super.resetVector = 0,
    required super.mmu,
    required super.interrupts,
    required super.clock,
    super.l1cache,
  }) : super(
         mxlen: Mxlen.mxlen_32,
         extensions: const [
           rvc,
           rv32Zicsr,
           rv32BasePrivilege,
           rv32M,
           rv32Atomics,
           rv32i,
         ],
       );

  /// RC1.s - River Core V1 small
  ///
  /// A RV64IMAC core using the River design.
  const RiverCoreV1.small({
    super.vendorId = 0,
    super.archId = 0,
    super.hartId = 0,
    super.resetVector = 0,
    required super.mmu,
    required super.interrupts,
    required super.clock,
    super.l1cache,
  }) : super(
         mxlen: Mxlen.mxlen_64,
         extensions: const [
           rvc,
           rv32Zicsr,
           rv32BasePrivilege,
           rv32M,
           rv64M,
           rv32Atomics,
           rv64Atomics,
           rv32i,
         ],
       );
}
