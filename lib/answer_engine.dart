import 'tariff_utils.dart';
import 'command_parser_service.dart';

/// Sumber data tarif kargo. Dipisah sebagai antarmuka agar mesin jawaban
/// bisa diuji tanpa SQLite.
abstract class TariffLookup {
  Future<List<Map<String, Object?>>> find(String query);
  Future<int> count();
}

const String _helpAnswer =
    'Saya bisa menghitung ongkir NEXT Cargo secara offline. Sebutkan tujuan dan berat, misalnya "ongkir ke Abiansemal Badung 20 kilo reguler".';

String normalizeQuery(String query) => CommandParserService.normalize(query);

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
  String _pendingRootQuery = '';
  final Set<String> _pendingBaseTokens = <String>{};
  final Set<String> _pendingRefinementTokens = <String>{};
  final Set<String> _pendingRefinementDetails = <String>{};
  List<Map<String, Object?>> _pending = const [];

  AnswerEngine(this.tariffs);

  bool get hasPendingChoice => _pending.isNotEmpty;

  void reset() {
    _pendingQuery = '';
    _pendingRootQuery = '';
    _pendingBaseTokens.clear();
    _pendingRefinementTokens.clear();
    _pendingRefinementDetails.clear();
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
      final followUp = await _narrow(query);
      if (followUp != null) return followUp;
      reset(); // Bukan jawaban atas pertanyaan sebelumnya: mulai baru.
    }

    final command = CommandParserService.parse(query);
    if (command.intent == CommandIntent.arithmetic) {
      final expression = command.arithmetic!;
      final result = expression.calculate();
      if (result == null) {
        return const Reply('Perhitungan tidak dapat dilakukan karena pembaginya nol.');
      }
      return Reply(
        'Hasil perhitungan: ${formatPlainNumber(expression.left)} '
        '${expression.operatorLabel} ${formatPlainNumber(expression.right)} '
        '= ${formatPlainNumber(result)}.',
      );
    }
    if (command.intent == CommandIntent.greeting) {
      return const Reply(_helpAnswer);
    }

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
  Future<Reply?> _narrow(String query) async {
    final tokens = destinationTokens(query);
    // Berat atau spesifikasi kendaraan boleh diberikan setelah tujuan ambigu,
    // misalnya "20 kg" atau "125cc", tanpa mengulang nama tujuan.
    final hasWeightDetail = parseWeight(query) != null;
    final hasVehicleDetail = RegExp(
      r'\b(?:motor\s*)?(?:100|125|150|250|500|750)\s*cc\b|\bsepeda\b',
      caseSensitive: false,
    ).hasMatch(query);
    if (tokens.isEmpty && !hasWeightDetail && !hasVehicleDetail) return null;

    // Simpan pertanyaan awal sekali saja; detail dan token follow-up unik
    // agar konteks tidak terus bertambah pada ucapan yang diulang.
    _pendingRefinementTokens.addAll(
      tokens.where((token) => !_pendingBaseTokens.contains(token)),
    );
    if (hasWeightDetail || hasVehicleDetail) {
      _pendingRefinementDetails.add(query.trim());
    }
    final combined = [
      _pendingRootQuery,
      ..._pendingRefinementTokens,
      ..._pendingRefinementDetails,
    ].where((part) => part.isNotEmpty).join(' ').trim();
    // Cari ulang seluruh database: _pending hanya memuat maksimal 8 pilihan UI.
    final narrowed = await tariffs.find(combined);
    if (narrowed.isEmpty) return null;

    if (narrowed.length == 1) {
      reset();
      return Reply(buildFareAnswer(combined, narrowed.first));
    }
    return _ambiguous(narrowed, combined);
  }

  Reply _ambiguous(List<Map<String, Object?>> rows, String query) {
    if (_pending.isEmpty) {
      _pendingRootQuery = query;
      _pendingBaseTokens
        ..clear()
        ..addAll(destinationTokens(query));
      _pendingRefinementTokens.clear();
    }
    _pendingQuery = query;
    _pending = rows;
    final count = rows.length >= kMaxTariffMatches
        ? 'Ada banyak tujuan'
        : 'Ada ${rows.length} tujuan';
    // Untuk pencarian nama kota, jangan penuhi enam saran pertama
    // dengan kelurahan dari kecamatan yang sama. Tampilkan kandidat lintas
    // kecamatan lebih dahulu, tetap membawa baris asli untuk tarif terpilih.
    final byDistrict = <String, Map<String, Object?>>{};
    for (final row in rows) {
      final key = [
        row['province'],
        row['city'],
        row['district'],
      ].map((value) => (value ?? '').toString().trim().toUpperCase()).join('|');
      byDistrict.putIfAbsent(key, () => row);
    }
    final suggestionRows = byDistrict.length > 1
        ? byDistrict.values.toList()
        : rows;
    final isDistrictList = suggestionRows.isNotEmpty &&
        suggestionRows.first['_suggestion_level'] == 'district';
    final visibleRows = isDistrictList
        ? suggestionRows
        : suggestionRows.take(6);
    return Reply(
      '$count yang cocok. Pilih salah satu di layar, atau sebutkan kecamatan atau kelurahan lebih lengkap.',
      [
        for (final r in visibleRows)
          Choice(
            r['_suggestion_level'] == 'district'
                ? [r['city'], r['district'], r['province']]
                    .where((value) => value != null && value.toString().trim().isNotEmpty)
                    .join(', ')
                : _destinationOf(r),
            r,
          ),
      ],
    );
  }
}

String _destinationOf(Map<String, Object?> r) =>
    formatDestination(village: r['village'], district: r['district'], city: r['city'], province: r['province']);

/// Menyusun jawaban tarif untuk satu baris tujuan.
String buildFareAnswer(String query, Map<String, Object?> r) {
  final destination = _destinationOf(r);

  // Tarif kendaraan adalah harga tetap per unit dari kolom Excel, bukan tarif/kg.
  final lowerQuery = query.toLowerCase();
  final wantsBicycle = RegExp(r'\bsepeda\b').hasMatch(lowerQuery);
  final motorMatch = RegExp(r'(?:\bmotor\s*)?\b(100|125|150|250|500|750)\s*(?:cc)?\b')
      .firstMatch(lowerQuery);
  final mentionsMotor = RegExp(r'\bmotor\b').hasMatch(lowerQuery);
  if (wantsBicycle || mentionsMotor) {
    if (mentionsMotor && motorMatch == null) {
      return 'Sebutkan kapasitas motor: 100cc, 125cc, 150cc, 250cc, 500cc, atau 750cc.';
    }
    final item = wantsBicycle ? 'sepeda' : 'motor ${motorMatch!.group(1)}cc';
    final key = wantsBicycle ? 'sepeda' : 'motor_${motorMatch!.group(1)}cc';
    final rate = parseTariffNumber(r[key]);
    if (rate == null || rate <= 0) {
      return 'Tarif $item tidak tersedia untuk tujuan $destination.';
    }
    return 'Tarif NEXT Cargo ke $destination untuk $item: ${formatRupiah(rate)} per unit (tarif tetap, tidak dihitung berdasarkan berat barang).';
  }

  final weight = parseWeight(query);

  final lower = query.toLowerCase();
  final wantsSpecial = RegExp(r'\btarif\s+khusus\b|\bkhusus\b').hasMatch(lower);
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

    num? requestedMinimum;
    if (requested != null) {
      for (final service in services) {
        if (service.$1 == requested) {
          requestedMinimum = parseTariffNumber(r[service.$2]);
          break;
        }
      }
    }

    if (requested != null && requestedMinimum != null && requestedMinimum > weight && eligible.isNotEmpty) {
      minimumNotice =
          '$requested belum berlaku karena minimum ${formatPlainNumber(requestedMinimum)} kg; digunakan layanan dengan minimum yang sudah terpenuhi.';
    } else if (requested != null && eligible.isNotEmpty &&
        eligible.first.label != requested) {
      minimumNotice =
          'Berat memenuhi minimum ${eligible.first.label}, memakai tarif ${eligible.first.label}.';
    }

    // Berat aktual menentukan satu kelompok tertinggi yang sudah memenuhi
    // minimum. Penyebutan layanan di pertanyaan tidak boleh memaksa tarif
    // kelompok yang lebih rendah jika kelompok lebih tinggi juga sudah layak.
    if (eligible.isNotEmpty) {
      selectedService = eligible.first.label;
    } else {
      // Jika berat masih di bawah minimum semua layanan, gunakan Reguler
      // dengan berat tagihan minimum Reguler, bukan menampilkan semua tier.
      selectedService = requested ?? 'Reguler';
    }
  } else {
    // Pertanyaan tarif tujuan tanpa berat/layanan memakai Reguler sebagai default.
    selectedService = requested ?? 'Reguler';
  }
  // Tarif khusus memakai kolom tarif_khusus, tetapi batas berat tagihnya
  // tetap mengikuti min_reg. Tarif khusus tidak masuk jenjang SP.
  final specialRate = parseTariffNumber(r['tarif_khusus']);
  final regularMinimum = parseTariffNumber(r['min_reg']);
  if (wantsSpecial && specialRate != null && specialRate > 0 &&
      regularMinimum != null && regularMinimum > 0) {
    final prefix = weight == null
        ? 'Tarif NEXT Cargo ke $destination.'
        : 'Perkiraan ongkir NEXT Cargo ke $destination untuk berat ${formatPlainNumber(weight)} kg.';
    final billable = weight == null ? regularMinimum : billableWeight(weight, regularMinimum);
    final line = 'Tarif khusus: minimum Reguler ${formatPlainNumber(regularMinimum)} kg, berat tagihan ${formatPlainNumber(billable)} kg × ${formatRupiah(specialRate)}/kg = ${formatRupiah(billable * specialRate)}.';
    return '$prefix $line';
  }
  if (wantsSpecial && (specialRate == null || specialRate <= 0)) {
    return 'Tarif khusus tidak tersedia untuk tujuan $destination.';
  }

  final lines = <String>[];
  for (final (label, minKey, rateKey) in services) {
    final minimum = parseTariffNumber(r[minKey]);
    final rate = parseTariffNumber(r[rateKey]);
    if (minimum == null || rate == null || minimum <= 0 || rate <= 0) continue;
    if (selectedService != label) continue;
    if (weight == null) {
      final minimumTotal = minimum * rate;
      lines.add(
          '$label ${formatPlainNumber(minimum)} kg: ${formatPlainNumber(minimum)} kg × ${formatRupiah(rate)}/kg = ${formatRupiah(minimumTotal)}; setiap kg berikutnya ${formatRupiah(rate)}/kg.');
    } else {
      final billable = billableWeight(weight, minimum);
      lines.add(
          '$label: berat aktual ${formatPlainNumber(weight)} kg, berat tagihan ${formatPlainNumber(billable)} kg × ${formatRupiah(rate)}/kg = ${formatRupiah(billable * rate)}.');
    }
  }

  if (lines.isEmpty) {
    final unavailable = requested ?? selectedService;
    return 'Tarif $unavailable tidak tersedia untuk tujuan $destination. Data minimum atau tarif layanan belum lengkap.';
  }

  final prefix = weight == null
      ? 'Tarif NEXT Cargo ke $destination.'
      : 'Perkiraan ongkir NEXT Cargo ke $destination untuk berat ${formatPlainNumber(weight)} kg (minimum layanan berlaku).';

  // Untuk permintaan dengan berat, tampilkan hasil ongkir yang diminta saja.
  // Tarif khusus, tarif 10 kg, handler, dan lead time bukan komponen perkalian
  // tarif/kg sehingga tidak dicampurkan ke total.
  if (weight != null) return [prefix, if (minimumNotice != null) minimumNotice, ...lines].join(' ');

  final extras = <String>[];
  final tarif10 = parseTariffNumber(r['tarif_10kg']);
  if (tarif10 != null && tarif10 > 0) {
    extras.add('Tarif 10 kg ${formatRupiah(tarif10)}.');
  }
  final rawLead = (r['lead_time'] ?? '').toString().trim();
  final parsedLead = parseTariffNumber(rawLead);
  // Lead time selalu ditampilkan dalam hari bulat; pecahan dibulatkan ke atas
  // agar estimasi tidak menjanjikan waktu lebih singkat dari data sumber.
  final lead = parsedLead == null ? rawLead : parsedLead.ceil().toString();
  if (lead.isNotEmpty && lead != '-') extras.add('Lead time $lead hari.');
  final handler = (r['handler'] ?? '').toString().trim();
  if (handler.isNotEmpty && handler != '-') extras.add('Handler $handler.');

  return [prefix, ...lines, ...extras].join(' ');
}
