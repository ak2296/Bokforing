import 'dart:convert';

import 'models.dart';
import 'money.dart';

/// How an invoice or receipt was paid. It decides which account the money
/// leaves from in the books; moms and the result are the same for all three.
enum PayMethod {
  /// The company's bank account or a company card: 1930.
  bank('Bank / kort'),

  /// Cash from the till: 1910 Kassa.
  cash('Kontant'),

  /// The owner paid with their own money: for enskild firma an own deposit
  /// (2018), for aktiebolag a debt to the owner (2893).
  owner('Privat');

  final String label;
  const PayMethod(this.label);

  /// Reads the saved key; anything else is [bank], which is what every record
  /// had before the choice existed.
  static PayMethod parse(String? key) => values.where((m) => m.name == key).firstOrNull ?? PayMethod.bank;

  /// The BAS account the payment is booked against.
  int account(CompanyForm? form) => switch (this) {
        PayMethod.bank => 1930,
        PayMethod.cash => 1910,
        PayMethod.owner => form == CompanyForm.enskildFirma ? 2018 : 2893,
      };

  /// One line for the owner: where it is booked.
  String explain(CompanyForm? form) => switch (this) {
        PayMethod.bank => 'Bokförs som betalt från företagskontot (1930).',
        PayMethod.cash => 'Bokförs som betalt från kassan (1910).',
        PayMethod.owner => form == CompanyForm.enskildFirma
            ? 'Du betalade med dina egna pengar. Bokförs som egen insättning (2018).'
            : 'Du betalade med dina egna pengar. Företaget är skyldigt dig beloppet (2893, skuld till ägaren).',
      };
}

/// One part of a payment that was split: how much was paid in which way.
class PaymentPart {
  final PayMethod method;
  final Money amount;
  const PaymentPart(this.method, this.amount);

  static String encode(List<PaymentPart> parts) => jsonEncode([
        for (final p in parts) [p.method.name, p.amount.ore],
      ]);

  /// Reads what [encode] wrote. Anything unreadable gives an empty list, which means
  /// "not split".
  static List<PaymentPart> decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      return [
        for (final e in jsonDecode(raw) as List) PaymentPart(PayMethod.parse((e as List)[0] as String?), Money((e[1] as num).toInt())),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// A usable split: at least two parts, none of them zero, and they add up to [total].
  static bool valid(List<PaymentPart> parts, Money total) =>
      parts.length > 1 && parts.every((p) => !p.amount.isZero) && Money.sum(parts.map((p) => p.amount)) == total;
}
