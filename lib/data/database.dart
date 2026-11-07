import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Local SQLite database. All money columns are integer öre (`*_ore`) and all
/// VAT rates are basis points (`*_bp`). Totals are derived, never stored,
/// except amounts printed on the document itself (e.g. reported Z total).
class AppDatabase {
  static const fileName = 'bokforing.db';
  static const version = 7;

  static Future<Database> open({DatabaseFactory? factory, String? path}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), fileName);
    var shrink = false;
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => _create(db),
        onUpgrade: (db, oldVersion, _) async {
          if (oldVersion < 2) await _createV2(db);
          if (oldVersion < 3) await _upgradeToV3(db);
          if (oldVersion < 4) {
            final batch = db.batch();
            _v4Tables(batch);
            await batch.commit(noResult: true);
          }
          if (oldVersion < 5) {
            final batch = db.batch();
            _v5Changes(batch);
            await batch.commit(noResult: true);
          }
          if (oldVersion < 6) {
            final batch = db.batch();
            _v6Changes(batch);
            await batch.commit(noResult: true);
          }
          if (oldVersion < 7) {
            // The word layout of each scan was kept but never read again.
            await db.execute('UPDATE document_scans SET ocr_json = NULL');
            shrink = true;
          }
        },
      ),
    );
    // VACUUM gives the freed space back to the phone; it cannot run inside
    // the upgrade transaction.
    if (shrink) await db.execute('VACUUM');
    return db;
  }

  static Future<void> _create(Database db) async {
    final batch = db.batch();
    batch.execute('''
      CREATE TABLE business_profile (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        name TEXT NOT NULL DEFAULT '',
        org_number TEXT NOT NULL DEFAULT '',
        address TEXT NOT NULL DEFAULT '',
        updated_at TEXT NOT NULL
      )''');
    batch.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )''');
    batch.execute('''
      CREATE TABLE vat_rates (
        basis_points INTEGER PRIMARY KEY,
        active INTEGER NOT NULL DEFAULT 1
      )''');
    batch.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        vat_bp INTEGER NOT NULL,
        sort_order INTEGER NOT NULL,
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )''');
    batch.execute('''
      CREATE TABLE category_aliases (
        label TEXT PRIMARY KEY,
        category_id INTEGER NOT NULL REFERENCES categories(id),
        created_at TEXT NOT NULL
      )''');
    batch.execute('''
      CREATE TABLE document_scans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        doc_type TEXT NOT NULL,
        ocr_text TEXT NOT NULL,
        ocr_json TEXT,
        image_path TEXT,
        created_at TEXT NOT NULL
      )''');
    batch.execute('''
      CREATE TABLE daily_sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        business_date TEXT NOT NULL,
        z_number TEXT,
        reported_total_ore INTEGER NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        source TEXT NOT NULL,
        manually_edited INTEGER NOT NULL DEFAULT 0,
        confirmed INTEGER NOT NULL DEFAULT 0,
        scan_id INTEGER REFERENCES document_scans(id),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )''');
    batch.execute('CREATE INDEX idx_daily_sales_date ON daily_sales(business_date)');
    batch.execute('''
      CREATE TABLE daily_sales_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        daily_sales_id INTEGER NOT NULL REFERENCES daily_sales(id) ON DELETE CASCADE,
        category_id INTEGER REFERENCES categories(id),
        category_name TEXT NOT NULL,
        vat_bp INTEGER NOT NULL,
        amount_ore INTEGER NOT NULL,
        source_label TEXT,
        position INTEGER NOT NULL
      )''');
    batch.execute('''
      CREATE TABLE invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_date TEXT NOT NULL,
        supplier TEXT NOT NULL DEFAULT '',
        invoice_number TEXT NOT NULL DEFAULT '',
        total_ore INTEGER NOT NULL,
        vat_total_ore INTEGER NOT NULL,
        vat_calculated INTEGER NOT NULL DEFAULT 0,
        due_date TEXT,
        ocr_reference TEXT NOT NULL DEFAULT '',
        source TEXT NOT NULL,
        manually_edited INTEGER NOT NULL DEFAULT 0,
        confirmed INTEGER NOT NULL DEFAULT 0,
        scan_id INTEGER REFERENCES document_scans(id),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )''');
    batch.execute('CREATE INDEX idx_invoices_date ON invoices(invoice_date)');
    batch.execute('''
      CREATE TABLE invoice_vat (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id INTEGER NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
        vat_bp INTEGER NOT NULL,
        vat_ore INTEGER NOT NULL,
        net_ore INTEGER,
        gross_ore INTEGER,
        calculated INTEGER NOT NULL DEFAULT 0
      )''');
    batch.execute('''
      CREATE TABLE audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity TEXT NOT NULL,
        entity_id INTEGER,
        action TEXT NOT NULL,
        details TEXT NOT NULL DEFAULT '',
        at TEXT NOT NULL
      )''');
    _v2Tables(batch);
    _v3Changes(batch);
    _v4Tables(batch);
    _v5Changes(batch);
    _v6Changes(batch);
    for (final bp in const [0, 600, 1200, 2500]) {
      batch.insert('vat_rates', {'basis_points': bp, 'active': 1});
    }
    await batch.commit(noResult: true);
  }

  /// v2: Z-report lines the owner chose not to count ("Räknas inte med").
  static void _v2Tables(Batch batch) {
    batch.execute('''
      CREATE TABLE IF NOT EXISTS z_ignored_labels (
        label TEXT PRIMARY KEY,
        created_at TEXT NOT NULL
      )''');
  }

  static Future<void> _createV2(Database db) async {
    final batch = db.batch();
    _v2Tables(batch);
    await batch.commit(noResult: true);
  }

  /// v3: payment status and payment details on invoices, and whether a
  /// supplier's documents are receipts (paid) or invoices (to pay).
  static void _v3Changes(Batch batch) {
    batch.execute('ALTER TABLE invoices ADD COLUMN paid INTEGER NOT NULL DEFAULT 0');
    batch.execute('ALTER TABLE invoices ADD COLUMN paid_date TEXT');
    batch.execute("ALTER TABLE invoices ADD COLUMN bankgiro TEXT NOT NULL DEFAULT ''");
    batch.execute("ALTER TABLE invoices ADD COLUMN plusgiro TEXT NOT NULL DEFAULT ''");
    batch.execute('''
      CREATE TABLE IF NOT EXISTS supplier_payment_kinds (
        supplier TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        created_at TEXT NOT NULL
      )''');
  }

  static Future<void> _upgradeToV3(Database db) async {
    final batch = db.batch();
    _v3Changes(batch);
    // Invoices saved before payment tracking existed are treated as paid so
    // they do not suddenly trigger reminders.
    batch.execute('UPDATE invoices SET paid = 1');
    await batch.commit(noResult: true);
  }

  /// v4: payouts from delivery partners (online sales).
  /// v5: moms on an online sale, when the partner's paper shows it.
  static void _v5Changes(Batch batch) {
    batch.execute('ALTER TABLE online_sales ADD COLUMN vat_ore INTEGER NOT NULL DEFAULT 0');
    batch.execute('ALTER TABLE online_sales ADD COLUMN vat_bp INTEGER');
  }

  /// v6: cost type of an invoice, for the resultatrapport and SIE export.
  static void _v6Changes(Batch batch) {
    batch.execute("ALTER TABLE invoices ADD COLUMN cost_type TEXT NOT NULL DEFAULT ''");
  }

  static void _v4Tables(Batch batch) {
    batch.execute('''
      CREATE TABLE IF NOT EXISTS online_sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        payment_date TEXT NOT NULL,
        partner TEXT NOT NULL DEFAULT '',
        document_number TEXT NOT NULL DEFAULT '',
        amount_ore INTEGER NOT NULL,
        source TEXT NOT NULL,
        manually_edited INTEGER NOT NULL DEFAULT 0,
        confirmed INTEGER NOT NULL DEFAULT 0,
        scan_id INTEGER REFERENCES document_scans(id),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )''');
    batch.execute('CREATE INDEX IF NOT EXISTS idx_online_sales_date ON online_sales(payment_date)');
  }
}
