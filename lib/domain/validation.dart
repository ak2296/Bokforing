import 'money.dart';
import 'vat.dart';

enum ValidationStatus { ok, warning, error }

class ValidationResult {
  const ValidationResult(this.status, this.field, this.message, [this.difference]);
  final ValidationStatus status;
  final String field, message;
  final Money? difference;
}

/// Returns structured results. Never changes the data it checks.
class AccountingValidationEngine {
  /// difference = detailed − reported.
  static ValidationResult reconcileZReport(Iterable<Money> categoryAmounts, Money? reported) {
    if (reported == null) {
      return const ValidationResult(ValidationStatus.warning, 'total',
          'Dagsförsäljning saknas. Det går inte att kontrollera summan.');
    }
    final detailed = Money.sum(categoryAmounts);
    final diff = detailed - reported;
    if (diff.isZero) {
      return ValidationResult(ValidationStatus.ok, 'total',
          'Kontroll: detaljerad försäljning stämmer med dagsförsäljningen.', diff);
    }
    return ValidationResult(
        ValidationStatus.warning,
        'total',
        'Varning: försäljningsbeloppen stämmer inte. Detaljerade poster: ${detailed.format()}, '
        'rapporterad dagsförsäljning: ${reported.format()}, skillnad: ${diff.format()}.',
        diff);
  }

  /// netto + moms ≈ totalt (tolerance covers öresavrundning).
  static ValidationResult checkInvoiceArithmetic(Money net, Money vat, Money total,
      {Money tolerance = const Money(100)}) {
    final diff = (net + vat) - total;
    if (diff.ore.abs() <= tolerance.ore) {
      return ValidationResult(
          ValidationStatus.ok, 'total', 'Netto + moms stämmer med totalsumman.', diff);
    }
    return ValidationResult(ValidationStatus.warning, 'total',
        'Netto + moms skiljer sig från totalsumman med ${diff.format()}.', diff);
  }

  static ValidationResult checkVatBreakdown(Iterable<Money> perRate, Money vatTotal) {
    final diff = Money.sum(perRate) - vatTotal;
    return diff.isZero
        ? ValidationResult(ValidationStatus.ok, 'vat', 'Momsfördelningen stämmer.', diff)
        : ValidationResult(ValidationStatus.warning, 'vat',
            'Momsfördelningen summerar inte till total moms (skillnad ${diff.format()}).', diff);
  }

  /// VAT can never exceed gross × 25/125 (the highest Swedish rate).
  static ValidationResult checkVatPlausible(Money vat, Money total) {
    final max = Money(VatCalculator.divRound(total.ore * 25, 125) + 100);
    return vat > max
        ? const ValidationResult(ValidationStatus.warning, 'vat',
            'Momsen är högre än vad 25 % moms kan vara av summan. Kontrollera.')
        : const ValidationResult(ValidationStatus.ok, 'vat', 'Momsen är rimlig.');
  }
}

extension on Money {
  bool operator >(Money o) => ore > o.ore;
}
