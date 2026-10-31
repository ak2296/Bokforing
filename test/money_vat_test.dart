import 'package:bokforing/domain/money.dart';
import 'package:bokforing/domain/vat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money.parse', () {
    test('Swedish formats', () {
      expect(Money.parse('1 250,50'), const Money(125050));
      expect(Money.parse('1250,50'), const Money(125050));
      expect(Money.parse('1.250,50'), const Money(125050));
      expect(Money.parse('1 250,50 kr'), const Money(125050));
      expect(Money.parse('12 955,00'), const Money(1295500));
      expect(Money.parse('12,5'), const Money(1250));
      expect(Money.parse('125:-'), const Money(12500));
      expect(Money.parse('125,-'), const Money(12500));
      expect(Money.parse('1250'), const Money(125000));
      expect(Money.parse('598,90 SEK'), const Money(59890));
      expect(Money.parse('200,00kr'), const Money(20000));
    });

    test('English format only where unambiguous', () {
      expect(Money.parse('1,250.50'), const Money(125050));
      expect(Money.parse('1250.50'), const Money(125050));
      expect(Money.parse('1.250'), isNull);
      expect(Money.parse('1,250'), isNull);
    });

    test('negative amounts', () {
      expect(Money.parse('-0,34'), const Money(-34));
      expect(Money.parse('34,00-'), const Money(-3400));
    });

    test('rejects non-amounts', () {
      expect(Money.parse(''), isNull);
      expect(Money.parse('abc'), isNull);
      expect(Money.parse('12,345,6'), isNull);
      expect(Money.parse('1,2,3'), isNull);
    });
  });

  group('Money.format', () {
    test('Swedish display', () {
      expect(const Money(125050).format(), '1 250,50 kr');
      expect(const Money(1080000).format(compact: true), '10 800 kr');
      expect(const Money(-10000).format(), '-100,00 kr');
      expect(const Money(5).format(), '0,05 kr');
      expect(const Money(125050).toInput(), '1250,50');
    });
  });

  group('VAT from VAT-inclusive amounts', () {
    test('125 kr at 25 % gives 25 kr', () {
      expect(VatCalculator.vatFromGross(Money.kr(125), VatRate.twentyFive), Money.kr(25));
    });
    test('112 kr at 12 % gives 12 kr', () {
      expect(VatCalculator.vatFromGross(Money.kr(112), VatRate.twelve), Money.kr(12));
    });
    test('106 kr at 6 % gives 6 kr', () {
      expect(VatCalculator.vatFromGross(Money.kr(106), VatRate.six), Money.kr(6));
    });
    test('rounding to whole öre, half away from zero', () {
      // 100 kr at 12 %: 10,714... kr
      expect(VatCalculator.vatFromGross(Money.kr(100), VatRate.twelve), const Money(1071));
      // 549 kr at 6 %: 31,075... kr
      expect(VatCalculator.vatFromGross(Money.kr(549), VatRate.six), const Money(3108));
      expect(VatCalculator.vatFromGross(Money.kr(-125), VatRate.twentyFive), Money.kr(-25));
    });
    test('VAT on net', () {
      expect(VatCalculator.vatFromNet(Money.kr(100), VatRate.twentyFive), Money.kr(25));
      expect(VatCalculator.netFromGross(Money.kr(125), VatRate.twentyFive), Money.kr(100));
    });
    test('multiple rates sum: 250 + 120 + 60 = 430', () {
      final total = Money.sum([Money.kr(250), Money.kr(120), Money.kr(60)]);
      expect(total, Money.kr(430));
    });
  });

  group('VatRate', () {
    test('parse and label', () {
      expect(VatRate.parse('25'), VatRate.twentyFive);
      expect(VatRate.parse('6 %'), VatRate.six);
      expect(VatRate.parse('6,5%'), const VatRate(650));
      expect(VatRate.parse('abc'), isNull);
      expect(VatRate.twelve.label, '12 %');
      expect(const VatRate(650).label, '6,5 %');
    });

    test('rule set guidance follows dates', () {
      final food = VatRuleSet.se2026.guidance.first;
      expect(food.rate, VatRate.six);
      expect(food.appliesOn(DateTime(2026, 4, 1)), isTrue);
      expect(food.appliesOn(DateTime(2026, 3, 31)), isFalse);
      expect(food.appliesOn(DateTime(2028, 1, 1)), isFalse);
    });
  });
}
