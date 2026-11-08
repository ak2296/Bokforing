import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../app/settings_keys.dart';
import '../domain/dates.dart';
import '../domain/license.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import '../domain/supplier_hints.dart';
import '../domain/text_patterns.dart';
import '../domain/vat.dart';

/// All reads and writes to the local database. Accounting records are only
/// written through the `save*` methods, which the UI calls exclusively from
/// the user's "Godkänn och spara" action.
class Repository {
  final Database db;
  Repository(this.db);

  static String _now() => DateTime.now().toIso8601String();

  // ---------- Settings ----------

  Future<String?> setting(String key) async {
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setSetting(String key, String value) => db.insert(
      'settings', {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace);

  Future<bool> boolSetting(String key, {bool fallback = false}) async {
    final v = await setting(key);
    return v == null ? fallback : v == '1';
  }

  Future<void> setBoolSetting(String key, bool value) => setSetting(key, value ? '1' : '0');

  /// The latest date this phone has shown, so setting the clock back does not
  /// bring an expired code back to life.
  Future<String> _licenseToday() async {
    final today = SwedishDates.iso(DateTime.now());
    final seen = await setting(SettingsKeys.licenseLastSeen);
    if (seen != null && seen.compareTo(today) > 0) return seen;
    if (seen != today) await setSetting(SettingsKeys.licenseLastSeen, today);
    return today;
  }

  Future<LicenseState> licenseState({LicenseChecker checker = const LicenseChecker()}) async {
    final code = await setting(SettingsKeys.licenseCode);
    final license = code == null ? null : await checker.read(code);
    return LicenseState(license, checker.statusOf(license, await _licenseToday()));
  }

  /// Stores a valid code and returns null, or returns why it was refused. A
  /// customer's code also sets the company name and org number.
  Future<String?> activateLicense(String code, {LicenseChecker checker = const LicenseChecker()}) async {
    final license = await checker.read(code);
    if (license == null) return 'Koden stämmer inte. Kontrollera att hela koden kom med.';
    switch (checker.statusOf(license, await _licenseToday())) {
      case LicenseStatus.revoked:
        return 'Den här koden är avslutad och kan inte användas.';
      case LicenseStatus.expired:
        return 'Koden gick ut ${license.until}.';
      case LicenseStatus.active:
      case LicenseStatus.missing:
        break;
    }
    await setSetting(SettingsKeys.licenseCode, code.replaceAll(RegExp(r'\s'), ''));
    if (license.locksCompany) {
      await saveProfile((await profile()).copyWith(name: license.companyName, orgNumber: license.orgNumber));
    }
    return null;
  }

  /// Enskild firma or aktiebolag; null until chosen.
  Future<CompanyForm?> companyForm() async => CompanyForm.parse(await setting(SettingsKeys.companyForm));

  Future<void> setCompanyForm(CompanyForm form) => setSetting(SettingsKeys.companyForm, form.name);

  /// First month of the financial year, 1 = January (January to December).
  Future<int> fiscalStartMonth() async => int.tryParse(await setting(SettingsKeys.fiscalStartMonth) ?? '') ?? 1;

  Future<void> setFiscalStartMonth(int month) => setSetting(SettingsKeys.fiscalStartMonth, '$month');

  /// Other names the owner's company has on papers ("TWINS").
  Future<List<String>> ownNames() async =>
      (await setting(SettingsKeys.ownNames) ?? '').split('\n').where((n) => n.trim().isNotEmpty).toList();

  Future<void> addOwnName(String name) async {
    final n = name.trim();
    final names = await ownNames();
    if (n.isEmpty || names.any((x) => x.toLowerCase() == n.toLowerCase())) return;
    await setSetting(SettingsKeys.ownNames, [...names, n].join('\n'));
  }

  Future<void> removeOwnName(String name) async {
    final names = await ownNames();
    await setSetting(SettingsKeys.ownNames, names.where((x) => x != name).join('\n'));
  }

  // ---------- Business profile ----------

  Future<BusinessProfile> profile() async {
    final rows = await db.query('business_profile', where: 'id = 1');
    if (rows.isEmpty) return const BusinessProfile();
    final r = rows.first;
    return BusinessProfile(
      name: r['name'] as String,
      orgNumber: r['org_number'] as String,
      address: r['address'] as String,
    );
  }

  Future<void> saveProfile(BusinessProfile p) => db.insert(
      'business_profile',
      {
        'id': 1,
        'name': p.name.trim(),
        'org_number': p.orgNumber.trim(),
        'address': p.address.trim(),
        'updated_at': _now(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace);

  // ---------- VAT rates ----------

  Future<List<VatRate>> vatRates() async {
    final rows = await db.query('vat_rates', where: 'active = 1', orderBy: 'basis_points');
    return [for (final r in rows) VatRate(r['basis_points'] as int)];
  }

  Future<void> addVatRate(VatRate rate) => db.insert(
      'vat_rates', {'basis_points': rate.basisPoints, 'active': 1},
      conflictAlgorithm: ConflictAlgorithm.replace);

  // ---------- Categories ----------

  Future<List<Category>> categories({bool includeInactive = false}) async {
    final rows = await db.query('categories',
        where: includeInactive ? null : 'active = 1', orderBy: 'sort_order, id');
    return rows.map(_category).toList();
  }

  Category _category(Map<String, Object?> r) => Category(
        id: r['id'] as int,
        name: r['name'] as String,
        vat: VatRate(r['vat_bp'] as int),
        sortOrder: r['sort_order'] as int,
        active: (r['active'] as int) == 1,
      );

  /// Replaces the active category list with [list], in order. Categories
  /// that disappear are deactivated (not deleted) so old days keep their link.
  Future<void> saveCategories(List<Category> list) async {
    await db.transaction((txn) async {
      final existing = await txn.query('categories');
      final keepIds = list.where((c) => c.id != null).map((c) => c.id).toSet();
      for (final r in existing) {
        final id = r['id'] as int;
        if (!keepIds.contains(id) && (r['active'] as int) == 1) {
          await txn.update('categories', {'active': 0, 'updated_at': _now()},
              where: 'id = ?', whereArgs: [id]);
          await _audit(txn, 'category', id, 'deactivate', '${r['name']}');
        }
      }
      for (var i = 0; i < list.length; i++) {
        final c = list[i];
        final values = {
          'name': c.name.trim(),
          'vat_bp': c.vat.basisPoints,
          'sort_order': i,
          'active': 1,
          'updated_at': _now(),
        };
        if (c.id == null) {
          final id = await txn.insert('categories', {...values, 'created_at': _now()});
          await _audit(txn, 'category', id, 'create', '${c.name} ${c.vat.label}');
        } else {
          final before = existing.where((r) => r['id'] == c.id).toList();
          await txn.update('categories', values, where: 'id = ?', whereArgs: [c.id]);
          if (before.isNotEmpty &&
              (before.first['name'] != c.name.trim() ||
                  before.first['vat_bp'] != c.vat.basisPoints)) {
            await _audit(txn, 'category', c.id, 'update',
                '${before.first['name']} ${VatRate(before.first['vat_bp'] as int).label} -> ${c.name} ${c.vat.label}');
          }
        }
      }
    });
  }

  // ---------- Remembered label -> category mappings ----------

  static String normalizeLabel(String label) =>
      label.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  Future<Map<String, int>> categoryAliases() async {
    final rows = await db.rawQuery('''
      SELECT a.label, a.category_id FROM category_aliases a
      JOIN categories c ON c.id = a.category_id WHERE c.active = 1''');
    return {for (final r in rows) r['label'] as String: r['category_id'] as int};
  }

  Future<void> rememberAlias(String label, int categoryId) => db.insert(
      'category_aliases',
      {'label': normalizeLabel(label), 'category_id': categoryId, 'created_at': _now()},
      conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> forgetAlias(String label) =>
      db.delete('category_aliases', where: 'label = ?', whereArgs: [normalizeLabel(label)]);

  /// Z-report lines that are never counted ("Räknas inte med").
  Future<Set<String>> ignoredZLabels() async {
    final rows = await db.query('z_ignored_labels');
    return {for (final r in rows) r['label'] as String};
  }

  /// "Fält på Z-rapport": what a printed line is recorded as. A null
  /// category means the line is not counted. Several lines may point to the
  /// same category; their amounts are then added together.
  Future<void> setZLabelRule(String label, int? categoryId) async {
    final l = normalizeLabel(label);
    if (l.isEmpty) return;
    await db.transaction((txn) async {
      await txn.delete('category_aliases', where: 'label = ?', whereArgs: [l]);
      await txn.delete('z_ignored_labels', where: 'label = ?', whereArgs: [l]);
      if (categoryId == null) {
        await txn.insert('z_ignored_labels', {'label': l, 'created_at': _now()});
      } else {
        await txn.insert('category_aliases', {'label': l, 'category_id': categoryId, 'created_at': _now()});
      }
    });
  }

  Future<void> deleteZLabelRule(String label) async {
    final l = normalizeLabel(label);
    await db.delete('category_aliases', where: 'label = ?', whereArgs: [l]);
    await db.delete('z_ignored_labels', where: 'label = ?', whereArgs: [l]);
  }

  /// All rules, sorted by label: (label, category id or null = not counted).
  Future<List<({String label, int? categoryId})>> zLabelRules() async {
    final aliases = await categoryAliases();
    final ignored = await ignoredZLabels();
    final out = <({String label, int? categoryId})>[
      for (final e in aliases.entries) (label: e.key, categoryId: e.value),
      for (final l in ignored) (label: l, categoryId: null),
    ]..sort((a, b) => a.label.compareTo(b.label));
    return out;
  }

  // ---------- Scans ----------

  Future<int> saveScan({
    required String docType,
    required String ocrText,
    String? ocrJson,
    String? imagePath,
  }) =>
      db.insert('document_scans', {
        'doc_type': docType,
        'ocr_text': ocrText,
        'ocr_json': ocrJson,
        'image_path': imagePath,
        'created_at': _now(),
      });

  Future<Map<String, Object?>?> scan(int id) async {
    final rows = await db.query('document_scans', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : rows.first;
  }

  // ---------- Daily sales (Z-reports) ----------

  Future<int> saveDailySales(DailySales d) async {
    return db.transaction((txn) async {
      final values = {
        'business_date': d.businessDate,
        'z_number': d.zNumber,
        'reported_total_ore': d.reportedTotal.ore,
        'note': d.note,
        'source': d.meta.source.name,
        'manually_edited': d.meta.manuallyEdited ? 1 : 0,
        'confirmed': 1,
        'scan_id': d.meta.scanId,
        'updated_at': _now(),
      };
      int id;
      if (d.id == null) {
        id = await txn.insert('daily_sales', {...values, 'created_at': _now()});
        await _audit(txn, 'daily_sales', id, 'create', _dailyJson(d));
      } else {
        id = d.id!;
        final before = await _loadDaily(txn, id);
        await txn.update('daily_sales', {...values, 'manually_edited': 1},
            where: 'id = ?', whereArgs: [id]);
        await txn.delete('daily_sales_items', where: 'daily_sales_id = ?', whereArgs: [id]);
        await _audit(txn, 'daily_sales', id, 'update',
            jsonEncode({'before': before == null ? null : jsonDecode(_dailyJson(before)), 'after': jsonDecode(_dailyJson(d))}));
      }
      for (var i = 0; i < d.items.length; i++) {
        final it = d.items[i];
        await txn.insert('daily_sales_items', {
          'daily_sales_id': id,
          'category_id': it.categoryId,
          'category_name': it.categoryName,
          'vat_bp': it.vat.basisPoints,
          'amount_ore': it.amount.ore,
          'source_label': it.sourceLabel,
          'position': i,
        });
      }
      return id;
    });
  }

  Future<List<DailySales>> dailySalesBetween(String fromIso, String toIso) async {
    final rows = await db.query('daily_sales',
        where: 'business_date >= ? AND business_date <= ?',
        whereArgs: [fromIso, toIso],
        orderBy: 'business_date, id');
    return [for (final r in rows) await _dailyFromRow(db, r)];
  }

  Future<DailySales?> dailySales(int id) => _loadDaily(db, id);

  Future<List<DailySales>> findDuplicateDailySales(DailySales d) async {
    final rows = await db.query('daily_sales',
        where: 'business_date = ? AND id != ?', whereArgs: [d.businessDate, d.id ?? -1]);
    final out = <DailySales>[];
    for (final r in rows) {
      final z = r['z_number'] as String?;
      final total = r['reported_total_ore'] as int;
      final sameZ = z != null && z.isNotEmpty && z == d.zNumber;
      final sameTotal = total == d.reportedTotal.ore;
      if (sameZ || sameTotal || (z == null || z.isEmpty || d.zNumber == null)) {
        out.add(await _dailyFromRow(db, r));
      }
    }
    return out;
  }

  Future<void> deleteDailySales(int id) async {
    await db.transaction((txn) async {
      final before = await _loadDaily(txn, id);
      await txn.delete('daily_sales', where: 'id = ?', whereArgs: [id]);
      await _audit(txn, 'daily_sales', id, 'delete', before == null ? '' : _dailyJson(before));
    });
  }

  Future<DailySales?> _loadDaily(DatabaseExecutor ex, int id) async {
    final rows = await ex.query('daily_sales', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _dailyFromRow(ex, rows.first);
  }

  Future<DailySales> _dailyFromRow(DatabaseExecutor ex, Map<String, Object?> r) async {
    final id = r['id'] as int;
    final items = await ex.query('daily_sales_items',
        where: 'daily_sales_id = ?', whereArgs: [id], orderBy: 'position');
    return DailySales(
      id: id,
      businessDate: r['business_date'] as String,
      zNumber: r['z_number'] as String?,
      reportedTotal: Money(r['reported_total_ore'] as int),
      note: r['note'] as String,
      items: [
        for (final i in items)
          SalesItem(
            categoryId: i['category_id'] as int?,
            categoryName: i['category_name'] as String,
            vat: VatRate(i['vat_bp'] as int),
            amount: Money(i['amount_ore'] as int),
            sourceLabel: i['source_label'] as String?,
          ),
      ],
      meta: _meta(r),
    );
  }

  String _dailyJson(DailySales d) => jsonEncode({
        'datum': d.businessDate,
        'z': d.zNumber,
        'rapporterad_ore': d.reportedTotal.ore,
        'poster': [
          for (final i in d.items)
            {'kategori': i.categoryName, 'moms_bp': i.vat.basisPoints, 'ore': i.amount.ore},
        ],
      });

  // ---------- Invoices ----------

  Future<int> saveInvoice(Invoice inv) async {
    return db.transaction((txn) async {
      final values = {
        'invoice_date': inv.invoiceDate,
        'supplier': inv.supplier.trim(),
        'invoice_number': inv.invoiceNumber.trim(),
        'total_ore': inv.total.ore,
        'vat_total_ore': inv.vatTotal.ore,
        'vat_calculated': inv.vatCalculated ? 1 : 0,
        'due_date': inv.dueDate,
        'ocr_reference': inv.ocrReference.trim(),
        'source': inv.meta.source.name,
        'manually_edited': inv.meta.manuallyEdited ? 1 : 0,
        'confirmed': 1,
        'scan_id': inv.meta.scanId,
        'paid': inv.paid ? 1 : 0,
        'paid_date': inv.paid ? inv.paidDate : null,
        'bankgiro': inv.bankgiro.trim(),
        'plusgiro': inv.plusgiro.trim(),
        'cost_type': inv.costType,
        'updated_at': _now(),
      };
      int id;
      if (inv.id == null) {
        id = await txn.insert('invoices', {...values, 'created_at': _now()});
        await _audit(txn, 'invoice', id, 'create', _invoiceJson(inv));
      } else {
        id = inv.id!;
        final before = await _loadInvoice(txn, id);
        await txn.update('invoices', {...values, 'manually_edited': 1},
            where: 'id = ?', whereArgs: [id]);
        await txn.delete('invoice_vat', where: 'invoice_id = ?', whereArgs: [id]);
        await _audit(txn, 'invoice', id, 'update',
            jsonEncode({'before': before == null ? null : jsonDecode(_invoiceJson(before)), 'after': jsonDecode(_invoiceJson(inv))}));
      }
      for (final l in inv.vatLines) {
        await txn.insert('invoice_vat', {
          'invoice_id': id,
          'vat_bp': l.rate.basisPoints,
          'vat_ore': l.vat.ore,
          'net_ore': l.net?.ore,
          'gross_ore': l.gross?.ore,
          'calculated': l.calculated ? 1 : 0,
        });
      }
      return id;
    });
  }

  Future<List<Invoice>> invoicesBetween(String fromIso, String toIso) async {
    final rows = await db.query('invoices',
        where: 'invoice_date >= ? AND invoice_date <= ?',
        whereArgs: [fromIso, toIso],
        orderBy: 'invoice_date, id');
    return [for (final r in rows) await _invoiceFromRow(db, r)];
  }

  Future<Invoice?> invoice(int id) => _loadInvoice(db, id);

  /// Likely duplicates: same supplier + invoice number, or same date and
  /// amount (with matching supplier when both have one).
  /// Invoices that may be [inv] saved before. Asked about before saving;
  /// the user decides. The OCR number alone is enough (it is unique per
  /// faktura); otherwise the same supplier with the same invoice number, the
  /// same date and amount, or the same amount within 10 days (a misread date).
  Future<List<Invoice>> findDuplicateInvoices(Invoice inv) async {
    final rows = await db.query('invoices', where: 'id != ?', whereArgs: [inv.id ?? -1]);
    final out = <Invoice>[];
    String fold(String s) =>
        s.toLowerCase().replaceAll(RegExp('[åä]'), 'a').replaceAll('ö', 'o').replaceAll(RegExp(r'[^a-z0-9]'), '');
    final number = fold(inv.invoiceNumber);
    final ocr = inv.ocrReference.replaceAll(RegExp(r'\D'), '');
    final supplier = fold(inv.supplier);
    final day = SwedishDates.parseIso(inv.invoiceDate);
    bool sameSupplier(String other) {
      final o = fold(other);
      if (supplier.isEmpty || o.isEmpty) return true;
      return o == supplier || o.contains(supplier) || supplier.contains(o) || TextPatterns.similarity(o, supplier) >= 0.8;
    }

    for (final r in rows) {
      final rSupplier = r['supplier'] as String;
      final rOcr = (r['ocr_reference'] as String).replaceAll(RegExp(r'\D'), '');
      final sameOcr = ocr.length >= 5 && rOcr == ocr;
      final sameNumber = number.isNotEmpty && fold(r['invoice_number'] as String) == number && sameSupplier(rSupplier);
      final sameAmount = r['total_ore'] == inv.total.ore;
      final sameDateAmount = r['invoice_date'] == inv.invoiceDate && sameAmount && sameSupplier(rSupplier);
      final rDay = SwedishDates.parseIso(r['invoice_date'] as String);
      final nearby = sameAmount &&
          supplier.isNotEmpty &&
          fold(rSupplier).isNotEmpty &&
          sameSupplier(rSupplier) &&
          day != null &&
          rDay != null &&
          day.difference(rDay).inDays.abs() <= 10;
      if (sameOcr || sameNumber || sameDateAmount || nearby) out.add(await _invoiceFromRow(db, r));
    }
    return out;
  }

  Future<void> deleteInvoice(int id) async {
    await db.transaction((txn) async {
      final before = await _loadInvoice(txn, id);
      await txn.delete('invoices', where: 'id = ?', whereArgs: [id]);
      await _audit(txn, 'invoice', id, 'delete', before == null ? '' : _invoiceJson(before));
    });
  }

  // ---------- Online sales ----------

  Future<int> saveOnlineSale(OnlineSale s) => db.transaction((txn) async {
        final values = {
          'payment_date': s.paymentDate,
          'partner': s.partner.trim(),
          'document_number': s.documentNumber.trim(),
          'amount_ore': s.amount.ore,
          'vat_ore': s.vat.ore,
          'vat_bp': s.vatRate?.basisPoints,
          'source': s.meta.source.name,
          'manually_edited': s.meta.manuallyEdited ? 1 : 0,
          'confirmed': 1,
          'scan_id': s.meta.scanId,
          'updated_at': _now(),
        };
        final detail = '${s.paymentDate} ${s.partner} ${s.amount.ore}';
        if (s.id == null) {
          final id = await txn.insert('online_sales', {...values, 'created_at': _now()});
          await _audit(txn, 'online_sale', id, 'create', detail);
          return id;
        }
        await txn.update('online_sales', {...values, 'manually_edited': 1}, where: 'id = ?', whereArgs: [s.id]);
        await _audit(txn, 'online_sale', s.id, 'update', detail);
        return s.id!;
      });

  OnlineSale _online(Map<String, Object?> r) => OnlineSale(
        id: r['id'] as int,
        paymentDate: r['payment_date'] as String,
        partner: r['partner'] as String,
        documentNumber: r['document_number'] as String,
        amount: Money(r['amount_ore'] as int),
        vat: Money(r['vat_ore'] as int? ?? 0),
        vatRate: r['vat_bp'] == null ? null : VatRate(r['vat_bp'] as int),
        meta: _meta(r),
      );

  Future<OnlineSale?> onlineSale(int id) async {
    final rows = await db.query('online_sales', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _online(rows.first);
  }

  Future<List<OnlineSale>> onlineSalesBetween(String fromIso, String toIso) async {
    final rows = await db.query('online_sales',
        where: 'payment_date >= ? AND payment_date <= ?',
        whereArgs: [fromIso, toIso],
        orderBy: 'payment_date, id');
    return rows.map(_online).toList();
  }

  /// Same document number, or same partner, date and amount.
  Future<List<OnlineSale>> findDuplicateOnlineSales(OnlineSale s) async {
    final rows = await db.query('online_sales', where: 'id != ?', whereArgs: [s.id ?? -1]);
    final number = s.documentNumber.trim().toLowerCase();
    return rows.map(_online).where((o) {
      final sameNumber = number.isNotEmpty && o.documentNumber.trim().toLowerCase() == number;
      final samePayment = o.paymentDate == s.paymentDate &&
          o.amount == s.amount &&
          normalizeLabel(o.partner) == normalizeLabel(s.partner);
      return sameNumber || samePayment;
    }).toList();
  }

  Future<void> deleteOnlineSale(int id) => db.transaction((txn) async {
        await txn.delete('online_sales', where: 'id = ?', whereArgs: [id]);
        await _audit(txn, 'online_sale', id, 'delete', '');
      });

  Future<List<String>> knownPartners() async {
    final rows = await db.rawQuery("SELECT DISTINCT partner FROM online_sales WHERE partner != '' ORDER BY id DESC");
    return [for (final r in rows) r['partner'] as String];
  }

  /// Learned labels for [supplier]'s papers.
  Future<List<SupplierHint>> supplierHints(String supplier) async {
    final key = SupplierHints.key(supplier);
    if (key.length < 3) return const [];
    final rows = await db.query('supplier_hints', where: 'supplier_key = ?', whereArgs: [key]);
    return [
      for (final r in rows)
        if (HintField.byName(r['field'] as String) case final f?)
          SupplierHint(key, f, r['label'] as String, r['hits'] as int),
    ];
  }

  /// Remembers that [supplier] prints [field] after [label]. The same label
  /// again counts up; a new one replaces the old.
  Future<void> learnHint(String supplier, HintField field, String label) async {
    final key = SupplierHints.key(supplier);
    if (key.length < 3) return;
    final old = await db.query('supplier_hints',
        where: 'supplier_key = ? AND field = ?', whereArgs: [key, field.name], limit: 1);
    final hits = old.isNotEmpty && old.first['label'] == label ? (old.first['hits'] as int) + 1 : 1;
    await db.insert(
      'supplier_hints',
      {'supplier_key': key, 'supplier': supplier.trim(), 'field': field.name, 'label': label, 'hits': hits, 'updated_at': _now()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Everything learned, for Inställningar.
  Future<List<({String supplier, String key, HintField field, String label, int hits})>> allHints() async {
    final rows = await db.query('supplier_hints', orderBy: 'supplier, field');
    return [
      for (final r in rows)
        if (HintField.byName(r['field'] as String) case final f?)
          (supplier: r['supplier'] as String, key: r['supplier_key'] as String, field: f, label: r['label'] as String, hits: r['hits'] as int),
    ];
  }

  Future<void> forgetHint(String key, HintField field) =>
      db.delete('supplier_hints', where: 'supplier_key = ? AND field = ?', whereArgs: [key, field.name]);

  /// The cost type last chosen for [supplier], to suggest it again.
  Future<String?> lastCostType(String supplier) async {
    if (supplier.trim().isEmpty) return null;
    final rows = await db.query('invoices',
        columns: ['cost_type'],
        where: "lower(supplier) = lower(?) AND cost_type != ''",
        whereArgs: [supplier.trim()],
        orderBy: 'id DESC',
        limit: 1);
    return rows.isEmpty ? null : rows.first['cost_type'] as String;
  }

  Future<List<String>> knownSuppliers() async {
    final rows = await db.rawQuery("SELECT DISTINCT supplier FROM invoices WHERE supplier != ''");
    return [for (final r in rows) r['supplier'] as String];
  }

  /// "Markera som betald" / "Markera som obetald", with an audit entry.
  Future<void> setInvoicePaid(int id, {required bool paid, String? paidDate}) async {
    await db.transaction((txn) async {
      await txn.update(
          'invoices', {'paid': paid ? 1 : 0, 'paid_date': paid ? paidDate : null, 'updated_at': _now()},
          where: 'id = ?', whereArgs: [id]);
      await _audit(txn, 'invoice', id, paid ? 'paid' : 'unpaid', paid ? (paidDate ?? '') : '');
    });
  }

  /// Unpaid invoices, earliest due date first (no due date last).
  Future<List<Invoice>> unpaidInvoices() async {
    final rows = await db.query('invoices',
        where: 'paid = 0', orderBy: 'due_date IS NULL, due_date, invoice_date, id');
    return [for (final r in rows) await _invoiceFromRow(db, r)];
  }

  Future<Invoice?> _loadInvoice(DatabaseExecutor ex, int id) async {
    final rows = await ex.query('invoices', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _invoiceFromRow(ex, rows.first);
  }

  Future<Invoice> _invoiceFromRow(DatabaseExecutor ex, Map<String, Object?> r) async {
    final id = r['id'] as int;
    final vat = await ex.query('invoice_vat',
        where: 'invoice_id = ?', whereArgs: [id], orderBy: 'vat_bp DESC');
    return Invoice(
      id: id,
      invoiceDate: r['invoice_date'] as String,
      supplier: r['supplier'] as String,
      invoiceNumber: r['invoice_number'] as String,
      total: Money(r['total_ore'] as int),
      vatTotal: Money(r['vat_total_ore'] as int),
      vatCalculated: (r['vat_calculated'] as int) == 1,
      dueDate: r['due_date'] as String?,
      ocrReference: r['ocr_reference'] as String,
      paid: (r['paid'] as int? ?? 0) == 1,
      paidDate: r['paid_date'] as String?,
      bankgiro: r['bankgiro'] as String? ?? '',
      plusgiro: r['plusgiro'] as String? ?? '',
      costType: r['cost_type'] as String? ?? '',
      vatLines: [
        for (final v in vat)
          InvoiceVatLine(
            rate: VatRate(v['vat_bp'] as int),
            vat: Money(v['vat_ore'] as int),
            net: v['net_ore'] == null ? null : Money(v['net_ore'] as int),
            gross: v['gross_ore'] == null ? null : Money(v['gross_ore'] as int),
            calculated: (v['calculated'] as int) == 1,
          ),
      ],
      meta: _meta(r),
    );
  }

  String _invoiceJson(Invoice i) => jsonEncode({
        'datum': i.invoiceDate,
        'leverantor': i.supplier,
        'fakturanr': i.invoiceNumber,
        'betald': i.paid,
        'betaldatum': i.paidDate,
        'summa_ore': i.total.ore,
        'moms_ore': i.vatTotal.ore,
        'moms': [
          for (final l in i.vatLines) {'bp': l.rate.basisPoints, 'ore': l.vat.ore},
        ],
      });

  // ---------- Shared ----------

  RecordMeta _meta(Map<String, Object?> r) => RecordMeta(
        source: RecordSource.values.firstWhere((s) => s.name == r['source'],
            orElse: () => RecordSource.manual),
        manuallyEdited: (r['manually_edited'] as int) == 1,
        confirmed: (r['confirmed'] as int) == 1,
        scanId: r['scan_id'] as int?,
        createdAt: DateTime.tryParse(r['created_at'] as String),
        updatedAt: DateTime.tryParse(r['updated_at'] as String),
      );

  Future<void> _audit(DatabaseExecutor ex, String entity, int? id, String action, String details) =>
      ex.insert('audit_log', {
        'entity': entity,
        'entity_id': id,
        'action': action,
        'details': details,
        'at': _now(),
      });

  Future<List<Map<String, Object?>>> auditFor(String entity, int id) => db.query('audit_log',
      where: 'entity = ? AND entity_id = ?', whereArgs: [entity, id], orderBy: 'id');

  Future<List<RegistrationSummary>> recentRegistrations({int limit = 10}) async {
    final rows = await db.rawQuery('''
      SELECT 'invoice' AS kind, id, invoice_date AS date, total_ore AS amount,
             vat_total_ore AS vat, supplier AS title, confirmed, created_at,
             paid, due_date
      FROM invoices
      UNION ALL
      SELECT 'z' AS kind, d.id, d.business_date, d.reported_total_ore,
             0, COALESCE(d.z_number, ''), d.confirmed, d.created_at, 1, NULL
      FROM daily_sales d
      UNION ALL
      SELECT 'online' AS kind, o.id, o.payment_date, o.amount_ore,
             0, o.partner, o.confirmed, o.created_at, 1, NULL
      FROM online_sales o
      ORDER BY created_at DESC LIMIT ?''', [limit]);
    return [
      for (final r in rows)
        RegistrationSummary(
          kind: r['kind'] as String,
          id: r['id'] as int,
          date: r['date'] as String,
          amount: Money(r['amount'] as int),
          vat: Money(r['vat'] as int),
          title: r['title'] as String,
          confirmed: (r['confirmed'] as int) == 1,
          createdAt: DateTime.parse(r['created_at'] as String),
          paid: (r['paid'] as int? ?? 0) == 1,
          dueDate: r['due_date'] as String?,
        ),
    ];
  }

  Future<int> documentCount({String? fromIso, String? toIso}) async {
    final where = fromIso == null ? '' : ' WHERE substr(created_at, 1, 10) BETWEEN ? AND ?';
    final args = fromIso == null ? <Object>[] : [fromIso, toIso!];
    final a = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM invoices$where', args)) ?? 0;
    final b = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM daily_sales$where', args)) ?? 0;
    final c = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM online_sales$where', args)) ?? 0;
    return a + b + c;
  }
}
