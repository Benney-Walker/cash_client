import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// The app's one SQLite database (owner decision 2026-11-15: SQLite through
/// sqflite), shared by the member list and the outbox.
///
/// Opened lazily, once per isolate. The background sync opens its own
/// connection to the same file; SQLite's locking keeps the two consistent.
class AppDatabase {
  AppDatabase({this.fileName = 'cash_client.db'});

  final String fileName;
  Future<Database>? _db;

  /// Version 1: member list. Version 2: outbox. Version 3: locks shared
  /// between the app and the background sync. Version 4: each outbox
  /// payment's last correction time.
  static const version = 4;

  Future<Database> get database => _db ??= _open();

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), fileName);
    return openDatabase(
      path,
      version: version,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await _createMemberTables(db);
        await _createOutbox(db);
        await _createLocks(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createOutbox(db);
        if (oldVersion < 3) await _createLocks(db);
        // Created fresh above from version 2 on, with the column already.
        if (oldVersion >= 2 && oldVersion < 4) {
          await db.execute('ALTER TABLE outbox ADD COLUMN updated_at TEXT');
          await db.execute('UPDATE outbox SET updated_at = recorded_at');
        }
      },
    );
  }

  static Future<void> _createMemberTables(Database db) async {
    // Members are numbered in the order the backend sent them; account
    // numbers are unique across the credit union, so they're the key.
    await db.execute('''
      CREATE TABLE members (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE member_accounts (
        account_number TEXT PRIMARY KEY,
        member_id INTEGER NOT NULL
          REFERENCES members (id) ON DELETE CASCADE,
        payment_type TEXT NOT NULL
      )''');
    await db.execute(
      'CREATE INDEX member_accounts_member ON member_accounts (member_id)',
    );
    await db.execute('''
      CREATE TABLE sync_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )''');
  }

  /// Named locks with a lease, such as the one that lets only one isolate
  /// refresh the session at a time (`RefreshLock`).
  static Future<void> _createLocks(Database db) async {
    await db.execute('''
      CREATE TABLE app_locks (
        name TEXT PRIMARY KEY,
        owner TEXT NOT NULL,
        held_until TEXT NOT NULL
      )''');
  }

  /// Payments recorded without a connection, until the backend has them.
  ///
  /// Times are UTC ISO-8601 text. `recorded_at` is the payment's phone
  /// `createdAt` and `updated_at` its last correction. A row is deleted once
  /// the backend has saved the payment; until then it's held (inside its 5
  /// minutes, correctable), ready to send, or refused (refusal_reason set).
  static Future<void> _createOutbox(Database db) async {
    await db.execute('''
      CREATE TABLE outbox (
        idempotency_key TEXT PRIMARY KEY,
        staff_id TEXT NOT NULL,
        member_name TEXT NOT NULL,
        account_number TEXT NOT NULL,
        payment_type TEXT NOT NULL,
        amount_pesewas INTEGER NOT NULL,
        description TEXT,
        recorded_at TEXT NOT NULL,
        updated_at TEXT,
        refusal_reason TEXT,
        refused_at TEXT,
        last_tried_at TEXT,
        notified INTEGER NOT NULL DEFAULT 0,
        claimed_until TEXT
      )''');
    await db.execute(
      'CREATE INDEX outbox_staff ON outbox (staff_id, recorded_at)',
    );
  }
}
