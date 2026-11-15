import 'package:flutter/foundation.dart';

import '../common/money.dart';

/// The two kinds of payment a collector takes (backend `CollectorPaymentType`):
/// a deposit into the member's savings account, or a share purchase into
/// their shares account.
enum PaymentType {
  savings('SAVINGS', 'Savings', 'Savings deposit'),
  shares('SHARES', 'Shares', 'Share purchase');

  const PaymentType(this.wireName, this.label, this.description);

  /// As the backend writes it.
  final String wireName;

  /// Short label, for the type picker.
  final String label;

  /// What the payment is, for the confirm and saved screens.
  final String description;

  static PaymentType? fromWire(Object? value) {
    for (final type in values) {
      if (type.wireName == value) return type;
    }
    return null;
  }
}

/// One of a member's accounts a collector can pay into. The backend only
/// sends savings and shares accounts here, so each maps to a [PaymentType].
@immutable
class MemberAccount {
  const MemberAccount({required this.accountNumber, required this.type});

  final String accountNumber;
  final PaymentType type;

  @override
  bool operator ==(Object other) =>
      other is MemberAccount &&
      other.accountNumber == accountNumber &&
      other.type == type;

  @override
  int get hashCode => Object.hash(accountNumber, type);
}

/// A member as a collector may see them: the name and the accounts they can
/// record against, nothing else (owner decision 2026-11-07).
@immutable
class CollectorMember {
  const CollectorMember({required this.name, required this.accounts});

  final String name;
  final List<MemberAccount> accounts;

  MemberAccount? accountFor(PaymentType type) {
    for (final account in accounts) {
      if (account.type == type) return account;
    }
    return null;
  }

  /// Payment types this member has an account for, savings first.
  List<PaymentType> get paymentTypes => [
        for (final type in PaymentType.values)
          if (accountFor(type) != null) type,
      ];

  /// Parses one entry of `GET /api/collector/v1/members`:
  /// `{memberName, accounts: [{accountNumber, accountType}]}`. Accounts of
  /// any other type are skipped. Returns null if the entry is malformed.
  static CollectorMember? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final name = json['memberName'];
    final accounts = json['accounts'];
    if (name is! String || accounts is! List) return null;
    final parsed = <MemberAccount>[];
    for (final entry in accounts) {
      if (entry is! Map<String, dynamic>) continue;
      final number = entry['accountNumber'];
      final type = PaymentType.fromWire(entry['accountType']);
      if (number is String && number.isNotEmpty && type != null) {
        parsed.add(MemberAccount(accountNumber: number, type: type));
      }
    }
    return CollectorMember(name: name, accounts: List.unmodifiable(parsed));
  }
}

/// A payment's state on the backend (`TransactionStatus`). A collector
/// payment is PENDING during its 10-minute correction window, then
/// COMPLETED (balance updated, member texted) or FAILED.
enum PaymentStatus {
  pending,
  completed,
  failed,
  unknown;

  static PaymentStatus fromWire(Object? value) => switch (value) {
        'PENDING' => pending,
        'COMPLETED' => completed,
        'FAILED' => failed,
        _ => unknown,
      };
}

/// A payment as the backend returns it (`CollectorPaymentResponse`).
@immutable
class CollectorPayment {
  const CollectorPayment({
    required this.transactionId,
    required this.idempotencyKey,
    required this.type,
    required this.accountNumber,
    required this.memberName,
    required this.amount,
    required this.status,
    this.failureReason,
    this.createdAt,
    this.correctableUntil,
  });

  final String transactionId;
  final String idempotencyKey;
  final PaymentType type;
  final String accountNumber;
  final String memberName;
  final Cedis amount;
  final PaymentStatus status;
  final String? failureReason;

  /// Server times, without a zone (the backend uses LocalDateTime).
  final DateTime? createdAt;

  /// When the 10-minute correction window closes; null for payments
  /// recorded offline, which are final on arrival.
  final DateTime? correctableUntil;

  /// How long the correction window has left, measured on the server's own
  /// clock (`correctableUntil - createdAt`), so a wrong phone clock can't
  /// change it. Zero when there's no window.
  Duration get correctionWindow {
    final until = correctableUntil;
    final created = createdAt;
    if (until == null || created == null) return Duration.zero;
    final window = until.difference(created);
    return window.isNegative ? Duration.zero : window;
  }

  static CollectorPayment? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['transactionId'];
    final key = json['idempotencyKey'];
    final type = PaymentType.fromWire(json['type']);
    final account = json['accountNumber'];
    final name = json['memberName'];
    final amount = Cedis.fromJson(json['amount']);
    if (id is! String ||
        key is! String ||
        type == null ||
        account is! String ||
        name is! String ||
        amount == null) {
      return null;
    }
    final reason = json['failureReason'];
    return CollectorPayment(
      transactionId: id,
      idempotencyKey: key,
      type: type,
      accountNumber: account,
      memberName: name,
      amount: amount,
      status: PaymentStatus.fromWire(json['status']),
      failureReason: reason is String ? reason : null,
      createdAt: _time(json['createdAt']),
      correctableUntil: _time(json['correctableUntil']),
    );
  }

  static DateTime? _time(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}
