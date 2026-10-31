import 'money.dart';

/// A VAT rate in basis points (2500 = 25 %), so future rates such as 6,5 %
/// can be represented without floating point.
class VatRate implements Comparable<VatRate> {
  final int basisPoints;
  const VatRate(this.basisPoints);

  static const zero = VatRate(0);
  static const six = VatRate(600);
  static const twelve = VatRate(1200);
  static const twentyFive = VatRate(2500);

  factory VatRate.percent(int percent) => VatRate(percent * 100);

  /// Parses `25`, `25 %`, `6,5%`, `12.00`.
  static VatRate? parse(String input) {
    final m = RegExp(r'^\s*(\d{1,2})(?:[.,](\d{1,2}))?\s*%?\s*$').firstMatch(input);
    if (m == null) return null;
    final whole = int.parse(m.group(1)!);
    final frac = int.parse((m.group(2) ?? '0').padRight(2, '0'));
    final bp = whole * 100 + frac;
    if (bp > 10000) return null;
    return VatRate(bp);
  }

  String get label {
    final whole = basisPoints ~/ 100;
    final frac = basisPoints % 100;
    if (frac == 0) return '$whole %';
    final f = frac % 10 == 0 ? '${frac ~/ 10}' : frac.toString().padLeft(2, '0');
    return '$whole,$f %';
  }

  @override
  int compareTo(VatRate other) => basisPoints.compareTo(other.basisPoints);

  @override
  bool operator ==(Object other) => other is VatRate && other.basisPoints == basisPoints;

  @override
  int get hashCode => basisPoints.hashCode;

  @override
  String toString() => label;
}

/// Integer VAT arithmetic with half-away-from-zero rounding to whole öre.
class VatCalculator {
  const VatCalculator._();

  /// VAT contained in a VAT-inclusive amount: gross × r / (100 + r).
  static Money vatFromGross(Money gross, VatRate rate) =>
      Money(_divRound(gross.ore * rate.basisPoints, 10000 + rate.basisPoints));

  static Money netFromGross(Money gross, VatRate rate) => gross - vatFromGross(gross, rate);

  /// VAT on a VAT-exclusive amount: net × r / 100.
  static Money vatFromNet(Money net, VatRate rate) =>
      Money(_divRound(net.ore * rate.basisPoints, 10000));

  static int _divRound(int numerator, int denominator) {
    final negative = (numerator < 0) != (denominator < 0);
    final n = numerator.abs();
    final d = denominator.abs();
    final q = (2 * n + d) ~/ (2 * d);
    return negative ? -q : q;
  }
}

/// Guidance shown to the user when they pick a rate for a category.
/// It is never used to assign a rate automatically.
class VatGuidance {
  final String text;
  final VatRate rate;
  final DateTime? validFrom;
  final DateTime? validTo;
  const VatGuidance(this.text, this.rate, {this.validFrom, this.validTo});

  bool appliesOn(DateTime day) =>
      (validFrom == null || !day.isBefore(validFrom!)) &&
      (validTo == null || !day.isAfter(validTo!));
}

/// A versioned set of Swedish VAT rules. When the rules change, add a new
/// set instead of editing an old one.
class VatRuleSet {
  final String id;
  final String source;
  final DateTime verifiedOn;
  final List<VatRate> rates;
  final List<VatGuidance> guidance;

  const VatRuleSet({
    required this.id,
    required this.source,
    required this.verifiedOn,
    required this.rates,
    required this.guidance,
  });

  List<VatGuidance> guidanceOn(DateTime day) =>
      guidance.where((g) => g.appliesOn(day)).toList();

  /// Verified 2026-10-31 against skatteverket.se ("Livsmedelsmomsen sänks
  /// till 6 procent" and "Momssatser och undantag från moms").
  static final se2026 = VatRuleSet(
    id: 'SE-2026-04',
    source: 'Skatteverket, skatteverket.se (kontrollerad 2026-10-31)',
    verifiedOn: DateTime(2026, 10, 31),
    rates: const [VatRate.zero, VatRate.six, VatRate.twelve, VatRate.twentyFive],
    guidance: [
      VatGuidance('Livsmedel, även hämtmat: 6 % (1 april 2026 – 31 december 2027)',
          VatRate.six,
          validFrom: DateTime(2026, 4, 1), validTo: DateTime(2027, 12, 31)),
      VatGuidance('Livsmedel: 12 % (före 1 april 2026)', VatRate.twelve,
          validTo: DateTime(2026, 3, 31)),
      const VatGuidance('Mat och dryck som serveras som restaurangtjänst: 12 %', VatRate.twelve),
      const VatGuidance('Alkoholdrycker, tobak och de flesta andra varor: 25 %',
          VatRate.twentyFive),
    ],
  );

  static VatRuleSet get current => se2026;
}
