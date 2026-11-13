class SettingsKeys {
  const SettingsKeys._();
  static const setupDone = 'setup_done';

  /// Look for a new version once a day (on by default), when it was last done
  /// (ISO date), and whether the last look found a newer release.
  static const updateCheck = 'update_check';
  static const updateLastCheck = 'update_last_check';
  static const updateFound = 'update_found';

  /// Set when the setup is finished: the first start shows the tour once.
  static const tourPending = 'tour_pending';
  static const keepImages = 'keep_images';

  /// "Avrunda utgifter till hela kronor": reports and lists only.
  static const roundExpenses = 'round_expenses';

  /// Estimated tax to set aside (enskild firma): 'percent' or 'amount', the
  /// percent in tenths and the yearly amount in öre.
  static const taxMode = 'tax_mode';
  static const taxPercent = 'tax_percent_tenths';
  static const taxAmount = 'tax_year_amount_ore';
  /// 'auto' (follow the phone), 'light' or 'dark'.
  static const themeMode = 'theme_mode';
  static const companyForm = 'company_form';
  static const fiscalStartMonth = 'fiscal_start_month';
  static const ownNames = 'own_names';
  static const licenseCode = 'license_code';
  static const licenseLastSeen = 'license_last_seen';
}
