/// Utilitas murni (tanpa dependensi Flutter/plugin) untuk angka tarif.

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
  'tarif', 'ongkir', 'ongkos', 'harga', 'biaya', 'ke', 'dari', 'tujuan',
  'menuju', 'pengiriman', 'kirim', 'paket', 'barang', 'malang', 'kota',
  'kabupaten', 'provinsi', 'propinsi', 'kecamatan', 'kelurahan', 'desa',
  'reg', 'reguler', 'sp1', 'sp2', 'sp3', 'next', 'cargo', 'tolong', 'mohon',
  'coba', 'cek', 'carikan', 'cari', 'info', 'informasi', 'hitung', 'hitungkan',
  'kalkulasi', 'estimasi', 'berapa', 'untuk', 'dengan', 'berat', 'kg', 'kilo',
  'kilogram', 'saya', 'minta', 'dong', 'halo', 'hai', 'selamat', 'pagi',
  'siang', 'sore', 'malam',
};

/// Kata penting nama tujuan dari kalimat pertanyaan (huruf besar, tanpa
/// kata perintah, angka, dan kata pendek).
List<String> destinationTokens(String query) => query
    .toUpperCase()
    .replaceAll(RegExp(r'[^A-Z0-9 ]'), ' ')
    .split(RegExp(r'\s+'))
    .where((t) =>
        t.length >= 3 &&
        !RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(t) &&
        !_ignoredWords.contains(t.toLowerCase()))
    .toSet()
    .toList();
