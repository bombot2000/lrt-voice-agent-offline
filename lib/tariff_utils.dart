// Utilitas murni (tanpa dependensi Flutter/plugin) untuk angka tarif.

/// Mengurai angka tarif/berat dari teks CSV, Excel, atau JSON.
///
/// Mendukung "4700", "4700.0", "4.700", "4,700", "Rp 4.700", "4.700,50",
/// "4,700.50", dan "12,5". Pemisah tunggal dengan tepat 3 digit di belakang
/// (dan bagian depan bukan "0") dianggap pemisah ribuan; selain itu desimal.
/// Mengembalikan null jika kosong atau tidak berisi angka.
num? parseTariffNumber(Object? value) {
  var raw = (value ?? '').toString().trim();
  if (raw.isEmpty) return null;
  raw = raw.replaceAll(RegExp(r'[^0-9.,]'), '');
  if (!RegExp(r'\d').hasMatch(raw)) return null;

  final lastDot = raw.lastIndexOf('.');
  final lastComma = raw.lastIndexOf(',');
  var intPart = raw;
  var frac = '';

  if (lastDot >= 0 && lastComma >= 0) {
    final decimalAt = lastDot > lastComma ? lastDot : lastComma;
    intPart = raw.substring(0, decimalAt).replaceAll(RegExp(r'[.,]'), '');
    frac = raw.substring(decimalAt + 1);
  } else if (lastDot >= 0 || lastComma >= 0) {
    final sep = lastDot >= 0 ? '.' : ',';
    final parts = raw.split(sep);
    final last = parts.last;
    final first = parts.first;
    final thousands = parts.length > 2 ||
        (last.length == 3 &&
            first.isNotEmpty &&
            first != '0' &&
            first.length <= 3);
    if (thousands) {
      intPart = parts.join();
    } else {
      intPart = parts.sublist(0, parts.length - 1).join();
      frac = last;
    }
  }

  if (intPart.isEmpty) intPart = '0';
  return num.tryParse(frac.isEmpty ? intPart : '$intPart.$frac');
}

/// Angka tanpa ".0" di belakang: 25.0 -> "25", 12.5 -> "12.5".
String formatPlainNumber(num value) =>
    value == value.roundToDouble() ? value.round().toString() : value.toString();

/// 117500 -> "Rp 117.500".
String formatRupiah(num value) {
  final n = value.round();
  final digits = n.abs().toString();
  final grouped = digits.replaceAllMapped(
    RegExp(r'(?<=\d)(?=(\d{3})+$)'),
    (_) => '.',
  );
  return '${n < 0 ? '-' : ''}Rp $grouped';
}

/// Berat yang ditagihkan mengikuti minimum layanan pada baris tujuan.
num billableWeight(num actualWeight, num serviceMinimum) =>
    actualWeight > serviceMinimum ? actualWeight : serviceMinimum;

/// Jumlah maksimum tujuan yang dikembalikan pencarian.
const int kMaxTariffMatches = 8;

const Set<String> _ignoredWords = {
  'tarif', 'khusus', 'ongkir', 'ongkos', 'harga', 'biaya', 'ke', 'dari', 'tujuan',
  'menuju', 'pengiriman', 'kirim', 'paket', 'barang', 'malang', 'kota',
  'kabupaten', 'provinsi', 'propinsi', 'kecamatan', 'kelurahan', 'desa',
  'reg', 'reguler', 'sp1', 'sp2', 'sp3', 'next', 'cargo', 'tolong', 'mohon',
  'coba', 'cek', 'carikan', 'cari', 'info', 'informasi', 'hitung', 'hitungkan',
  'kalkulasi', 'estimasi', 'berapa', 'untuk', 'dengan', 'berat', 'kg', 'kilo',
  'kilogram', 'saya', 'minta', 'dong', 'halo', 'hai', 'selamat', 'pagi',
  'siang', 'sore', 'malam',
};

/// Bilangan Indonesia yang umum dipakai saat menyebut berat.
const Map<String, int> _smallNumbers = {
  'nol': 0, 'kosong': 0, 'satu': 1, 'se': 1, 'dua': 2, 'tiga': 3,
  'empat': 4, 'lima': 5, 'enam': 6, 'tujuh': 7, 'delapan': 8,
  'sembilan': 9, 'sepuluh': 10, 'sebelas': 11, 'dua belas': 12,
  'tiga belas': 13, 'empat belas': 14, 'lima belas': 15,
  'enam belas': 16, 'tujuh belas': 17, 'delapan belas': 18,
  'sembilan belas': 19,
};

num? _parseIndonesianInteger(List<String> words) {
  var total = 0, current = 0;
  for (final word in words) {
    if (_smallNumbers.containsKey(word)) {
      current += _smallNumbers[word]!;
    } else if (word == 'puluh') {
      current = (current == 0 ? 1 : current) * 10;
    } else if (word == 'ratus') {
      current = (current == 0 ? 1 : current) * 100;
    } else if (word == 'belas') {
      current += 10;
    } else if (word == 'ribu') {
      total += (current == 0 ? 1 : current) * 1000;
      current = 0;
    } else {
      return null;
    }
  }
  return total + current;
}

/// Mengambil berat angka atau terbilang sebelum kg/kilo/kilogram.
num? parseWeight(String query) {
  final numeric = RegExp(
    r'(\d+(?:[.,]\d+)?)\s*(?:kg|kilo(?:gram)?)\b',
    caseSensitive: false,
  ).firstMatch(query);
  if (numeric != null) return parseTariffNumber(numeric.group(1));

  final normalized = query.toLowerCase()
      .replaceAll(RegExp(r'\\bseratus\\b'), 'se ratus')
      .replaceAll(RegExp(r'\\bseribu\\b'), 'se ribu');
  final words = RegExp(
    r'((?:nol|kosong|se|satu|dua|tiga|empat|lima|enam|tujuh|delapan|sembilan|sepuluh|sebelas|belas|puluh|ratus|ribu|koma)(?:[\s-]+(?:nol|kosong|se|satu|dua|tiga|empat|lima|enam|tujuh|delapan|sembilan|sepuluh|sebelas|belas|puluh|ratus|ribu|koma))*)\s*(?:kg|kilo(?:gram)?)\b',
    caseSensitive: false,
  ).firstMatch(normalized);
  if (words == null) return null;
  final parts = words.group(1)!.replaceAll('-', ' ').split(RegExp(r'\s+'));
  final comma = parts.indexOf('koma');
  if (comma < 0) return _parseIndonesianInteger(parts);
  final whole = _parseIndonesianInteger(parts.sublist(0, comma));
  if (whole == null || comma + 1 >= parts.length) return null;
  final decimalWords = parts.sublist(comma + 1);
  final digits = decimalWords.map((w) {
    final value = _smallNumbers[w];
    return value != null && value < 10 ? value.toString() : '';
  }).join();
  if (digits.isEmpty || digits.length != decimalWords.length) return null;
  return num.tryParse('$whole.$digits');
}

const Set<String> _ignoredWords = {
  'tarif', 'khusus', 'ongkir', 'ongkos', 'harga', 'biaya', 'ke', 'dari',
  'tujuan', 'menuju', 'pengiriman', 'kirim', 'paket', 'barang', 'malang',
  'kota', 'kabupaten', 'provinsi', 'propinsi', 'kecamatan', 'kelurahan',
  'desa', 'reg', 'reguler', 'sp1', 'sp2', 'sp3', 'next', 'cargo', 'tolong',
  'mohon', 'coba', 'cek', 'carikan', 'cari', 'info', 'informasi', 'hitung',
  'hitungkan', 'kalkulasi', 'estimasi', 'berapa', 'untuk', 'dengan', 'berat',
  'kg', 'kilo', 'kilogram', 'saya', 'minta', 'dong', 'halo', 'hai', 'selamat',
  'pagi', 'siang', 'sore', 'malam', 'nya', 'kah', 'lah', 'kan',
};

String _commandStem(String word) {
  for (final suffix in const ['nya', 'kah', 'lah', 'kan']) {
    if (word.length > suffix.length + 2 && word.endsWith(suffix)) {
      final stem = word.substring(0, word.length - suffix.length);
      if (_ignoredWords.contains(stem)) return stem;
    }
  }
  return word;
}

/// Token nama tujuan. Penghapusan imbuhan hanya untuk kata perintah yang
/// dikenal; nama wilayah tidak pernah di-stem.
List<String> destinationTokens(String query) {
  final withoutWeight = query.toLowerCase()\n      .replaceAll(RegExp(r'\\bseratus\\b'), 'se ratus')\n      .replaceAll(RegExp(r'\\bseribu\\b'), 'se ribu')\n      .replaceAll(
    RegExp(r'\b(?:nol|kosong|se|satu|dua|tiga|empat|lima|enam|tujuh|delapan|sembilan|sepuluh|sebelas|belas|puluh|ratus|ribu|koma)(?:[\s-]+(?:nol|kosong|se|satu|dua|tiga|empat|lima|enam|tujuh|delapan|sembilan|sepuluh|sebelas|belas|puluh|ratus|ribu|koma))*\s*(?:kg|kilo(?:gram)?)\b',
    caseSensitive: false,
  ), ' ');
  final tokens = withoutWeight
      .toUpperCase()
      .replaceAll(RegExp(r'\bJATI\s+ASIH\b'), 'JATIASIH')
      .replaceAll(RegExp(r'[^A-Z0-9 ]'), ' ')
      .split(RegExp(r'\s+'))
      .map((t) => _commandStem(t.toLowerCase()).toUpperCase())
      .where((t) => t.length >= 3 &&
          !RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(t) &&
          !_ignoredWords.contains(t.toLowerCase()))
      .toSet()
      .toList();
  return tokens;
}

/// Koreksi token ke kosakata wilayah hanya bila jaraknya cukup dekat.
/// Kata tiga huruf atau lebih pendek sengaja tidak dikoreksi.
List<String> resolveTokens(List<String> tokens, Iterable<String> vocabulary) {
  final words = vocabulary.map((e) => e.toUpperCase()).toSet();
  return tokens.map((token) {
    if (token.length <= 3 || words.contains(token)) return token;
    String? best;
    var bestDistance = 99;
    for (final candidate in words) {
      if ((candidate.length - token.length).abs() > 2) continue;
      final distance = _editDistance(token, candidate);
      final limit = token.length >= 8 ? 2 : 1;
      if (distance < bestDistance && distance <= limit) {
        best = candidate;
        bestDistance = distance;
      } else if (distance == bestDistance) {
        best = null; // hasil seri: jangan menebak.
      }
    }
    return best ?? token;
  }).toList();
}

int _editDistance(String a, String b) {
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 0; i < a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0);
    current[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      current[j + 1] = [
        current[j] + 1,
        previous[j + 1] + 1,
        previous[j] + (a[i] == b[j] ? 0 : 1),
      ].reduce((x, y) => x < y ? x : y);
    }
    previous = current;
  }
  return previous[b.length];
}
