import '../constants/app_constants.dart';

/// Localizes a raw category/skill value (a slug like `plumber` or an English/
/// Hindi trade name like `Plumbing`/`प्लंबर`) coming from the backend/DB into
/// the user's selected language.
///
/// Categories are a fixed enum, so this is deterministic and instant — no
/// backend round-trip or LLM needed. Unknown free-text values (e.g. a bio or an
/// unmapped trade) are returned unchanged, which is acceptable for the rare
/// item that cannot be translated.
String localizeCategory(String? raw, String locale) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return '';
  final norm = value.toLowerCase();

  final match = _findCategory(norm, value) ?? _matchByKeyword(norm);
  return match?.nameFor(locale) ?? value;
}

/// Localizes + de-duplicates a list of category/skill values by localized label.
List<String> localizeCategoryList(Iterable<String> raw, String locale) {
  final seen = <String>{};
  final out = <String>[];
  for (final r in raw) {
    final label = localizeCategory(r, locale);
    if (label.isNotEmpty && seen.add(label.toLowerCase())) out.add(label);
  }
  return out;
}

ServiceCategory? _findCategory(String norm, String original) {
  for (final c in ServiceCategories.all) {
    if (c.id == norm ||
        c.nameEn.toLowerCase() == norm ||
        c.nameHi == original ||
        (c.translations?.values.any((t) => t.toLowerCase() == norm) ?? false)) {
      return c;
    }
  }
  return null;
}

ServiceCategory? _matchByKeyword(String norm) {
  const keywordToId = <String, String>{
    'plumb': 'plumber',
    'elect': 'electrician',
    'carp': 'carpenter',
    'wood': 'carpenter',
    'furnit': 'carpenter',
    'paint': 'painter',
    'garden': 'gardener',
    'plant': 'gardener',
    'clean': 'cleaning',
    'maid': 'domestic_helper',
    'domestic': 'domestic_helper',
    'helper': 'domestic_helper',
    'driv': 'driver',
    'care': 'caregiving',
    'tech': 'technician',
    'applianc': 'technician',
    'hvac': 'technician',
  };
  for (final entry in keywordToId.entries) {
    if (norm.contains(entry.key)) {
      for (final c in ServiceCategories.all) {
        if (c.id == entry.value) return c;
      }
    }
  }
  return null;
}
