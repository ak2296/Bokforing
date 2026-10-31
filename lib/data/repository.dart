import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../domain/models.dart';
import '../domain/money.dart';
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
  Future<List<Invoice>> findDuplicateInvoices(Invoice inv) async {
    final rows = await db.query('invoices', where: 'id != ?', whereArgs: [inv.id ?? -1]);
    final out = <Invoice>[];
    final number = inv.invoiceNumber.trim().toLowerCase();
    final supplier = inv.supplier.trim().toLowerCase();
    for (final r in rows) {
      final rNumber = (r['invoice_number'] as String).trim().toLowerCase();
      final rSupplier = (r['supplier'] as String).trim().toLowerCase();
      final sameNumber = number.isNotEmpty && rNumber == number &&
          (supplier.isEmpty || rSupplier.isEmpty || rSupplier == supplier);
      final sameDateAmount = r['invoice_date'] == inv.invoiceDate &&
          r['total_ore'] == inv.total.ore &&
          (supplier.isEmpty || rSupplier.isEmpty || rSupplier == supplier);
      if (sameNumber || sameDateAmount) out.add(await _invoiceFromRow(db, r));
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
             vat_total_ore AS vat, supplier AS title, confirmed, created_at
      FROM invoices
      UNION ALL
      SELECT 'z' AS kind, d.id, d.business_date, d.reported_total_ore,
             0, COALESCE(d.z_number, ''), d.confirmed, d.created_at
      FROM daily_sales d
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
        ),
    ];
  }

  Future<int> documentCount({String? fromIso, String? toIso}) async {
    final where = fromIso == null ? '' : ' WHERE substr(created_at, 1, 10) BETWEEN ? AND ?';
    final args = fromIso == null ? <Object>[] : [fromIso, toIso!];
    final a = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM invoices$where', args)) ?? 0;
    final b = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM daily_sales$where', args)) ?? 0;
    return a + b;
  }
}
