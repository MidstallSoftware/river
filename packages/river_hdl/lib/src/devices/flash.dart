import 'package:rohd/rohd.dart';
import 'package:rohd_hcl/rohd_hcl.dart';
import 'package:riscv/riscv.dart';
import 'package:river/river.dart';
import '../dev.dart';

class RiverFlashModule extends DeviceModule {
  RiverFlashModule(super.mxlen, super.config);

  @override
  List<Conditional> read(Logic addr, Logic data, Logic done, Logic valid) => [
    data < 0,
    done < 1,
    valid < 0,
  ];

  @override
  List<Conditional> write(Logic addr, Logic data, Logic done, Logic valid) => [
    done < 1,
    valid < 0,
  ];

  static DeviceModule create(
    Mxlen mxlen,
    Device config,
    Map<String, String> _options,
  ) => RiverFlashModule(mxlen, config);
}
