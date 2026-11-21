import 'dart:convert';

import '../domain/models.dart';
import '../domain/money.dart';
import 'repository.dart';

const _key = 'bank_match';

/// What the owner's last bank files said about the Z-reports and the invoices paid from
/// the bank or by card: only yes or no per Z-report day and per invoice. Nothing else
/// from the bank file (text, amounts, balances) is kept.
class BankMatchFlags {
  /// Z-report day (ISO) to whether a deposit was found.
  final Map<String, bool> z;

  /// Invoice id to whether a payment was found.
  final Map<int, bool> invoices;
  const BankMatchFlags({this.z = const {}, this.invoices = const {}});

  bool get isEmpty => z.isEmpty && invoices.isEmpty;

  /// "3 av 4": Z-report days with card takings that a deposit was found for. "–" when
  /// no bank file has been read for these days.
  String zText(List<DailySales> sales) {
    final days = [for (final d in sales) if ((d.card ?? Money.zero) > Money.zero) d.businessDate];
    if (days.isEmpty || !days.any(z.containsKey)) return '–';
    return '${days.where((d) => z[d] == true).length} av ${days.length}';
  }

  /// "4 av 5": invoices and receipts paid from the bank or by card that a payment in the
  /// bank file was found for.
  String invoiceText(List<Invoice> list) {
    final ids = [for (final i in list) if (i.paid && i.bankPart > Money.zero && i.id != null) i.id!];
    if (ids.isEmpty || !ids.any(invoices.containsKey)) return '–';
    return '${ids.where((i) => invoices[i] == true).length} av ${ids.length}';
  }
}

Future<BankMatchFlags> loadBankMatch(Repository repo) async {
  final raw = await repo.setting(_key);
  if (raw == null || raw.isEmpty) return const BankMatchFlags();
  try {
    final json = jsonDecode(raw) as Map;
    return BankMatchFlags(
      z: {for (final e in (json['z'] as Map? ?? {}).entries) '${e.key}': e.value == true},
      invoices: {for (final e in (json['i'] as Map? ?? {}).entries) if (int.tryParse('${e.key}') != null) int.parse('${e.key}'): e.value == true},
    );
  } catch (_) {
    return const BankMatchFlags();
  }
}

/// Adds the newest answers to what is already kept.
Future<void> saveBankMatch(Repository repo, {Map<String, bool> z = const {}, Map<int, bool> invoices = const {}}) async {
  final old = await loadBankMatch(repo);
  await repo.setSetting(
    _key,
    jsonEncode({
      'z': {...old.z, ...z},
      'i': {for (final e in {...old.invoices, ...invoices}.entries) '${e.key}': e.value},
    }),
  );
}
