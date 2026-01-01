import 'package:riscv/riscv.dart';
import 'package:river/river.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd_hcl/rohd_hcl.dart';

class MmuHDL extends Module {
  final Mmu config;

  MmuHDL(
    Logic clk,
    Logic reset,
    List<(MemoryAccess, DataPortInterface)> memWritePorts,
    List<(MemoryAccess, DataPortInterface)> memReadPorts, {
    required this.config,
    Logic? privilegeMode,
    Logic? enableSum,
    Logic? enableMxr,
    Logic? pagingMode,
    Logic? pageTableAddress,
    Logic? fence,
    Map<MemoryBlock, (DataPortInterface, DataPortInterface)> devices = const {},
    super.name = 'river_mmu',
  }) {
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);

    memWritePorts = memWritePorts.indexed
        .map(
          (e) => (
            e.$2.$1,
            e.$2.$2.clone()..connectIO(
              this,
              e.$2.$2,
              outputTags: {DataPortGroup.integrity},
              inputTags: {DataPortGroup.control, DataPortGroup.data},
              uniquify: (og) => 'memWrite${e.$1}_$og',
            ),
          ),
        )
        .toList();

    memReadPorts = memReadPorts.indexed
        .map(
          (e) => (
            e.$2.$1,
            e.$2.$2.clone()..connectIO(
              this,
              e.$2.$2,
              outputTags: {DataPortGroup.data, DataPortGroup.integrity},
              inputTags: {DataPortGroup.control},
              uniquify: (og) => 'memRead${e.$1}_$og',
            ),
          ),
        )
        .toList();

    devices = Map.fromEntries(
      devices.entries.indexed.map((e) {
        final index = e.$1;
        final mmap = e.$2.key;
        final devReadPort = e.$2.value.$1;
        final devWritePort = e.$2.value.$2;
        return MapEntry(mmap, (
          devReadPort.clone()..connectIO(
            this,
            devReadPort,
            outputTags: {DataPortGroup.control},
            inputTags: {DataPortGroup.data, DataPortGroup.integrity},
            uniquify: (og) => 'devRead${index}_$og',
          ),
          devWritePort.clone()..connectIO(
            this,
            devWritePort,
            outputTags: {DataPortGroup.control, DataPortGroup.data},
            inputTags: {DataPortGroup.integrity},
            uniquify: (og) => 'devWrite${index}_$og',
          ),
        ));
      }),
    );

    if (privilegeMode != null)
      privilegeMode = addInput('privilegeMode', privilegeMode!, width: 3);

    if (fence != null) fence = addInput('fence', fence!);

    if (config.hasSum) {
      assert(enableSum != null, 'SUM is enabled in the MMU but not wired up.');
      enableSum = addInput('enableSum', enableSum!);
    }

    if (config.hasMxr) {
      assert(enableMxr != null, 'MXR is enabled in the MMU but not wired up.');
      enableMxr = addInput('enableMxr', enableMxr!);
    }

    List<Conditional> pagingReset = [];
    List<Conditional> pagingCycle = [];

    final devReadBusy = Logic(name: 'devReadBusy');
    final devReadClaim = Logic(
      name: 'devReadClaim',
      width: (devices.length + 1).bitLength,
    );
    final devReadDone = Logic(name: 'devReadDone');
    final devReadValid = Logic(name: 'devReadValid');
    final devReadEnable = Logic(name: 'devReadEnable');
    final devReadAddr = Logic(name: 'devReadAddr', width: config.mxlen.size);
    final devReadData = Logic(name: 'devReadData', width: config.mxlen.size);

    final devWriteBusy = Logic(name: 'devWriteBusy');
    final devWriteClaim = Logic(
      name: 'devWriteClaim',
      width: (devices.length + 1).bitLength,
    );
    final devWriteDone = Logic(name: 'devWriteDone');
    final devWriteValid = Logic(name: 'devWriteValid');
    final devWriteEnable = Logic(name: 'devWriteEnable');
    final devWriteAddr = Logic(name: 'devWriteAddr', width: config.mxlen.size);
    final devWriteData = Logic(name: 'devWriteData', width: config.mxlen.size);

    final ptwEnable = Logic(name: 'ptwEnable');
    final ptwDone = Logic(name: 'ptwDone');
    final ptwValid = Logic(name: 'ptwValid');
    final ptwAccess = Logic(name: 'ptwAccess', width: 3);
    final ptwPaddr = Logic(name: 'ptwPaddr', width: config.mxlen.size);
    final ptwVaddr = Logic(name: 'ptwVaddr', width: config.mxlen.size);

    Logic needsPageTranslation = Const(0);

    if (config.hasPaging) {
      final pagingModes = PagingMode.values.where(
        (m) => m.isSupported(config.mxlen),
      );

      final maxPagingLevel = pagingModes
          .map((m) => m.levels)
          .fold(0, (a, b) => a > b ? a : b);

      final maxModeId = pagingModes
          .map((m) => m.id)
          .fold<int>(0, (a, b) => a > b ? a : b);
      final pagingModeWidth = maxModeId.bitLength == 0
          ? 1
          : maxModeId.bitLength;

      assert(
        pagingMode != null,
        'Paging is enabled but missing paging mode input',
      );
      pagingMode = addInput('pagingMode', pagingMode!, width: pagingModeWidth);

      assert(
        pageTableAddress != null,
        'Paging is enabled but missing page table address input',
      );
      pageTableAddress = addInput(
        'pageTableAddress',
        pageTableAddress!,
        width: config.mxlen.size,
      );

      needsPageTranslation = pagingMode!
          .gt(Const(PagingMode.bare.id, width: pagingMode!.width))
          .named('needsPageTranslation');

      final ptwCycle = Logic(name: 'ptwCycle', width: maxPagingLevel.bitLength);
      final pteAddress = Logic(name: 'pteAddress', width: config.mxlen.size);
      final pte = Logic(name: 'pte', width: config.mxlen.size);
      final pteV = Logic(name: 'pteV');
      final pteR = Logic(name: 'pteR');
      final pteW = Logic(name: 'pteW');
      final pteX = Logic(name: 'pteX');
      final pteU = Logic(name: 'pteU');

      List<Logic> defineVPN(Logic addr) {
        final modes = pagingModes.toList();

        final maxVpnBits = modes
            .map((m) => m.vpnBits)
            .fold<int>(0, (a, b) => a > b ? a : b);

        Logic vpnForModeAtLevel(PagingMode m, int level) {
          if (level >= m.levels || m.levels == 0) {
            return Const(0, width: maxVpnBits);
          }

          final shift = 12 + (m.vpnBits * level);
          final shifted = addr >> Const(shift, width: addr.width);

          final mask = (1 << m.vpnBits) - 1;
          final masked = shifted & Const(mask, width: addr.width);

          final bits = masked.getRange(0, m.vpnBits - 1);

          return (m.vpnBits == maxVpnBits) ? bits : bits.zeroExtend(maxVpnBits);
        }

        return List<Logic>.generate(maxPagingLevel, (i) {
          Logic acc = Const(0, width: maxVpnBits);

          for (final m in modes.reversed) {
            final isMode = pagingMode!.eq(
              Const(m.id, width: pagingMode!.width),
            );
            final v = vpnForModeAtLevel(m, i);
            acc = mux(isMode, v.zeroExtend(acc.width), acc);
          }

          return acc;
        }).reversed.toList();
      }

      final pteBytes = pagingModes
          .fold<Logic>(Const(8, width: config.mxlen.size), (acc, m) {
            final isMode = pagingMode!.eq(
              Const(m.id, width: pagingMode!.width),
            );

            final bytes = Const(m.pteBytes, width: config.mxlen.size);

            return mux(isMode, bytes, acc);
          })
          .named('pteBytes');

      List<Logic> vpnTop = defineVPN(ptwVaddr);
      final vpnBottom = vpnTop.reversed.toList();

      pagingReset.addAll([
        ptwEnable < 0,
        ptwDone < 0,
        ptwValid < 0,
        ptwAccess < 0,
        ptwPaddr < 0,
        ptwVaddr < 0,
        ptwCycle < 0,
        pteAddress < 0,
        pte < 0,
      ]);

      Logic buildPhys(PagingMode mode, Logic pte) {
        final offset = ptwVaddr & Const(0xFFF, width: config.mxlen.size);
        Logic phys = Const(0, width: config.mxlen.size);

        for (int i = 0; i < mode.ppnBits.length; i++) {
          final fromVpn = ptwCycle.lt(mode.levels - 1 - i);
          final value = mux(
            fromVpn,
            vpnBottom[i].zeroExtend(config.mxlen.size),
            ((pte >> mode.ppnShift(i)) &
                    Const((1 << mode.ppnBits[i]) - 1, width: config.mxlen.size))
                .zeroExtend(config.mxlen.size),
          );

          phys |= value << mode.ppnPhysShift(i);
        }

        return phys | offset;
      }

      pagingCycle.addAll([
        If(
          ptwEnable,
          then: [
            Case(
              ptwCycle,
              [
                for (var i = 0; i < maxPagingLevel; i++)
                  CaseItem(Const(i, width: maxPagingLevel.bitLength), [
                    If(
                      ~devReadBusy & devReadClaim.eq(0),
                      then: [
                        if (i == 0) pteAddress < pageTableAddress,
                        devReadClaim < 1,
                        devReadBusy < 1,
                        devReadEnable < 1,
                        devReadAddr <
                            (pteAddress +
                                vpnTop[i].zeroExtend(config.mxlen.size) *
                                    pteBytes),
                      ],
                    ),
                    If(
                      devReadBusy &
                          devReadClaim.eq(1) &
                          devReadDone &
                          devReadValid,
                      then: [
                        devReadBusy < 0,
                        devReadClaim < 0,
                        devReadEnable < 0,
                        pte < devReadData,
                        pteV <
                            (devReadData &
                                Const(1, width: config.mxlen.size))[0],
                        pteR <
                            ((devReadData >> 1) &
                                Const(1, width: config.mxlen.size))[0],
                        pteW <
                            ((devReadData >> 2) &
                                Const(1, width: config.mxlen.size))[0],
                        pteX <
                            ((devReadData >> 3) &
                                Const(1, width: config.mxlen.size))[0],
                        pteU <
                            ((devReadData >> 4) &
                                Const(1, width: config.mxlen.size))[0],
                        If(
                          (pteV.eq(0) | (pteR.eq(0) & pteW.eq(1))) |
                              (privilegeMode != null
                                  ? (privilegeMode!.eq(
                                          Const(
                                            PrivilegeMode.user.id,
                                            width: 3,
                                          ),
                                        ) &
                                        pteU.eq(0))
                                  : Const(0)) |
                              (privilegeMode != null
                                  ? (privilegeMode!.eq(
                                          Const(
                                            PrivilegeMode.supervisor.id,
                                            width: 3,
                                          ),
                                        ) &
                                        pteU.eq(1) &
                                        (config.hasSum
                                            ? ~enableSum! & ~ptwAccess.eq(2)
                                            : Const(0)))
                                  : Const(0)),
                          then: [ptwDone < 1, ptwValid < 0],
                          orElse: [
                            If(
                              pteR.eq(1) | pteX.eq(1),
                              then: [
                                If(
                                  ~mux(
                                    ptwAccess.eq(0),
                                    pteR.eq(1) |
                                        (config.hasMxr
                                            ? enableMxr! & pteX.eq(1)
                                            : Const(0)),
                                    mux(
                                      ptwAccess.eq(1),
                                      pteW.eq(1),
                                      mux(
                                        ptwAccess.eq(2),
                                        pteX.eq(1),
                                        Const(0),
                                      ),
                                    ),
                                  ),
                                  then: [
                                    ptwDone < 1,
                                    ptwValid < 0,
                                    ptwPaddr < 0,
                                    ptwCycle < 0,
                                    pteAddress < 0,
                                  ],
                                  orElse: [
                                    Case(
                                      pagingMode,
                                      [
                                        for (final mode in pagingModes)
                                          CaseItem(
                                            Const(
                                              mode.id,
                                              width: pagingModeWidth,
                                            ),
                                            [
                                              ptwPaddr <
                                                  buildPhys(mode, devReadData),
                                              ptwDone < 1,
                                              ptwValid < 1,
                                            ],
                                          ),
                                      ],
                                      defaultItem: [ptwDone < 1, ptwValid < 0],
                                    ),
                                  ],
                                ),
                              ],
                              orElse: [
                                pteAddress <
                                    ((devReadData >> 10) &
                                            Const(
                                              (1 << config.mxlen.size) - 1,
                                              width: config.mxlen.size,
                                            )) <<
                                        12,
                                Case(
                                  pagingMode,
                                  [
                                    for (final mode in pagingModes)
                                      CaseItem(
                                        Const(mode.id, width: pagingModeWidth),
                                        [
                                          if (i < (mode.levels - 1)) ...[
                                            ptwCycle < (ptwCycle + 1),
                                            ptwDone < 0,
                                            ptwValid < 0,
                                          ] else ...[
                                            ptwDone < 1,
                                            ptwValid < 0,
                                            ptwPaddr < 0,
                                            ptwCycle < 0,
                                            pteAddress < 0,
                                          ],
                                        ],
                                      ),
                                  ],
                                  defaultItem: [
                                    ptwDone < 1,
                                    ptwValid < 0,
                                    ptwPaddr < 0,
                                    ptwCycle < 0,
                                    pteAddress < 0,
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ]),
              ],
              defaultItem: [
                ptwDone < 1,
                ptwValid < 0,
                ptwPaddr < 0,
                ptwCycle < 0,
                pteAddress < 0,
              ],
            ),
          ],
          orElse: [
            ptwDone < 0,
            ptwValid < 0,
            ptwPaddr < 0,
            ptwCycle < 0,
            pteAddress < 0,
            pte < 0,
          ],
        ),
      ]);
    }

    List<Iff> defineReadPort(
      MemoryAccess access,
      DataPortInterface readPort,
      int id,
    ) => [
      if (config.hasPaging)
        Iff(
          readPort.en &
              ~devReadBusy &
              devReadClaim.eq(0) &
              needsPageTranslation,
          [
            ptwEnable < 1,
            ptwVaddr < readPort.addr,
            ptwAccess <
                switch (access) {
                  MemoryAccess.instr => 2,
                  MemoryAccess.write => 1,
                  MemoryAccess.read => 0,
                },
            readPort.done < 0,
            readPort.valid < 0,
            readPort.data < 0,
            If(
              ptwDone & ptwValid,
              then: [
                ptwEnable < 0,
                devReadBusy < 1,
                devReadEnable < 1,
                devReadClaim < id,
                devReadAddr < ptwPaddr,
              ],
            ),
            If(
              ptwDone & ~ptwValid,
              then: [ptwEnable < 0, readPort.done < 1, readPort.valid < 0],
            ),
          ],
        ),
      Iff(
        readPort.en & ~devReadBusy & devReadClaim.eq(0) & ~needsPageTranslation,
        [
          devReadEnable < 1,
          devReadBusy < 1,
          devReadClaim < id,
          devReadAddr < readPort.addr,
          readPort.done < 0,
          readPort.valid < 0,
          readPort.data < 0,
        ],
      ),
      Iff(readPort.en & devReadBusy & devReadClaim.eq(id) & devReadDone, [
        readPort.done < devReadDone,
        readPort.valid < devReadValid,
        readPort.data < devReadData,
      ]),
      Iff(devReadBusy & devReadClaim.eq(id) & (~readPort.en | devReadDone), [
        readPort.done < 0,
        readPort.valid < 0,
        readPort.data < 0,
        devReadBusy < 0,
        devReadClaim < 0,
        devReadEnable < 0,
      ]),
      ElseIf(devReadBusy & devReadClaim.eq(id), [
        readPort.done < 0,
        readPort.valid < 0,
        readPort.data < 0,
      ]),
    ];

    List<Iff> defineWritePort(
      MemoryAccess access,
      DataPortInterface writePort,
      int id,
    ) => [
      if (config.hasPaging)
        Iff(
          writePort.en &
              ~devWriteBusy &
              devWriteClaim.eq(0) &
              needsPageTranslation,
          [
            ptwEnable < 1,
            ptwAccess <
                switch (access) {
                  MemoryAccess.instr => 2,
                  MemoryAccess.write => 1,
                  MemoryAccess.read => 0,
                },
            ptwVaddr < writePort.addr,
            If(
              ptwDone & ptwValid,
              then: [
                ptwEnable < 0,
                devWriteEnable < 1,
                devWriteBusy < 1,
                devWriteClaim < id,
                devWriteAddr < ptwPaddr,
              ],
            ),
            If(
              ptwDone & ~ptwValid,
              then: [ptwEnable < 0, writePort.done < 1, writePort.valid < 0],
            ),
          ],
        ),
      Iff(
        writePort.en &
            ~devWriteBusy &
            devWriteClaim.eq(0) &
            ~needsPageTranslation,
        [
          devWriteEnable < 1,
          devWriteBusy < 1,
          devWriteClaim < id,
          devWriteAddr < writePort.addr,
          devWriteData < writePort.data,
        ],
      ),
      Iff(devWriteBusy & devWriteClaim.eq(id), [
        writePort.done < devWriteDone,
        writePort.valid < devWriteValid,
        If(
          devWriteDone & ~writePort.en,
          then: [devWriteBusy < 0, devWriteClaim < 0, devWriteEnable < 0],
        ),
      ]),
    ];

    Sequential(clk, [
      If(
        reset,
        then: [
          for (final memReadPort in memReadPorts) ...[
            memReadPort.$2.done < 0,
            memReadPort.$2.valid < 0,
            memReadPort.$2.data < 0,
          ],
          for (final memWritePort in memWritePorts) ...[
            memWritePort.$2.done < 0,
            memWritePort.$2.valid < 0,
          ],
          for (final dev in devices.values) ...[
            dev.$1.en < 0,
            dev.$1.addr < 0,
            dev.$2.en < 0,
            dev.$2.addr < 0,
          ],
          devReadBusy < 0,
          devReadEnable < 0,
          devReadDone < 0,
          devReadValid < 0,
          devReadClaim < 0,
          devWriteBusy < 0,
          devWriteEnable < 0,
          devWriteDone < 0,
          devWriteClaim < 0,
          ...pagingReset,
        ],
        orElse: [
          ...pagingCycle,
          for (final memPort in [
            ...memReadPorts,
            ...memWritePorts,
          ].map((e) => e.$2))
            If(~memPort.en, then: [memPort.done < 0, memPort.valid < 0]),
          If.block([
            for (final memReadPort in memReadPorts.indexed)
              ...defineReadPort(
                memReadPort.$2.$1,
                memReadPort.$2.$2,
                memReadPort.$1 + 2,
              ),
            for (final memWritePort in memWritePorts.indexed)
              ...defineWritePort(
                memWritePort.$2.$1,
                memWritePort.$2.$2,
                memWritePort.$1 + 2,
              ),
          ]),
          If(
            devReadEnable,
            then: [
              if (devices.isEmpty) ...[
                devReadDone < 1,
                devReadData < 0,
                devReadValid < 0,
              ] else
                If.block([
                  for (final dev in devices.entries)
                    Iff(
                      devReadAddr.gte(dev.key.start) &
                          devReadAddr.lt(dev.key.end),
                      [
                        dev.value.$1.en < devReadBusy,
                        dev.value.$1.addr <
                            (devReadAddr -
                                    Const(
                                      dev.key.start,
                                      width: config.mxlen.size,
                                    ))
                                .slice(dev.value.$1.addr.width - 1, 0),
                        devReadData <
                            dev.value.$1.data.zeroExtend(config.mxlen.size),
                        devReadDone < dev.value.$1.done,
                        devReadValid < dev.value.$1.valid,
                      ],
                    ),
                  Else([devReadDone < 1, devReadData < 0, devReadValid < 0]),
                ]),
            ],
            orElse: [devReadDone < 0, devReadData < 0, devReadValid < 0],
          ),
          If(
            devWriteEnable,
            then: [
              if (devices.isEmpty) ...[
                devWriteDone < 1,
                devWriteValid < 0,
              ] else
                If.block([
                  for (final dev in devices.entries)
                    Iff(
                      devWriteAddr.gte(dev.key.start) &
                          devWriteAddr.lt(dev.key.end),
                      [
                        dev.value.$2.en < devWriteBusy,
                        dev.value.$2.addr <
                            (devWriteAddr -
                                    Const(
                                      dev.key.start,
                                      width: config.mxlen.size,
                                    ))
                                .slice(dev.value.$2.addr.width - 1, 0),
                        dev.value.$2.data <
                            devWriteData.slice(dev.value.$2.data.width - 1, 0),
                        devWriteDone < dev.value.$2.done,
                        devWriteValid < dev.value.$2.valid,
                        If(dev.value.$2.done, then: [dev.value.$2.en < 0]),
                      ],
                    ),
                  Else([devWriteDone < 1, devWriteValid < 0]),
                ]),
            ],
            orElse: [devWriteDone < 0, devWriteValid < 0],
          ),
        ],
      ),
    ]);
  }
}
