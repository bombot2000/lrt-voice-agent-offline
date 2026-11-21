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

/// Satu pilihan tujuan yang bisa diketuk saat hasil pencarian ambigu.
class Choice {
  final String label;
  final Map<String, Object?> row;
  const Choice(this.label, this.row);
}

/// Jawaban mesin: teks (untuk ditampilkan dan dibacakan) dan pilihan tujuan.
class Reply {
  final String text;
  final List<Choice> choices;
  const Reply(this.text, [this.choices = const []]);
}

/// Menentukan jawaban untuk satu pertanyaan ongkir, dengan ingatan dialog:
/// bila tujuan ambigu, jawaban berikutnya (ucapan, ketikan, atau ketukan
/// pilihan) mempersempit kandidat tanpa perlu mengulang seluruh kalimat.
class AnswerEngine {
  final TariffLookup tariffs;
  String _pendingQuery = '';
  List<Map<String, Object?>> _pending = const [];

  AnswerEngine(this.tariffs);

  bool get hasPendingChoice => _pending.isNotEmpty;

  void reset() {
    _pendingQuery = '';
    _pending = const [];
  }

  /// Versi sederhana yang hanya mengembalikan teks.
  Future<String> answer(String query) async => (await ask(query)).text;

  /// Jawaban setelah pengguna mengetuk salah satu pilihan.
  Reply select(Choice choice) {
    final query = _pendingQuery;
    reset();
    return Reply(buildFareAnswer(query, choice.row));
  }

  Future<Reply> ask(String query) async {
    if (_pending.isNotEmpty) {
      final followUp = _narrow(query);
      if (followUp != null) return followUp;
      reset(); // Bukan jawaban atas pertanyaan sebelumnya: mulai baru.
    }

    final normalized = normalizeQuery(query);
    final words = normalized.split(' ').where((w) => w.isNotEmpty).toSet();
    final cargo = words.any(_cargoWords.contains) ||
        RegExp(r'\d\s*(kg|kilo|kilogram)\b').hasMatch(normalized);
    final greeting =
        words.any(_greetingWords.contains) || normalized.contains('bisa apa');
    if (greeting && !cargo) return const Reply(_helpAnswer);

    List<Map<String, Object?>> matches;
    try {
      matches = await tariffs.find(query);
    } catch (_) {
      return const Reply(
          'Data tarif tidak dapat dibaca. Coba lagi, atau impor ulang lewat menu Kelola Data Ongkir.');
    }

    if (matches.isEmpty) {
      final total = await tariffs.count();
      if (total == 0) {
        return const Reply(
            'Data tarif kargo belum diimpor. Buka menu Kelola Data Ongkir untuk memasukkan file tarif terbaru.');
      }
      return Reply(
          'Tarif NEXT Cargo dari MALANG KOTA tersedia untuk $total tujuan. Sebutkan kota serta kecamatan atau kelurahan tujuan.');
    }
    if (matches.length > 1) return _ambiguous(matches, query);
    return Reply(buildFareAnswer(query, matches.first));
  }

  /// Mempersempit kandidat dengan kata baru. Null bila kata baru tidak cocok
  /// dengan satu pun kandidat (berarti ini pertanyaan baru).
  Reply? _narrow(String query) {
    final tokens = destinationTokens(query);
    if (tokens.isEmpty) return null;
    final narrowed = _pending.where((r) {
      final text = _destinationOf(r).toUpperCase();
      return tokens.every(text.contains);
    }).toList();
    if (narrowed.isEmpty) return null;

    final combined = '$_pendingQuery $query';
    if (narrowed.length == 1) {
      reset();
      return Reply(buildFareAnswer(combined, narrowed.first));
    }
    return _ambiguous(narrowed, combined);
  }

  Reply _ambiguous(List<Map<String, Object?>> rows, String query) {
    _pendingQuery = query;
    _pending = rows;
    final count = rows.length >= kMaxTariffMatches
        ? 'Ada banyak tujuan'
        : 'Ada ${rows.length} tujuan';
    return Reply(
      '$count yang cocok. Pilih salah satu di layar, atau sebutkan kecamatan atau kelurahan lebih lengkap.',
      [for (final r in rows.take(6)) Choice(_destinationOf(r), r)],
    );
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

  // Tarif bertingkat dipilih berdasarkan batas minimum yang benar-benar
  // terpenuhi. Berat 30 kg memakai Reguler min. 20 kg; SP1 min. 200 kg
  // belum berlaku dan tidak boleh ikut dihitung.
  String? selectedService;
  String? minimumNotice;
  if (weight != null) {
    final eligible = services
        .map((service) => (
              label: service.$1,
              minimum: parseTariffNumber(r[service.$2]),
              rate: parseTariffNumber(r[service.$3]),
            ))
        .where((service) => service.minimum != null && service.rate != null &&
            service.minimum! > 0 && service.rate! > 0 && weight >= service.minimum!)
        .toList()
      ..sort((a, b) => b.minimum!.compareTo(a.minimum!));

    final requestedMinimum = requested == null
        ? null
        : services
            .where((service) => service.$1 == requested)
            .map((service) => parseTariffNumber(r[service.$2]))
            .firstOrNull;

    if (requested != null && requestedMinimum != null && requestedMinimum > weight) {
      minimumNotice =
          '$requested belum berlaku karena minimum ${formatPlainNumber(requestedMinimum)} kg; digunakan layanan dengan minimum yang sudah terpenuhi.';
    }

    if (requested != null && requestedMinimum != null && requestedMinimum <= weight) {
      selectedService = requested;
    } else if (eligible.isNotEmpty) {
      selectedService = eligible.first.label;
    } else if (requested != null) {
      selectedService = requested;
    }
  } else {
    selectedService = requested;
  }
  final lines = <String>[];
  for (final (label, minKey, rateKey) in services) {
    final minimum = parseTariffNumber(r[minKey]);
    final rate = parseTariffNumber(r[rateKey]);
    if (minimum == null || rate == null || minimum <= 0 || rate <= 0) continue;
    if (selectedService != null && selectedService != label) continue;
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

  // Untuk permintaan dengan berat, tampilkan hasil ongkir yang diminta saja.
  // Tarif khusus, tarif 10 kg, handler, dan lead time bukan komponen perkalian
  // tarif/kg sehingga tidak dicampurkan ke total.
  if (weight != null) return [prefix, if (minimumNotice != null) minimumNotice, ...lines].join(' ');

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
