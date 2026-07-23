/// Resolves a country flag for a proxy node from its display name — first by
/// reading any regional-indicator emoji already in the name, then by matching
/// country names/abbreviations (English + Russian). Windows can't render the
/// emoji itself, so the bundled Twemoji font is used at draw time.
class CountryFlags {
  CountryFlags._();

  /// Full country names (len ≥ 4, safe for substring matching) → ISO-3166-1.
  static const _names = <String, String>{
    'germany': 'DE', 'германия': 'DE', 'deutschland': 'DE', 'frankfurt': 'DE',
    'finland': 'FI', 'финляндия': 'FI', 'helsinki': 'FI',
    'netherlands': 'NL', 'holland': 'NL', 'нидерланды': 'NL', 'amsterdam': 'NL',
    'united kingdom': 'GB', 'britain': 'GB', 'england': 'GB', 'британия': 'GB',
    'англия': 'GB', 'london': 'GB', 'лондон': 'GB',
    'united states': 'US', 'america': 'US', 'сша': 'US', 'америка': 'US',
    'france': 'FR', 'франция': 'FR', 'paris': 'FR', 'париж': 'FR',
    'sweden': 'SE', 'швеция': 'SE', 'stockholm': 'SE',
    'estonia': 'EE', 'эстония': 'EE',
    'russia': 'RU', 'россия': 'RU', 'moscow': 'RU', 'москва': 'RU',
    'poland': 'PL', 'польша': 'PL', 'warsaw': 'PL',
    'turkey': 'TR', 'турция': 'TR', 'istanbul': 'TR',
    'japan': 'JP', 'япония': 'JP', 'tokyo': 'JP',
    'singapore': 'SG', 'сингапур': 'SG',
    'hong kong': 'HK', 'hongkong': 'HK', 'гонконг': 'HK',
    'canada': 'CA', 'канада': 'CA',
    'switzerland': 'CH', 'швейцария': 'CH', 'zurich': 'CH',
    'norway': 'NO', 'норвегия': 'NO',
    'spain': 'ES', 'испания': 'ES', 'madrid': 'ES',
    'italy': 'IT', 'италия': 'IT', 'milan': 'IT',
    'ukraine': 'UA', 'украина': 'UA', 'kyiv': 'UA',
    'latvia': 'LV', 'латвия': 'LV',
    'lithuania': 'LT', 'литва': 'LT',
    'austria': 'AT', 'австрия': 'AT', 'vienna': 'AT',
    'ireland': 'IE', 'ирландия': 'IE',
    'india': 'IN', 'индия': 'IN', 'mumbai': 'IN',
    'australia': 'AU', 'австралия': 'AU', 'sydney': 'AU',
    'brazil': 'BR', 'бразилия': 'BR',
    'emirates': 'AE', 'dubai': 'AE', 'дубай': 'AE', 'оаэ': 'AE',
    'czech': 'CZ', 'чехия': 'CZ', 'prague': 'CZ',
    'denmark': 'DK', 'дания': 'DK',
    'belgium': 'BE', 'бельгия': 'BE',
    'romania': 'RO', 'румыния': 'RO',
    'korea': 'KR', 'корея': 'KR', 'seoul': 'KR',
    'kazakhstan': 'KZ', 'казахстан': 'KZ',
    'iran': 'IR', 'иран': 'IR',
    'china': 'CN', 'китай': 'CN',
    'hungary': 'HU', 'венгрия': 'HU',
    'bulgaria': 'BG', 'болгария': 'BG',
    'serbia': 'RS', 'сербия': 'RS',
    'greece': 'GR', 'греция': 'GR', 'athens': 'GR',
    'portugal': 'PT', 'португалия': 'PT',
    'moldova': 'MD', 'молдова': 'MD',
    'armenia': 'AM', 'армения': 'AM',
    'georgia': 'GE', 'грузия': 'GE',
  };

  /// Standalone token abbreviations (matched only as whole words).
  static const _codes = <String, String>{
    'de': 'DE', 'fi': 'FI', 'nl': 'NL', 'uk': 'GB', 'gb': 'GB', 'usa': 'US',
    'us': 'US', 'fr': 'FR', 'se': 'SE', 'ee': 'EE', 'ru': 'RU', 'pl': 'PL',
    'tr': 'TR', 'jp': 'JP', 'sg': 'SG', 'hk': 'HK', 'ca': 'CA', 'ch': 'CH',
    'es': 'ES', 'it': 'IT', 'ua': 'UA', 'uae': 'AE', 'kz': 'KZ', 'kr': 'KR',
  };

  /// ISO-3166-1 alpha-2 for a name, or null when unknown.
  static String? codeFor(String name) {
    final existing = _extractRegional(name);
    if (existing != null) return existing;
    final lower = name.toLowerCase();
    for (final entry in _names.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    for (final token in lower.split(RegExp(r'[^a-z]+'))) {
      final code = _codes[token];
      if (code != null) return code;
    }
    return null;
  }

  /// The flag emoji (regional indicators) for a name, or null.
  static String? flagEmoji(String name) {
    final code = codeFor(name);
    if (code == null) return null;
    return code
        .toUpperCase()
        .split('')
        .map((c) => String.fromCharCode(0x1F1E6 + c.codeUnitAt(0) - 65))
        .join();
  }

  /// The name with any leading/embedded flag emoji removed (so it doesn't show
  /// as raw "DE" letters next to the rendered flag on Windows).
  static String cleanName(String name) {
    final buffer = StringBuffer();
    for (final rune in name.runes) {
      if (rune >= 0x1F1E6 && rune <= 0x1F1FF) continue; // regional indicators
      if (rune == 0x200D || rune == 0xFE0F) continue; // ZWJ / variation selector
      buffer.writeCharCode(rune);
    }
    return buffer.toString().trim();
  }

  static String? _extractRegional(String s) {
    final runes = s.runes.toList();
    for (var i = 0; i < runes.length - 1; i++) {
      final a = runes[i];
      final b = runes[i + 1];
      if (a >= 0x1F1E6 && a <= 0x1F1FF && b >= 0x1F1E6 && b <= 0x1F1FF) {
        return '${String.fromCharCode(65 + a - 0x1F1E6)}'
            '${String.fromCharCode(65 + b - 0x1F1E6)}';
      }
    }
    return null;
  }
}
