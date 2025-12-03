import 'package:riscv/riscv.dart';
import '../../devices/uart.dart';
import '../../core/v1.dart';
import '../../../interconnect/base.dart';
import '../../../interconnect/wishbone.dart';
import '../../../bus.dart';
import '../../../cache.dart';
import '../../../clock.dart';
import '../../../dev.dart';
import '../../../mem.dart';
import '../../../river_base.dart';

/// Stream V1 SoC
///
/// The Stream V1 SoC is a lightweight SoC designed to run on small FPGAs.
/// It is suitable for light embedded applications like LED controllers.
///
/// The SoC has a single RC1.n core (RV32IC) on a wishbone interconnect.
/// It has a boot ROM, SRAM, UART, GPIO, a timer, and flash.
class StreamV1SoC extends RiverSoC {
  final ClockDomainConfig sysclk;
  final ClockDomainConfig lfclk;
  final int flashSize;
  final int sramSize;
  final CacheAccessorMethod l1Method;
  final int l1Size;
  final int l1iSize;
  final int l1dSize;

  @override
  List<Device> get devices => [
    Device.simple(
      name: 'bootrom',
      compatible: 'river,bootrom',
      range: BusAddressRange(0x00010000, l1iSize),
      fields: const {0: DeviceField('data', 4)},
      type: DeviceAccessorType.memory,
      clock: sysclk.clock,
    ),
    Device.simple(
      name: 'clint',
      compatible: 'riscv,clint0',
      range: const BusAddressRange(0x02000000, 0x00010000),
      fields: const {
        0x0000: DeviceField('msip', 4),
        0x4000: DeviceField('mtimecmp', 8),
        0xBFF8: DeviceField('mtime', 8),
      },
      type: DeviceAccessorType.io,
      clock: sysclk.clock,
    ),
    Device.simple(
      name: 'plic',
      compatible: 'riscv,plic0',
      range: const BusAddressRange(0x04000000, 0x4000000),
      fields: {
        0x000000: DeviceField('priority', 4),
        0x000100: DeviceField('pending', 4),
        0x000200: DeviceField('enable_cpu0', 4),
        0x200000: DeviceField('threshold_cpu0', 4),
        0x200004: DeviceField('claim_cpu0', 4),
      },
      type: DeviceAccessorType.io,
      clock: sysclk.clock,
    ),
    RiverUart(name: 'uart0', address: 0x10000000, clock: sysclk.clock),
    Device.simple(
      name: 'gpio',
      compatible: 'river,gpio',
      interrupts: const [2],
      range: const BusAddressRange(0x10001000, 0x00001000),
      fields: const {
        0: DeviceField('input', 4),
        1: DeviceField('output', 4),
        2: DeviceField('dir', 4),
      },
      type: DeviceAccessorType.io,
      clock: sysclk.clock,
    ),
    Device.simple(
      name: 'l1cache',
      compatible: 'river,cache',
      range: BusAddressRange(0x10004000, l1Size),
      fields: const {
        0: DeviceField('ctrl', 4),
        1: DeviceField('status', 4),
        2: DeviceField('flush', 4),
      },
      type: DeviceAccessorType.io,
      clock: sysclk.clock,
    ),
    Device.simple(
      name: 'flash',
      compatible: 'river,flash',
      range: BusAddressRange(0x20000000, flashSize),
      type: DeviceAccessorType.memory,
      fields: const {0: DeviceField('read', 4)},
    ),
    Device.simple(
      name: 'sram',
      compatible: 'river,sram',
      range: BusAddressRange(0x80000000, sramSize),
      fields: const {0: DeviceField('data', 4)},
      type: DeviceAccessorType.memory,
      clock: sysclk.clock,
    ),
  ];

  @override
  List<BusClientPort> get clients =>
      devices.map((dev) => dev.clientPort).nonNulls.toList();

  @override
  List<RiverCore> get cores => [
    RiverCoreV1.nano(
      interrupts: const [
        InterruptController(
          name: '/cpu0/interrupts',
          baseAddr: 0x0C000000,
          lines: interrupts,
        ),
      ],
      mmu: Mmu(mxlen: Mxlen.mxlen_32, blocks: mmap),
      clock: sysclk.clock,
      l1cache: L1Cache.split(
        accessor: CacheAccessor(
          clientPort: devices
              .firstWhere((dev) => dev.name == 'l1cache')
              .clientPort!,
          method: l1Method,
        ),
        iSize: l1iSize,
        dSize: l1dSize,
        ways: 4,
        lineSize: 64,
      ),
      resetVector: 0x00010000,
    ),
  ];

  @override
  Interconnect get fabric => WishboneFabric(
    arbitration: BusArbitration.priority,
    hosts: const [BusHostPort('/cpu0')],
    clients: clients,
  );

  @override
  List<ClockDomain> get clocks => [
    sysclk.getDomain(
      consumers: [
        '/cpu0',
        ...devices
            .where((dev) => dev.clock?.name == sysclk.name)
            .map((dev) => dev.name)
            .toList(),
      ],
    ),
    lfclk.getDomain(
      consumers: devices
          .where((dev) => dev.clock?.name == lfclk.name)
          .map((dev) => dev.name)
          .toList(),
    ),
  ];

  List<MemoryBlock> get mmap =>
      devices.map((dev) => dev.mmap).nonNulls.toList();

  const StreamV1SoC({
    required this.sysclk,
    required this.lfclk,
    required this.flashSize,
    required this.sramSize,
    required this.l1Method,
    required this.l1iSize,
    required this.l1dSize,
  }) : l1Size = l1iSize + l1dSize;

  /// Stream V1 SoC configured for the iCESugar
  const StreamV1SoC.icesugar({
    this.l1Method = CacheAccessorMethod.bus,
    this.l1iSize = 0x10000,
    this.l1dSize = 0x10000,
  }) : sysclk = const ClockDomainConfig(
         name: 'sysclk',
         freqHz: 48e6,
         divisors: const [1, 2, 4, 8],
       ),
       lfclk = const ClockDomainConfig(
         name: 'lfclk',
         freqHz: 10e3,
         divisors: const [1, 2, 4, 8],
       ),
       flashSize = 0x01000000,
       sramSize = 0x100000,
       l1Size = 0x20000;

  static const List<InterruptLine> interrupts = [
    InterruptLine(irq: 1, source: '/uart0', target: '/cpu0'),
    InterruptLine(irq: 2, source: '/gpio', target: '/cpu0'),
  ];

  static StreamV1SoC? configure(Map<String, dynamic> options) {
    final l1Method = CacheAccessorMethod.from(options['l1Method']);
    final l1iSize = options['l1iSize'] as int?;
    final l1dSize = options['l1dSize'] as int?;

    if (options.containsKey('platform')) {
      switch (options['platform']) {
        case 'icesugar':
          return StreamV1SoC.icesugar(
            l1Method: l1Method ?? CacheAccessorMethod.bus,
            l1iSize: l1iSize ?? 0x10000,
            l1dSize: l1dSize ?? 0x10000,
          );
        default:
          return null;
      }
    }

    final sysclk =
        ClockDomainConfig.from(options['sysclk'] ?? (throw 'Missing sysclk')) ??
        (throw 'Invalid sysclk');
    final lfclk =
        ClockDomainConfig.from(options['lfclk'] ?? (throw 'Missing lfclk')) ??
        (throw 'Invalid lfclk');
    final flashSize =
        (options['flashSize'] ?? (throw 'Missing flash size')) as int;
    final sramSize =
        (options['sramSize'] ?? (throw 'Missing SRAM size')) as int;

    return StreamV1SoC(
      sysclk: sysclk,
      lfclk: lfclk,
      flashSize: flashSize,
      sramSize: sramSize,
      l1Method: l1Method ?? (throw 'Missing l1 access method'),
      l1iSize: l1iSize ?? (throw 'Missing l1i size'),
      l1dSize: l1dSize ?? (throw 'Missing l1d size'),
    );
  }
}
