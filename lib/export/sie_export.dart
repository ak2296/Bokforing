import 'dart:typed_data';

import '../domain/cost_types.dart';
import '../domain/dates.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import '../domain/vat.dart';

/// SIE 4 file (Swedish standard) with one verification per Z-report, online
/// sale, invoice and invoice payment, on BAS accounts. Fortnox, Visma, Bokio
/// and accountants read it. Only what is registered in the app is exported.
class SieExport {
  static const cash = 1910;
  static const bank = 1930;
  static const partnerReceivable = 1510;
  static const supplierDebt = 2440;
  static const inputVat = 2641;
  static const unspecifiedSales = 3000;
  static const personalTax = 2710;
  static const socialFeesDebt = 2731;

  static const _accountNames = {
    1510: 'Kundfordringar',
    1910: 'Kassa',
    1930: 'Företagskonto',
    2710: 'Personalskatt',
    2731: 'Avräkning lagstadgade sociala avgifter',
    7010: 'Löner',
    7510: 'Lagstadgade sociala avgifter',
    2440: 'Leverantörsskulder',
    2611: 'Utgående moms på försäljning inom Sverige, 25 %',
    2621: 'Utgående moms på försäljning inom Sverige, 12 %',
    2631: 'Utgående moms på försäljning inom Sverige, 6 %',
    2641: 'Debiterad ingående moms',
    3000: 'Försäljning',
    3001: 'Försäljning inom Sverige, 25 % moms',
    3002: 'Försäljning inom Sverige, 12 % moms',
    3003: 'Försäljning inom Sverige, 6 % moms',
    3004: 'Försäljning inom Sverige, momsfri',
  };

  static int salesAccount(VatRate r) => switch (r.basisPoints) {
        2500 => 3001,
        1200 => 3002,
        600 => 3003,
        0 => 3004,
        _ => unspecifiedSales,
      };

  static int? outputVatAccount(VatRate r) => switch (r.basisPoints) {
        2500 => 2611,
        1200 => 2621,
        600 => 2631,
        _ => null,
      };

  /// The file as text; [encode] turns it into the bytes to save.
  static String build({
    required BusinessProfile profile,
    required String fromIso,
    required String toIso,
    required String yearStartIso,
    required String yearEndIso,
    required List<DailySales> sales,
    required List<Invoice> invoices,
    List<OnlineSale> online = const [],
    List<Payslip> payslips = const [],
    DateTime? generated,
  }) {
    bool inPeriod(String? d) => d != null && d.compareTo(fromIso) >= 0 && d.compareTo(toIso) <= 0;
    final vers = <_Ver>[];

    for (final day in sales.where((s) => inPeriod(s.businessDate))) {
      final gross = <int, Money>{}, vat = <int, Money>{};
      for (final item in day.items) {
        final bp = item.vat.basisPoints;
        gross[bp] = (gross[bp] ?? Money.zero) + item.amount;
        vat[bp] = (vat[bp] ?? Money.zero) + item.vatAmount;
      }
      final v = _Ver('A', day.businessDate, 'Dagskassa${day.zNumber == null ? '' : ' Z ${day.zNumber}'}');
      v.add(cash, day.detailedTotal);
      for (final bp in gross.keys) {
        final rate = VatRate(bp);
        final vatAcc = outputVatAccount(rate);
        final vatPart = vatAcc == null ? Money.zero : vat[bp]!;
        v.add(salesAccount(rate), -(gross[bp]! - vatPart));
        if (vatAcc != null) v.add(vatAcc, -vatPart);
      }
      vers.add(v);
    }

    for (final o in online.where((o) => inPeriod(o.paymentDate))) {
      final v = _Ver('B', o.paymentDate, 'Onlineförsäljning ${o.partner} ${o.documentNumber}'.trim());
      v.add(partnerReceivable, o.amount);
      final rate = o.vatRate;
      final vatAcc = rate == null ? null : outputVatAccount(rate);
      if (vatAcc != null && !o.vat.isZero) {
        v.add(salesAccount(rate!), -(o.amount - o.vat));
        v.add(vatAcc, -o.vat);
      } else {
        v.add(unspecifiedSales, -o.amount);
      }
      vers.add(v);
    }

    for (final i in invoices) {
      final cost = CostType.byKey(i.costType) ?? CostType.other;
      final text = [i.supplier, if (i.invoiceNumber.isNotEmpty) 'nr ${i.invoiceNumber}'].join(' ').trim();
      // Paid on the day (kvitto): straight from the bank. Otherwise a debt
      // until it is paid.
      final paidAtOnce = i.paid && (i.paidDate == null || i.paidDate == i.bookingDate);
      if (inPeriod(i.bookingDate)) {
        final v = _Ver('C', i.bookingDate, text.isEmpty ? 'Leverantörsfaktura' : text);
        v.add(cost.account, i.total - i.vatTotal, name: cost.label);
        if (!i.vatTotal.isZero) v.add(inputVat, i.vatTotal);
        v.add(paidAtOnce ? bank : supplierDebt, -i.total);
        vers.add(v);
      }
      // A payment in the period, also for an invoice from before it.
      if (!paidAtOnce && i.paid && inPeriod(i.paidDate)) {
        vers.add(_Ver('C', i.paidDate!, 'Betalning ${text.isEmpty ? 'leverantörsfaktura' : text}')
          ..add(supplierDebt, i.total)
          ..add(bank, -i.total));
      }
    }

    // One balanced verification per lönebesked: the cost (lön and arbetsgivar-
    // avgift) against the tax withheld, the fee owed and what is paid out. The
    // personnummer is not in the file. The accounts are for the accountant to
    // confirm.
    for (final p in payslips.where((p) => inPeriod(p.payoutDate))) {
      final who = p.employeeName.trim();
      vers.add(_Ver('D', p.payoutDate, who.isEmpty ? 'Lönebesked' : 'Lönebesked $who')
        ..add(CostType.salaries.account, p.gross)
        ..add(CostType.socialFees.account, p.employerFee)
        ..add(personalTax, -p.tax)
        ..add(socialFeesDebt, -p.employerFee)
        ..add(bank, -(p.gross - p.tax)));
    }

    vers.sort((a, b) => a.date.compareTo(b.date));
    final names = <int, String>{};
    for (final v in vers) {
      for (final t in v.trans) {
        names[t.account] ??= t.name ?? _accountNames[t.account] ?? CostType.all.firstWhere((c) => c.account == t.account,
            orElse: () => CostType.other).label;
      }
    }
    final out = StringBuffer();
    void line(String s) => out.write('$s\r\n');
    String d(String iso) => iso.replaceAll('-', '');
    line('#FLAGGA 0');
    line('#FORMAT PC8');
    line('#SIETYP 4');
    line('#PROGRAM ${_q('Quee')} ${_q('1')}');
    line('#GEN ${d(SwedishDates.iso(generated ?? DateTime.now()))}');
    line('#FNAMN ${_q(profile.name)}');
    if (profile.orgNumber.trim().isNotEmpty) line('#ORGNR ${profile.orgNumber.trim()}');
    line('#RAR 0 ${d(yearStartIso)} ${d(yearEndIso)}');
    line('#KPTYP BAS2014');
    for (final a in names.keys.toList()..sort()) {
      line('#KONTO $a ${_q(names[a]!)}');
    }
    final numbers = <String, int>{};
    for (final v in vers) {
      final n = numbers[v.series] = (numbers[v.series] ?? 0) + 1;
      line('#VER ${v.series} $n ${d(v.date)} ${_q(v.text)}');
      line('{');
      for (final t in v.trans) {
        if (t.amount.isZero) continue;
        line('   #TRANS ${t.account} {} ${_amount(t.amount)}');
      }
      line('}');
    }
    return out.toString();
  }

  static String _amount(Money m) {
    final sign = m.isNegative ? '-' : '';
    final ore = m.ore.abs();
    return '$sign${ore ~/ 100}.${(ore % 100).toString().padLeft(2, '0')}';
  }

  static String _q(String s) => '"${s.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll(RegExp(r'[\r\n]'), ' ')}"';

  /// PC8 (code page 437), as the SIE standard asks.
  static Uint8List encode(String text) {
    const map = {
      'Ç': 0x80, 'ü': 0x81, 'é': 0x82, 'â': 0x83, 'ä': 0x84, 'à': 0x85, 'å': 0x86, 'ç': 0x87, 'ê': 0x88,
      'ë': 0x89, 'è': 0x8A, 'ï': 0x8B, 'î': 0x8C, 'ì': 0x8D, 'Ä': 0x8E, 'Å': 0x8F, 'É': 0x90, 'æ': 0x91,
      'Æ': 0x92, 'ô': 0x93, 'ö': 0x94, 'ò': 0x95, 'û': 0x96, 'ù': 0x97, 'ÿ': 0x98, 'Ö': 0x99, 'Ü': 0x9A,
      'á': 0xA0, 'í': 0xA1, 'ó': 0xA2, 'ú': 0xA3, 'ñ': 0xA4, 'Ñ': 0xA5,
    };
    final bytes = <int>[];
    for (final r in text.runes) {
      final c = String.fromCharCode(r);
      bytes.add(r < 0x80 ? r : map[c] ?? 0x3F);
    }
    return Uint8List.fromList(bytes);
  }
}

class _Trans {
  final int account;
  final Money amount;
  final String? name;
  const _Trans(this.account, this.amount, this.name);
}

class _Ver {
  final String series;
  final String date;
  final String text;
  final trans = <_Trans>[];
  _Ver(this.series, this.date, this.text);

  void add(int account, Money amount, {String? name}) => trans.add(_Trans(account, amount, name));
}
