/// The backend sends names in upper case ("KOFI MENSAH"); show them in
/// normal case ("Kofi Mensah").
String displayName(String name) => name
    .trim()
    .split(RegExp(r'\s+'))
    .where((part) => part.isNotEmpty)
    .map((part) => part[0].toUpperCase() + part.substring(1).toLowerCase())
    .join(' ');

/// Up to two initials for an avatar: "KOFI MENSAH" gives "KM", "EFUA"
/// gives "E". Uses the first and last names, so middle names don't push
/// the surname out.
String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return '?';
  final first = parts.first[0];
  final last = parts.length > 1 ? parts.last[0] : '';
  return (first + last).toUpperCase();
}
