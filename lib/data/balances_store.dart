import '../app/settings_keys.dart';
import '../domain/balances.dart';
import 'repository.dart';

/// The first day of the financial year that [now] falls in, as an ISO date.
String fiscalYearStartIso(DateTime now, int startMonth) {
  final year = now.month >= startMonth ? now.year : now.year - 1;
  return '$year-${startMonth.toString().padLeft(2, '0')}-01';
}

/// The opening balances the owner entered (none yet gives an empty set dated
/// at the start of the current financial year).
Future<OpeningBalances> loadBalances(Repository repo) async {
  final start = await repo.fiscalStartMonth();
  return OpeningBalances.decode(await repo.setting(SettingsKeys.openingBalances),
      fallbackDate: fiscalYearStartIso(DateTime.now(), start));
}

Future<void> saveBalances(Repository repo, OpeningBalances b) => repo.setSetting(SettingsKeys.openingBalances, b.encode());
