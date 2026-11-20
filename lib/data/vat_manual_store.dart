import 'dart:convert';

import 'repository.dart';

/// The figures the owner typed by hand for one period's momsdeklaration (EU trade,
/// import and so on), ruta number to whole kronor. Kept on the phone only, one entry
/// per period ([tag] is the period's file tag, for example `2026-10` or `2026-K4`).
String _key(String tag) => 'vat_manual_$tag';

Future<Map<int, int>> loadVatManual(Repository repo, String tag) async {
  final raw = await repo.setting(_key(tag));
  if (raw == null || raw.isEmpty) return {};
  try {
    final json = jsonDecode(raw);
    if (json is! Map) return {};
    return {
      for (final e in json.entries)
        if (int.tryParse('${e.key}') != null && e.value is num && (e.value as num) != 0) int.parse('${e.key}'): (e.value as num).toInt(),
    };
  } on FormatException {
    return {};
  }
}

Future<void> saveVatManual(Repository repo, String tag, Map<int, int> values) => repo.setSetting(
      _key(tag),
      jsonEncode({for (final e in values.entries) if (e.value != 0) '${e.key}': e.value}),
    );
