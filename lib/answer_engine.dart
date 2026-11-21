import 'tariff_utils.dart';

/// Sumber data tarif kargo. Dipisah sebagai antarmuka agar mesin jawaban
/// bisa diuji tanpa SQLite.
abstract class TariffLookup {
  Future<List<Map<String, Object?>>> find(String query);
  Future<int> count();
}

const String _helpAnswer =
    'Saya bisa menghitung ongkir NEXT Cargo dari MALANG KOTA secara offline. Sebutkan tujuan dan berat, misalnya "ongkir ke Abiansemal Badung 20 kilo reguler".';

const Set<String> _greetingWords = {
  'halo', 'hai', 'selamat', 'pagi', 'siang', 'sore', 'malam', 'bantuan',
};

/// Kata yang menandakan pertanyaan tentang pengiriman kargo.
const Set<String> _cargoWords = {
  'ongkir', 'ongkos', 'cargo', 'kargo', 'paket', 'kirim', 'pengiriman',
  'barang', 'kg', 'kilo', 'kilogram', 'reg', 'reguler', 'sp1', 'sp2', 'sp3',
  'next', 'malang', 'tarif', 'harga', 'biaya',
};

String normalizeQuery(String query) => query
    .toLowerCase()
    .replaceAll(RegExp(r'[^\w\s-]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Menentukan jawaban untuk satu pertanyaan ongkir.
class AnswerEngine {
  final TariffLookup tariffs;

  const AnswerEngine(this.tariffs);

  Future<String> answer(String query) async {
    final normalized = normalizeQuery(query);
    final words = normalized.split(' ').where((w) => w.isNotEmpty).toSet();

    final cargo = words.any(_cargoWords.contains) ||
        RegExp(r'\d\s*(kg|kilo|kilogram)\b').hasMatch(normalized);
    final greeting =
        words.any(_greetingWords.contains) || normalized.contains('bisa apa');
    if (greeting && !cargo) return _helpAnswer;

    List<Map<String, Object?>> matches;
    try {
      matches = await tariffs.find(query);
    } catch (_) {
      return 'Data tarif tidak dapat dibaca. Coba lagi, atau impor ulang lewat menu Kelola Data Ongkir.';
    }

    if (matches.isEmpty) {
      final total = await tariffs.count();
      if (total == 0) {
        return 'Data tarif kargo belum diimpor. Buka menu Kelola Data Ongkir untuk memasukkan file tarif terbaru.';
      }
      return 'Tarif NEXT Cargo dari MALANG KOTA tersedia untuk $total tujuan. Sebutkan kota serta kecamatan atau kelurahan tujuan.';
    }
    if (matches.length > 1) {
      final choices = matches.take(5).map(_destinationOf).join('; ');
      return 'Ada beberapa tujuan yang cocok. Sebutkan kecamatan atau kelurahan lebih lengkap. Contoh: $choices.';
    }
    return buildFareAnswer(query, matches.first);
  }
}

String _destinationOf(Map<String, Object?> r) =>
    [r['village'], r['district'], r['city'], r['province']].join(', ');

/// Menyusun jawaban tarif untuk satu baris tujuan.
String buildFareAnswer(String query, Map<String, Object?> r) {
  final destination = _destinationOf(r);

  final weightMatch = RegExp(
    r'(\d+(?:[.,]\d+)?)\s*(?:kg|kilo|kilogram)\b',
    caseSensitive: false,
  ).firstMatch(query);
  final weight =
      weightMatch == null ? null : parseTariffNumber(weightMatch.group(1));

  final lower = query.toLowerCase();
  final requested = lower.contains('sp3')
      ? 'SP3'
      : lower.contains('sp2')
          ? 'SP2'
          : lower.contains('sp1')
              ? 'SP1'
              : (lower.contains('reguler') || RegExp(r'\breg\b').hasMatch(lower))
                  ? 'Reguler'
                  : null;

  const services = [
    ('Reguler', 'min_reg', 'tarif_reg'),
    ('SP1', 'min_sp1', 'tarif_sp1'),
    ('SP2', 'min_sp2', 'tarif_sp2'),
    ('SP3', 'min_sp3', 'tarif_sp3'),
  ];

  final lines = <String>[];
  for (final (label, minKey, rateKey) in services) {
    final minimum = parseTariffNumber(r[minKey]);
    final rate = parseTariffNumber(r[rateKey]);
    if (minimum == null || rate == null || minimum <= 0 || rate <= 0) continue;
    if (requested != null && requested != label) continue;
    if (weight == null) {
      lines.add(
          '$label: minimum ${formatPlainNumber(minimum)} kg, tarif ${formatRupiah(rate)}/kg.');
    } else {
      final billable = billableWeight(weight, minimum);
      lines.add(
          '$label: berat aktual ${formatPlainNumber(weight)} kg, berat tagihan ${formatPlainNumber(billable)} kg × ${formatRupiah(rate)}/kg = ${formatRupiah(billable * rate)}.');
    }
  }

  if (lines.isEmpty && requested != null) {
    return 'Tarif $requested tidak tersedia untuk tujuan $destination.';
  }

  final prefix = weight == null
      ? 'Tarif NEXT Cargo dari MALANG KOTA ke $destination.'
      : 'Perkiraan ongkir NEXT Cargo dari MALANG KOTA ke $destination untuk berat ${formatPlainNumber(weight)} kg (minimum layanan berlaku).';

  final extras = <String>[];
  final tarif10 = parseTariffNumber(r['tarif_10kg']);
  if (tarif10 != null && tarif10 > 0) {
    extras.add('Tarif 10 kg ${formatRupiah(tarif10)}.');
  }
  final khusus = parseTariffNumber(r['tarif_khusus']);
  if (khusus != null && khusus > 0) {
    extras.add('Tarif khusus ${formatRupiah(khusus)}.');
  }
  final lead = (r['lead_time'] ?? '').toString().trim();
  if (lead.isNotEmpty && lead != '-') extras.add('Lead time $lead hari.');
  final handler = (r['handler'] ?? '').toString().trim();
  if (handler.isNotEmpty && handler != '-') extras.add('Handler $handler.');

  return [prefix, ...lines, ...extras].join(' ');
}
