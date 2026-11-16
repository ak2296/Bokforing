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

  /// The highest release note the owner has seen (Inställningar → Mer → Nyheter).
  static const notesSeen = 'notes_seen';

  /// The opening balances the owner entered: JSON, see OpeningBalances.encode.
  static const openingBalances = 'opening_balances';

  /// How often underlag goes to the accountant ('month', 'quarter', 'half', 'year'),
  /// and who the accountant is. Kept on the phone only.
  static const reportPeriodKind = 'report_period_kind';
  static const accountantName = 'accountant_name';
  static const accountantEmail = 'accountant_email';
  static const accountantPhone = 'accountant_phone';
  static const ownerEmail = 'owner_email';
  static const keepImages = 'keep_images';

  /// "Avrunda utgifter till hela kronor": reports and lists only.
  static const roundExpenses = 'round_expenses';

  /// Cost types the owner added: JSON, see CostType.encodeCustom.
  static const customCostTypes = 'custom_cost_types';

  /// Days the shop is closed, so no Z-report is expected: weekdays (JSON list of
  /// 1..7, Monday = 1) and single dates (JSON list of ISO dates).
  static const closedWeekdays = 'closed_weekdays';
  static const closedDates = 'closed_dates';

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
