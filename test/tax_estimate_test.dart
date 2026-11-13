import 'package:bokforing/domain/models.dart';
import 'package:bokforing/domain/money.dart';
import 'package:bokforing/domain/tax_estimate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TaxEstimate', () {
    test('aktiebolag: 20,6 % of a profit, 0 for a loss', () {
      const t = TaxEstimate(form: CompanyForm.aktiebolag);
      expect(t.tax(Money.kr(10000)), Money.kr(2060));
      expect(t.tax(Money.kr(-500)), Money.zero);
    });

    test('enskild firma: own percentage', () {
      const t = TaxEstimate(form: CompanyForm.enskildFirma, percentTenths: 305);
      expect(t.tax(Money.kr(10000)), Money.kr(3050));
      expect(t.label, 'Att lägga undan, 30,5 %');
    });

    test('enskild firma: yearly amount, spread over the months, never more than the profit', () {
      final t = TaxEstimate(form: CompanyForm.enskildFirma, mode: TaxMode.amount, yearlyAmount: Money.kr(36000));
      expect(t.tax(Money.kr(100000), months: 12), Money.kr(36000));
      expect(t.tax(Money.kr(10000)), Money.kr(3000));
      expect(t.tax(Money.kr(2000)), Money.kr(2000));
      expect(t.tax(Money.kr(0)), Money.zero);
    });

    test('nothing is shown before the form is chosen or when nothing is set', () {
      expect(const TaxEstimate().tax(Money.kr(10000)), isNull);
      expect(const TaxEstimate(form: CompanyForm.enskildFirma, percentTenths: 0).tax(Money.kr(10000)), isNull);
    });
  });
}
