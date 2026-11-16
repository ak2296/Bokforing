import '../app/settings_keys.dart';
import '../domain/report_period.dart';
import 'repository.dart';

/// How often the owner hands over underlag, and who the accountant is. All
/// kept on the phone; nothing is sent anywhere by the app itself.
class AccountingSettings {
  final PeriodKind kind;
  final String accountantName;
  final String accountantEmail;
  final String accountantPhone;
  final String ownerEmail;
  const AccountingSettings({
    this.kind = PeriodKind.month,
    this.accountantName = '',
    this.accountantEmail = '',
    this.accountantPhone = '',
    this.ownerEmail = '',
  });

  bool get hasAccountantEmail => accountantEmail.contains('@');
  bool get hasAccountantPhone => accountantPhone.replaceAll(RegExp(r'[^0-9+]'), '').length >= 6;

  /// The first name or the whole name, for "Hej Anna!".
  String get greetingName {
    final n = accountantName.trim();
    return n.isEmpty ? '' : n.split(RegExp(r'\s+')).first;
  }

  AccountingSettings copyWith({
    PeriodKind? kind,
    String? accountantName,
    String? accountantEmail,
    String? accountantPhone,
    String? ownerEmail,
  }) =>
      AccountingSettings(
        kind: kind ?? this.kind,
        accountantName: accountantName ?? this.accountantName,
        accountantEmail: accountantEmail ?? this.accountantEmail,
        accountantPhone: accountantPhone ?? this.accountantPhone,
        ownerEmail: ownerEmail ?? this.ownerEmail,
      );
}

Future<AccountingSettings> loadAccounting(Repository repo) async => AccountingSettings(
      kind: PeriodKind.byName(await repo.setting(SettingsKeys.reportPeriodKind)),
      accountantName: await repo.setting(SettingsKeys.accountantName) ?? '',
      accountantEmail: await repo.setting(SettingsKeys.accountantEmail) ?? '',
      accountantPhone: await repo.setting(SettingsKeys.accountantPhone) ?? '',
      ownerEmail: await repo.setting(SettingsKeys.ownerEmail) ?? '',
    );

Future<void> saveAccounting(Repository repo, AccountingSettings s) async {
  await repo.setSetting(SettingsKeys.reportPeriodKind, s.kind.name);
  await repo.setSetting(SettingsKeys.accountantName, s.accountantName.trim());
  await repo.setSetting(SettingsKeys.accountantEmail, s.accountantEmail.trim());
  await repo.setSetting(SettingsKeys.accountantPhone, s.accountantPhone.trim());
  await repo.setSetting(SettingsKeys.ownerEmail, s.ownerEmail.trim());
}
