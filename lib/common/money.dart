import 'package:flutter/foundation.dart';

/// An amount of Ghana cedis, held as a whole number of pesewas so no
/// floating-point rounding ever touches money.
///
/// Collectors enter amounts to 2 decimal places (owner decision,
/// 15 Nov 2026), and every amount in the app is shown as "GH₵ 1,240.00".
@immutable
class Cedis implements Comparable<Cedis> {
  const Cedis.pesewas(this.pesewas);

  static const zero = Cedis.pesewas(0);

  /// The largest amount the entry field accepts: 9 digits of cedis. Well
  /// inside the backend's DECIMAL(19,4) and the range ints hold exactly.
  static const max = Cedis.pesewas(99999999999);

  final int pesewas;

  /// Reads what a collector typed: "50", "50.", "50.5" or "50.50".
  /// Returns null for anything else, including more than 2 decimal places.
  static Cedis? tryParse(String text) {
    final match = RegExp(r'^(\d+)(?:\.(\d{0,2}))?$').firstMatch(text.trim());
    if (match == null) return null;
    final whole = match.group(1)!;
    if (whole.length > 9) return null;
    final fraction = (match.group(2) ?? '').padRight(2, '0');
    return Cedis.pesewas(int.parse(whole) * 100 + int.parse(fraction));
  }

  /// Reads an amount from a backend response. JSON numbers arrive as
  /// doubles, so this rounds to the nearest pesewa; it's for showing
  /// amounts, never for sending them back.
  static Cedis? fromJson(Object? value) {
    if (value is int) return Cedis.pesewas(value * 100);
    if (value is double && value.isFinite) {
      return Cedis.pesewas((value * 100).round());
    }
    if (value is String) return tryParse(value);
    return null;
  }

  bool get isPositive => pesewas > 0;

  /// The plain decimal the backend expects, such as `50.50`. It's written
  /// into the request body as a JSON number literal (see CollectorApi), so
  /// Jackson reads it straight into a BigDecimal with no float in between.
  String toDecimalString() {
    final whole = pesewas ~/ 100;
    final fraction = (pesewas % 100).toString().padLeft(2, '0');
    return '$whole.$fraction';
  }

  /// "GH₵ 1,240.00".
  String format() {
    final whole = (pesewas ~/ 100).toString();
    final fraction = (pesewas % 100).toString().padLeft(2, '0');
    final grouped = whole.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return 'GH₵ $grouped.$fraction';
  }

  @override
  int compareTo(Cedis other) => pesewas.compareTo(other.pesewas);

  @override
  bool operator ==(Object other) => other is Cedis && other.pesewas == pesewas;

  @override
  int get hashCode => pesewas.hashCode;

  @override
  String toString() => format();
}
