import 'money.dart';

/// Rate in basis points (25 % = 2500) so other rates can be added later.
class VatRate {
  const VatRate(this.basisPoints);
  final int basisPoints;
  int get percent => basisPoints ~/ 100;

  static const zero = VatRate(0);
  static const six = VatRate(600);
  static const twelve = VatRate(1200);
  static const twentyFive = VatRate(2500);
  static const selectable = [zero, six, twelve, twentyFive];

  @override
  bool operator ==(Object o) => o is VatRate && o.basisPoints == basisPoints;
  @override
  int get hashCode => basisPoints.hashCode;
}

class VatSplit {
  const VatSplit(this.gross, this.vat, this.net);
  final Money gross, vat, net;
}

class VatCalculator {
  /// Round half away from zero, integers only.
  static int divRound(int n, int d) {
    final sg = ((n < 0) != (d < 0)) ? -1 : 1;
    final a = n.abs(), b = d.abs();
    return sg * ((2 * a + b) ~/ (2 * b));
  }

  /// VAT inside a VAT-inclusive amount: gross × r / (100 + r).
  static VatSplit fromGross(Money gross, VatRate rate) {
    final bp = rate.basisPoints;
    final vat = Money(divRound(gross.ore * bp, 10000 + bp));
    return VatSplit(gross, vat, gross - vat);
  }

  /// VAT added on top of a net amount.
  static VatSplit fromNet(Money net, VatRate rate) {
    final vat = Money(divRound(net.ore * rate.basisPoints, 10000));
    return VatSplit(net + vat, vat, net);
  }
}

/// Informational only. The app never assigns a rate from a category name.
class VatGuidance {
  const VatGuidance(this.topic, this.rate, this.validFrom, this.validTo,
      this.verified, this.noteSv);
  final String topic;
  final VatRate rate;
  final DateTime validFrom;
  final DateTime? validTo;
  final bool verified;
  final String noteSv;
}

class VatRuleSet {
  static final guidance = <VatGuidance>[
    VatGuidance('Livsmedel inkl. avhämtning', VatRate.twelve, DateTime(2012, 1, 1),
        DateTime(2026, 3, 31), true, '12 % till och med 31 mars 2026.'),
    VatGuidance('Livsmedel inkl. avhämtning', VatRate.six, DateTime(2026, 4, 1),
        DateTime(2027, 12, 31), false,
        '6 % från 1 april 2026. Slutdatum bör kontrolleras hos Skatteverket.'),
    VatGuidance('Mat och dryck som serveras på plats', VatRate.twelve,
        DateTime(2012, 1, 1), null, true, 'Restaurang- och cafétjänster: 12 %.'),
  ];

  static List<VatGuidance> hintsFor(DateTime d) => guidance
      .where((g) => !d.isBefore(g.validFrom) && (g.validTo == null || !d.isAfter(g.validTo!)))
      .toList();
}
