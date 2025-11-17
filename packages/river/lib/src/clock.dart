class ClockConfig {
  final String name;
  final double baseFreqHz;
  final List<double> divisors;

  const ClockConfig({
    required this.name,
    required this.baseFreqHz,
    this.divisors = const [],
  });

  double frequencyForDivisor(double divisor) => baseFreqHz / divisor;

  @override
  String toString() =>
      'ClockConfig(name: $name, baseFreqHz: $baseFreqHz, divisors: $divisors)';
}

class ClockDomainConfig {
  final String name;
  final String? source;
  final double freqHz;
  final double? divider;
  final List<double> divisors;

  const ClockDomainConfig({
    required this.name,
    required this.freqHz,
    this.source,
    this.divider,
    this.divisors = const [],
  });

  ClockConfig get clock =>
      ClockConfig(name: name, baseFreqHz: freqHz, divisors: divisors);

  ClockDomain getDomain({List<String> consumers = const []}) => ClockDomain(
    name: name,
    source: source,
    freqHz: freqHz,
    divider: divider,
    consumers: consumers,
  );

  static ClockDomainConfig? from(dynamic value) {
    if (value is ClockDomainConfig) return value as ClockDomainConfig;
    // TODO: add a way to parse value if it a string
    return null;
  }
}

class ClockDomain {
  final String name;
  final double freqHz;
  final String? source;
  final double? divider;
  final List<String> consumers;

  const ClockDomain({
    required this.name,
    required this.freqHz,
    this.source,
    this.divider,
    this.consumers = const [],
  });

  @override
  String toString() =>
      'ClockDomain(name: $name, freqHz: $freqHz, '
      'source: $source, divider: $divider, consumers: $consumers)';
}
