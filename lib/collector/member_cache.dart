import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'collector_models.dart';

/// The branch member list as last downloaded, and when.
@immutable
class SavedMembers {
  const SavedMembers({required this.members, required this.savedAt});

  final List<CollectorMember> members;

  /// Phone time when the list was downloaded.
  final DateTime savedAt;
}

/// Keeps the branch member list on the phone, so collectors can look up
/// members without a connection (app spec 2.2).
///
/// It holds only what the backend sends collectors: names and savings and
/// shares account numbers. It's cleared when the session ends.
abstract interface class MemberCache {
  Future<SavedMembers?> read();

  /// Replaces the whole list.
  Future<void> save(List<CollectorMember> members, DateTime savedAt);
  Future<void> clear();
}

/// [MemberCache] in the app's SQLite database (owner decision 2026-11-15:
/// SQLite, through sqflite).
class SqliteMemberCache implements MemberCache {
  SqliteMemberCache({this.fileName = 'cash_client.db'});

  final String fileName;
  Future<Database>? _db;

  static const _savedAtKey = 'members_saved_at';

  Future<Database> get _database => _db ??= _open();

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), fileName);
    return openDatabase(
      path,
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
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
      },
    );
  }

  @override
  Future<SavedMembers?> read() async {
    final db = await _database;
    final meta = await db.query(
      'sync_meta',
      where: 'key = ?',
      whereArgs: [_savedAtKey],
    );
    if (meta.isEmpty) return null;
    final savedAt = DateTime.tryParse(meta.first['value'] as String);
    if (savedAt == null) return null;

    final rows = await db.rawQuery('''
      SELECT m.id, m.name, a.account_number, a.payment_type
      FROM members m
      LEFT JOIN member_accounts a ON a.member_id = m.id
      ORDER BY m.id, a.payment_type''');

    final members = <CollectorMember>[];
    int? currentId;
    String? currentName;
    var accounts = <MemberAccount>[];
    void flush() {
      if (currentId != null) {
        members.add(CollectorMember(
          name: currentName!,
          accounts: List.unmodifiable(accounts),
        ));
      }
    }

    for (final row in rows) {
      final id = row['id'] as int;
      if (id != currentId) {
        flush();
        currentId = id;
        currentName = row['name'] as String;
        accounts = <MemberAccount>[];
      }
      final number = row['account_number'] as String?;
      final type = PaymentType.fromWire(row['payment_type']);
      if (number != null && type != null) {
        accounts.add(MemberAccount(accountNumber: number, type: type));
      }
    }
    flush();
    return SavedMembers(members: List.unmodifiable(members), savedAt: savedAt);
  }

  @override
  Future<void> save(List<CollectorMember> members, DateTime savedAt) async {
    final db = await _database;
    // One transaction, so a crash halfway never leaves a mixed list.
    await db.transaction((txn) async {
      await txn.delete('member_accounts');
      await txn.delete('members');
      final batch = txn.batch();
      for (var i = 0; i < members.length; i++) {
        batch.insert('members', {'id': i, 'name': members[i].name});
        for (final account in members[i].accounts) {
          batch.insert(
            'member_accounts',
            {
              'account_number': account.accountNumber,
              'member_id': i,
              'payment_type': account.type.wireName,
            },
            // An account number the backend sent twice keeps its last row
            // rather than failing the whole save.
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      batch.insert(
        'sync_meta',
        {'key': _savedAtKey, 'value': savedAt.toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<void> clear() async {
    final db = await _database;
    await db.transaction((txn) async {
      await txn.delete('member_accounts');
      await txn.delete('members');
      await txn.delete('sync_meta', where: 'key = ?', whereArgs: [_savedAtKey]);
    });
  }
}

/// Picks members by name or account number, for the member picker.
List<CollectorMember> searchMembers(
  List<CollectorMember> members,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return members;
  return [
    for (final member in members)
      if (member.name.toLowerCase().contains(q) ||
          member.accounts.any((a) => a.accountNumber.contains(q)))
        member,
  ];
}
