import 'models.dart';
import 'money.dart';
import 'vat.dart';

enum ValidationStatus { ok, warning, error }

class ValidationResult {
  final ValidationStatus status;
  final String field;
  final String message;
  final Money? difference;

  const ValidationResult(this.status, this.field, this.message, {this.difference});

  bool get isOk => status == ValidationStatus.ok;

  @override
  String toString() => 'ValidationResult($status, $field, $message)';
}

/// Deterministic accounting checks. It reports discrepancies; it never
/// changes a value to make the numbers agree.
class AccountingValidationEngine {
  const AccountingValidationEngine();

  /// Allowed difference for net + VAT vs. total: öresavrundning up to 50 öre
  /// plus one öre of rounding per VAT line.
  static Money totalTolerance(int vatLines) => Money(50 + vatLines);

  /// Z-report: the category rows must add up to the reported daily total.
  /// Any difference, however small, is shown to the user.
  ValidationResult reconcileZReport(Iterable<Money> categoryAmounts, Money reportedTotal) {
    final detailed = Money.sum(categoryAmounts);
    final diff = detailed - reportedTotal;
    if (diff.isZero) {
      return const ValidationResult(ValidationStatus.ok, 'total',
          'Kontroll: detaljerad försäljning stämmer med dagsförsäljningen.',
          difference: Money.zero);
    }
    return ValidationResult(ValidationStatus.warning, 'total',
        'Varning: försäljningsbeloppen stämmer inte. Skillnad ${diff.format()}.',
        difference: diff);
  }

  List<ValidationResult> validateDailySales(DailySales day) => [
        reconcileZReport(day.items.map((i) => i.amount), day.reportedTotal),
        for (final i in day.items)
          if (i.amount.isNegative)
            ValidationResult(ValidationStatus.warning, 'item',
                '${i.categoryName}: beloppet är negativt.'),
      ];

  List<ValidationResult> validateInvoice(Invoice inv, {Money? net}) {
    final results = <ValidationResult>[];
    if (inv.total.isZero || inv.total.isNegative) {
      results.add(const ValidationResult(
          ValidationStatus.error, 'total', 'Summan saknas eller är inte positiv.'));
    }
    if (inv.vatLines.isNotEmpty) {
      results.add(checkVatBreakdown(inv.vatLines, inv.vatTotal));
      for (final line in inv.vatLines) {
        final r = checkVatLine(line);
        if (r != null) results.add(r);
      }
      final nets = inv.vatLines.map((l) => l.net).toList();
      if (net == null && nets.every((n) => n != null)) {
        net = Money.sum(nets.cast<Money>());
      }
    }
    if (net != null) {
      results.add(checkInvoiceArithmetic(net, inv.vatTotal, inv.total,
          vatLines: inv.vatLines.length));
    }
    final plausible = checkVatPlausible(inv.vatTotal, inv.total);
    if (plausible != null) results.add(plausible);
    return results;
  }

  /// NETTO + MOMS ≈ TOTAL.
  ValidationResult checkInvoiceArithmetic(Money net, Money vat, Money total,
      {int vatLines = 1}) {
    final diff = net + vat - total;
    if (diff.abs() <= totalTolerance(vatLines)) {
      return ValidationResult(ValidationStatus.ok, 'total',
          'Netto + moms stämmer med summan.', difference: diff);
    }
    return ValidationResult(ValidationStatus.warning, 'total',
        'Netto + moms (${(net + vat).format()}) skiljer sig från summan med ${diff.format()}.',
        difference: diff);
  }

  /// The VAT lines must add up to the total VAT.
  ValidationResult checkVatBreakdown(List<InvoiceVatLine> lines, Money vatTotal) {
    final sum = Money.sum(lines.map((l) => l.vat));
    final diff = sum - vatTotal;
    if (diff.abs() <= Money(lines.length)) {
      return ValidationResult(ValidationStatus.ok, 'vat',
          'Momsen per momssats stämmer med total moms.', difference: diff);
    }
    return ValidationResult(ValidationStatus.warning, 'vat',
        'Momsen per momssats (${sum.format()}) skiljer sig från total moms med ${diff.format()}.',
        difference: diff);
  }

  /// A VAT line must agree with its own net or gross amount at its rate.
  ValidationResult? checkVatLine(InvoiceVatLine line) {
    Money? expected;
    if (line.net != null) {
      expected = VatCalculator.vatFromNet(line.net!, line.rate);
    } else if (line.gross != null) {
      expected = VatCalculator.vatFromGross(line.gross!, line.rate);
    }
    if (expected == null) return null;
    final diff = line.vat - expected;
    if (diff.abs() <= const Money(2)) return null;
    return ValidationResult(ValidationStatus.warning, 'vat',
        'Moms ${line.rate.label}: ${line.vat.format()} stämmer inte med beräknat ${expected.format()}.',
        difference: diff);
  }

  /// VAT can never exceed what the highest standard rate gives on the total.
  ValidationResult? checkVatPlausible(Money vat, Money total) {
    if (vat.isNegative) {
      return const ValidationResult(ValidationStatus.warning, 'vat', 'Momsen är negativ.');
    }
    final max = VatCalculator.vatFromGross(total.abs(), VatRate.twentyFive);
    if (vat > max + const Money(1)) {
      return ValidationResult(ValidationStatus.warning, 'vat',
          'Momsen (${vat.format()}) är högre än 25 % av summan kan ge (${max.format()}).');
    }
    return null;
  }

  /// Monthly/yearly: the parts must add up to the stated total.
  ValidationResult checkAggregation(String field, Iterable<Money> parts, Money total) {
    final diff = Money.sum(parts) - total;
    if (diff.isZero) {
      return const ValidationResult(ValidationStatus.ok, 'sum', 'Summeringen stämmer.');
    }
    return ValidationResult(ValidationStatus.error, field,
        'Summeringen stämmer inte (skillnad ${diff.format()}).', difference: diff);
  }
}
