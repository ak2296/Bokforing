class SettingsKeys {
  const SettingsKeys._();
  static const setupDone = 'setup_done';

  /// Set when the setup is finished: the first start shows the tour once.
  static const tourPending = 'tour_pending';
  static const keepImages = 'keep_images';

  /// "Avrunda utgifter till hela kronor": reports and lists only.
  static const roundExpenses = 'round_expenses';

  /// Estimated tax to set aside (enskild firma): 'percent' or 'amount', the
  /// percent in tenths and the monthly amount in öre.
  static const taxMode = 'tax_mode';
  static const taxPercent = 'tax_percent_tenths';
  static const taxAmount = 'tax_amount_ore';
  /// 'auto' (follow the phone), 'light' or 'dark'.
  static const themeMode = 'theme_mode';
  static const companyForm = 'company_form';
  static const fiscalStartMonth = 'fiscal_start_month';
  static const ownNames = 'own_names';
  static const licenseCode = 'license_code';
  static const licenseLastSeen = 'license_last_seen';
}
