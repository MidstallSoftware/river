import 'dart:io' show Platform;

import 'package:args/args.dart';
import 'package:path/path.dart' as path;
import 'package:river/river.dart';
import 'package:river_emulator/river_emulator.dart';

void main(List<String> arguments) {
  var parser = ArgParser();
  parser.addOption(
    'soc',
    help: 'Sets the SoC to emulate',
    allowed: RiverSoCChoice.values.map((v) => v.name).toList(),
  );

  parser.addMultiOption(
    'soc-option',
    help: 'Adds an option when configuring the SoC',
    splitCommas: false,
  );

  parser.addOption(
    'platform',
    help: 'Sets the platform to emulate',
    allowed: RiverPlatformChoice.values.map((v) => v.name).toList(),
  );

  parser.addFlag('help', help: 'Prints the usage');

  final args = parser.parse(arguments);

  if (args.flag('help')) {
    print('Usage: ${path.basename(Platform.script.toFilePath())}');
    print('');
    print('Options:');
    print(parser.usage);
    return;
  }

  RiverPlatformChoice? platformChoice;
  RiverSoCChoice? socChoice;

  if (args.option('platform') == null && args.option('soc') == null) {
    print('Missing platform or soc option');
    return;
  } else if (args.option('platform') != null && args.option('soc') == null) {
    platformChoice = RiverPlatformChoice.getChoice(args.option('platform')!);

    if (platformChoice == null) {
      print('Invalid argument for platform option');
      return;
    }

    socChoice = platformChoice!.soc;
  } else if (args.option('platform') == null && args.option('soc') != null) {
    socChoice = RiverSoCChoice.getChoice(args.option('soc')!);

    if (socChoice == null) {
      print('Invalid argument for soc option');
      return;
    }
  } else {
    platformChoice = RiverPlatformChoice.getChoice(args.option('platform')!);
    socChoice = RiverSoCChoice.getChoice(args.option('soc')!);

    if (platformChoice?.soc != socChoice) {
      print(
        "Platform's SoC and the value given for \"--soc\" do not align, unable to handle...",
      );
      return;
    }
  }

  if (platformChoice == null) {
    print('Platform is not set, unable to handle...');
    return;
  }

  final platform = platformChoice ?? (throw 'Bad state, platform is not set');
  final soc = socChoice ?? (throw 'Bad state, soc is not set');

  final socConfig =
      soc.configure({
        ...Map.fromEntries(
          args.multiOption('soc-option').map((entry) {
            final i = entry.indexOf('=');
            assert(i > 0);
            return MapEntry(entry.substring(0, i), entry.substring(i + 1));
          }),
        ),
        'platform': platform.name,
      }) ??
      (throw 'Invalid platform configuration');

  final emulator = RiverEmulator(soc: RiverSoCEmulator(socConfig));
  emulator.reset();

  Map<int, int> pcs = {};
  while (true) {
    pcs = emulator.soc.run(pcs);
  }
}
