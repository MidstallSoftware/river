import 'dart:io' show Platform, File;

import 'package:args/args.dart';
import 'package:path/path.dart' as path;
import 'package:river/river.dart';
import 'package:river_hdl/river_hdl.dart';

Future<void> main(List<String> arguments) async {
  var parser = ArgParser();
  parser.addOption(
    'soc',
    help: 'Sets the SoC to generate',
    allowed: RiverSoCChoice.values.map((v) => v.name).toList(),
  );

  parser.addMultiOption(
    'soc-option',
    help: 'Adds an option when configuring the SoC',
    splitCommas: false,
  );

  parser.addOption(
    'platform',
    help: 'Sets the platform to generate',
    allowed: RiverPlatformChoice.values.map((v) => v.name).toList(),
  );

  parser.addOption(
    'output',
    help: 'Sets the output path to generate the SystemVerilog to',
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
      return Future.value();
    }
  } else {
    platformChoice = RiverPlatformChoice.getChoice(args.option('platform')!);
    socChoice = RiverSoCChoice.getChoice(args.option('soc')!);

    if (platformChoice?.soc != socChoice) {
      print(
        "Platform's SoC and the value given for \"--soc\" do not align, unable to handle...",
      );
      return Future.value();
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

  final ip = RiverSoCIP(socConfig);

  await ip.buildAndGenerateRTL(outputPath: args.option('output') ?? 'output');
}
