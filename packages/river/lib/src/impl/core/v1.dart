import 'package:riscv/riscv.dart';
import '../../clock.dart';
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
    required super.interrupts,
    required super.mmu,
    required super.clock,
    super.l1cache,
  }) : super(mxlen: Mxlen.mxlen_32, extensions: const [rv32i, rvc]);
}
