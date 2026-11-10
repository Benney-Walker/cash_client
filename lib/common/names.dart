/// The backend sends names in upper case ("KOFI MENSAH"); show them in
/// normal case ("Kofi Mensah").
String displayName(String name) => name
    .trim()
    .split(RegExp(r'\s+'))
    .where((part) => part.isNotEmpty)
    .map((part) => part[0].toUpperCase() + part.substring(1).toLowerCase())
    .join(' ');
