// Utilitas murni (tanpa dependensi Flutter/plugin) untuk angka tarif.

/// Mengurai angka tarif dari CSV, Excel, atau JSON.
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
        (last.length == 3 && first.isNotEmpty && first != '0' && first.length <= 3);
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

String formatPlainNumber(num value) =>
    value == value.roundToDouble() ? value.round().toString() : value.toString();

String formatRupiah(num value) {
  final n = value.round();
  final digits = n.abs().toString();
  final grouped = digits.replaceAllMapped(
    RegExp(r'(?<=\d)(?=(\d{3})+$)'),
    (_) => '.',
  );
  return '${n < 0 ? '-' : ''}Rp $grouped';
}

num billableWeight(num actualWeight, num serviceMinimum) =>
    actualWeight > serviceMinimum ? actualWeight : serviceMinimum;

const int kMaxTariffMatches = 8;

/// Mengubah bilangan bulat ke ucapan bahasa Indonesia untuk TTS.
String _indonesianIntegerWords(int value) {
  const units = ['nol', 'satu', 'dua', 'tiga', 'empat', 'lima', 'enam',
    'tujuh', 'delapan', 'sembilan', 'sepuluh', 'sebelas'];
  if (value < 0) return 'minus ${_indonesianIntegerWords(-value)}';
  if (value < 12) return units[value];
  if (value < 20) return '${_indonesianIntegerWords(value - 10)} belas';
  if (value < 100) {
    final rest = value % 10;
    return '${_indonesianIntegerWords(value ~/ 10)} puluh${rest == 0 ? '' : ' ${_indonesianIntegerWords(rest)}'}';
  }
  if (value < 200) {
    return 'seratus${value == 100 ? '' : ' ${_indonesianIntegerWords(value - 100)}'}';
  }
  if (value < 1000) {
    final rest = value % 100;
    return '${_indonesianIntegerWords(value ~/ 100)} ratus${rest == 0 ? '' : ' ${_indonesianIntegerWords(rest)}'}';
  }
  for (final scale in [1000000000, 1000000, 1000]) {
    if (value >= scale) {
      final count = value ~/ scale;
      final rest = value % scale;
      final label = scale == 1000000000 ? 'miliar' : scale == 1000000 ? 'juta' : 'ribu';
      final prefix = scale == 1000 && count == 1
          ? 'seribu'
          : '${_indonesianIntegerWords(count)} $label';
      return '$prefix${rest == 0 ? '' : ' ${_indonesianIntegerWords(rest)}'}';
    }
  }
  return value.toString();
}

/// Format nama wilayah dan susunan alamat tujuan.
String formatRegionName(Object? value) {
  final raw = (value ?? '').toString().trim().replaceAll(RegExp(r'\s+'), ' ');
  if (raw.isEmpty || raw == '-') return '';
  return raw.toLowerCase().split(' ').map((word) {
    if (word.isEmpty) return word;
    return word[0].toUpperCase() + word.substring(1);
  }).join(' ');
}

String formatDestination({
  Object? village,
  Object? district,
  Object? city,
  Object? province,
}) => [village, district, city, province]
    .map(formatRegionName)
    .where((part) => part.isNotEmpty)
    .toList()
    .join(', ');

/// Teks TTS dipisahkan dari teks yang ditampilkan pada chat.
String spokenVersion(String text) {
  final result = text.replaceAllMapped(
    RegExp(r'\bRp\s*(\d{1,3}(?:\.\d{3})*|\d+)(?![\d.]\d)'),
    (match) {
      final amount = int.tryParse(match.group(1)!.replaceAll('.', ''));
      return amount == null
          ? match.group(0)!
          : '${_indonesianIntegerWords(amount)} rupiah';
    },
  );
  const tierWords = {'1': 'satu', '2': 'dua', '3': 'tiga'};
  return result
      .replaceAllMapped(
        RegExp(r'\bKab\.\s*', caseSensitive: false),
        (_) => 'Kabupaten ',
      )
      .replaceAllMapped(
        RegExp(r'\bSP([123])\b', caseSensitive: false),
        (match) => 'S P ${tierWords[match.group(1)]}',
      )
      .replaceAll('=', ' sama dengan ')
      .replaceAll('×', ' kali ')
      .replaceAll('/kg', ' per kilogram')
      .replaceAll(RegExp(r'\bkg\b', caseSensitive: false), 'kilogram')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

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
      final unit = current % 100;
      current = current - unit + (unit == 0 ? 1 : unit) * 10;
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


num? parseWeight(String query) {
  final numeric = RegExp(
    r'(\d+(?:[.,]\d+)?)\s*(?:kg|kilo(?:gram)?)\b',
    caseSensitive: false,
  ).firstMatch(query);
  if (numeric != null) {
    final raw = numeric.group(1)!;
    // Notasi Indonesia: titik dengan tiga digit di belakang adalah ribuan;
    // koma menjadi tanda desimal.
    if (raw.contains(',')) {
      return double.tryParse(raw.replaceAll('.', '').replaceAll(',', '.'));
    }
    if (RegExp(r'^\d{1,3}\.\d{3}$').hasMatch(raw)) {
      return int.tryParse(raw.replaceAll('.', ''));
    }
    return num.tryParse(raw);
  }

  final normalized = query.toLowerCase()
      .replaceAll(RegExp(r'\bseratus\b'), 'se ratus')
      .replaceAll(RegExp(r'\bseribu\b'), 'se ribu');
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
  'tarif', 'khusus', 'ongkir', 'ongkos', 'harga', 'biaya', 'ke', 'dari', 'motor', 'sepeda', 'cc',
  'tujuan', 'menuju', 'pengiriman', 'kirim', 'paket', 'barang', 'malang',
  'provinsi', 'propinsi', 'kota', 'kabupaten', 'kab', 'kecamatan', 'kec', 'kelurahan', 'desa', 'reg', 'reguler',
  'sp1', 'sp2', 'sp3', 'next', 'cargo', 'tolong', 'mohon', 'coba', 'cek',
  'carikan', 'cari', 'info', 'informasi', 'hitung', 'hitungkan', 'kalkulasi',
  'estimasi', 'berapa', 'untuk', 'dengan', 'berat', 'kg', 'kilo', 'kilogram',
  'saya', 'minta', 'dong', 'halo', 'hai', 'selamat', 'pagi', 'siang', 'sore',
  'malam', 'nya', 'kah', 'lah', 'kan',
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

List<String> destinationTokens(String query) {
  final withoutWeight = query.toLowerCase()
      .replaceAll(RegExp(r'\bseratus\b'), 'se ratus')
      .replaceAll(RegExp(r'\bseribu\b'), 'se ribu')
      .replaceAll(
    RegExp(r'(?:\d+(?:[.,]\d+)?|(?:nol|kosong|se|satu|dua|tiga|empat|lima|enam|tujuh|delapan|sembilan|sepuluh|sebelas|belas|puluh|ratus|ribu|koma)(?:[\s-]+(?:nol|kosong|se|satu|dua|tiga|empat|lima|enam|tujuh|delapan|sembilan|sepuluh|sebelas|belas|puluh|ratus|ribu|koma))*)\s*(?:kg|kilo(?:gram)?)\b',
    caseSensitive: false,
  ), ' ');
  final tokens = withoutWeight.toUpperCase()
      .replaceAll(RegExp(r'\bJATI\s+ASIH\b'), 'JATIASIH')
      .replaceAll(RegExp(r'[^A-Z0-9 ]'), ' ')
      .split(RegExp(r'\s+'))
      .map((t) => _commandStem(t.toLowerCase()).toUpperCase())
      .where((t) => t.length >= 3 && !t.endsWith('CC') &&
          !RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(t) &&
          !_ignoredWords.contains(t.toLowerCase()))
      .toSet()
      .toList();
  return tokens;
}

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
        best = null;
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


/// Merapikan jawaban tarif untuk tampilan chat versi ketik.
/// Jawaban suara tetap memakai teks asli agar nyaman dibacakan.
String formatTypedReply(String text) {
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) return normalized;
  final sentences = normalized
      .split(RegExp(r'(?<=[.!?])\s+(?=[A-Z0-9])'))
      .where((part) => part.trim().isNotEmpty)
      .map((part) => part.trim())
      .toList();
  if (sentences.isEmpty) return normalized;
  final first = sentences.first;
  final routePattern = RegExp(
    r'^(?:Perkiraan ongkir(?: NEXT Cargo)?|Tarif NEXT Cargo) dari (.+?) ke (.+?)(?: untuk berat (.+?) kg)?(?: \([^)]*\))?\.$',
  );
  final route = routePattern.firstMatch(first);
  if (route == null) {
    if (sentences.length < 2) return normalized;
    return [
      sentences.first,
      '',
      for (final detail in sentences.skip(1))
        '• ${detail.replaceFirst(RegExp(r'[.!?]+$'), '')}',
    ].join('\n');
  }
  final hasWeight = route.group(3) != null;
  final output = <String>[
    hasWeight ? 'PERKIRAAN ONGKIR NEXT CARGO' : 'INFORMASI TARIF NEXT CARGO',
    'Tujuan: ${route.group(2)}',
    if (hasWeight) 'Berat: ${route.group(3)} kg',
  ];
  final serviceLines = <String>[];
  final notes = <String>[];
  for (final rawDetail in sentences.skip(1)) {
    final originalDetail = rawDetail.trim();
    final detail = originalDetail.replaceFirst(RegExp(r'[.!?]+$'), '').trim();
    final service = RegExp(r'^(Reguler|SP1|SP2|SP3):\s*(.+)').firstMatch(detail);
    if (service != null) {
      serviceLines.add('${service.group(1)}: ${service.group(2)}');
    } else if (detail.startsWith('Tarif khusus ')) {
      serviceLines.add(detail);
    } else {
      notes.add(originalDetail);
    }
  }
  if (notes.isNotEmpty) {
    output.add('');
    output.add('Catatan:');
    output.addAll(notes.map((note) => '• $note'));
  }
  if (serviceLines.isNotEmpty) {
    output.add('');
    output.add('Rincian tarif:');
    output.addAll(serviceLines.map((line) => '• $line'));
  }
  return output.join('\n');
}
