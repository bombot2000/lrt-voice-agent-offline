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
          'Data tarif tidak dapat dibaca. Coba lagi, atau impor ulang lewat menu Kelola data tarif.');
    }

    if (matches.isEmpty) {
      final total = await tariffs.count();
      if (total == 0) {
        return const Reply(
            'Data tarif kargo belum diimpor. Buka menu Kelola data tarif untuk memasukkan file tarif terbaru.');
      }
      final destinationTokensForMessage = destinationTokens(query);
      final destination = destinationTokensForMessage
          .map(formatRegionName)
          .where((part) => part.isNotEmpty)
          .join(' ');
      final searched = destination.isEmpty ? 'yang disebutkan' : destination;
      return Reply(
          "Tujuan '$searched' tidak ditemukan. Tarif NEXT Cargo dari MALANG KOTA tersedia untuk $total tujuan. Coba sebut kecamatan atau kota.");
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
                ? [r['district'], r['city'], r['province']]
                    .map(formatRegionName)
                    .where((value) => value.isNotEmpty)
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

String _leadTimeLabel(Map<String, Object?> row) {
  final raw = (row['lead_time'] ?? '').toString().trim();
  if (raw.isEmpty || raw == '-') return '';
  final parsed = parseTariffNumber(raw);
  final days = parsed == null ? raw : parsed.ceil().toString();
  return '$days hari';
}

String _handlerLabel(Map<String, Object?> row) {
  final value = (row['handler'] ?? '').toString().trim();
  return value.isEmpty || value == '-' ? '' : value;
}

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
    final vehicleLabel = wantsBicycle ? 'Sepeda' : 'Motor ${motorMatch!.group(1)}cc';
    return [
      wantsBicycle ? 'ESTIMASI TARIF PENGIRIMAN SEPEDA' : 'ESTIMASI TARIF PENGIRIMAN MOTOR',
      'Tujuan: $destination',
      'Jenis kendaraan: $vehicleLabel',
      '',
      'Tarif: ${formatRupiah(rate)} per unit',
      '',
      'Tarif tetap per unit, tidak dihitung berdasarkan berat barang.',
    ].join('\\n');
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

    // Berat aktual menentukan satu kelompok tertinggi yang sudah memenuhi
    // minimum. Penyebutan layanan di pertanyaan tidak boleh memaksa tarif
    // kelompok yang lebih rendah jika kelompok lebih tinggi juga sudah layak.
    if (eligible.isNotEmpty) {
      selectedService = eligible.first.label;
    } else {
      // Jika berat belum memenuhi minimum layanan mana pun, gunakan Reguler.
      // Jangan menagihkan minimum SP yang diminta jika berat aktual belum layak.
      selectedService = 'Reguler';
    }
  } else {
    // Pertanyaan tarif tujuan tanpa berat/layanan memakai Reguler sebagai default.
    selectedService = requested ?? 'Reguler';
  }
  final requestedServiceEntries = requested == null
      ? <(String, String, String)>[]
      : services.where((service) => service.$1 == requested).toList();
  final requestedMinimum = requestedServiceEntries.isEmpty
      ? null
      : parseTariffNumber(r[requestedServiceEntries.first.$2]);
  final selectedServiceEntries =
      services.where((service) => service.$1 == selectedService).toList();
  final selectedMinimum = selectedServiceEntries.isEmpty
      ? null
      : parseTariffNumber(r[selectedServiceEntries.first.$2]);
  final serviceNotice = weight == null || requested == null ||
          requested == selectedService
      ? ''
      : requestedMinimum != null && requestedMinimum > weight
          ? 'Catatan: $requested minimum ${formatPlainNumber(requestedMinimum)} kg belum terpenuhi; perhitungan menggunakan $selectedService'
              '${selectedMinimum == null ? '' : ' (minimum ${formatPlainNumber(selectedMinimum)} kg)'}.'
          : 'Catatan: berat memenuhi minimum layanan $selectedService; tarif dihitung menggunakan $selectedService.';

  // Tarif khusus memakai kolom tarif_khusus, tetapi batas berat tagihnya
  // tetap mengikuti min_reg. Tarif khusus tidak masuk jenjang SP.
  final specialRate = parseTariffNumber(r['tarif_khusus']);
  final regularMinimum = parseTariffNumber(r['min_reg']);
  if (wantsSpecial && specialRate != null && specialRate > 0 &&
      regularMinimum != null && regularMinimum > 0) {
    final billable = weight == null ? regularMinimum : billableWeight(weight, regularMinimum);
    final line = '- Tarif khusus: minimum Reguler ${formatPlainNumber(regularMinimum)} kg, berat tagihan ${formatPlainNumber(billable)} kg × ${formatRupiah(specialRate)}/kg = ${formatRupiah(billable * specialRate)}.';
    return [
      'ESTIMASI TARIF PENGIRIMAN',
      'Tujuan: $destination',
      '',
      line,
      '',
      if (_leadTimeLabel(r).isNotEmpty) 'Estimasi Pengiriman: ${_leadTimeLabel(r)}',
      if (_handlerLabel(r).isNotEmpty) 'Handler: ${_handlerLabel(r)}',
    ].join('\n');
  }
  if (wantsSpecial && (specialRate == null || specialRate <= 0)) {
    return 'Tarif khusus tidak tersedia untuk tujuan $destination.';
  }

  // Tujuan yang memiliki tarif_10kg: berat di bawah 10 kg tetap ditagih
  // minimum 10 kg. Berat 10-13 kg memakai berat aktual. Jika tarif_10kg
  // kosong/nol, lanjutkan ke aturan minimum Reguler/SP tujuan tersebut.
  final tarif10 = parseTariffNumber(r['tarif_10kg']);
  if (weight != null && weight <= 13 && tarif10 != null && tarif10 > 0) {
    final billable = weight < 10 ? 10 : weight;
    final amount = formatRupiah(billable * tarif10);
    final lead = _leadTimeLabel(r);
    final handler = _handlerLabel(r);
    return [
      '📦 INFORMASI TARIF NEXT CARGO',
      'Tujuan: $destination',
      '',
      '💰 Tarif Pengiriman:',
      'Berat aktual: ${formatPlainNumber(weight)} kg',
      'Berat tagihan: ${formatPlainNumber(billable)} kg',
      'Layanan: Tarif 10 Kg',
      'Tarif 10 kg: ${formatRupiah(tarif10 * 10)}',
      'Estimasi ongkir: $amount',
      if (weight < 10) 'Catatan: minimum tagihan 10 kg',
      if (serviceNotice.isNotEmpty) serviceNotice,
      '',
      if (lead.isNotEmpty) '⏱️ Estimasi Pengiriman: $lead',
      if (handler.isNotEmpty) '📍 Handler: $handler',
    ].join('\n');
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
    return 'Tarif Reguler tidak tersedia untuk tujuan $destination. Data minimum atau tarif belum lengkap.';
  }

  // Format ringkas untuk jawaban yang menyertakan berat.
  // Rumus dan berat tagihan tetap memakai hasil perhitungan di atas.
  if (weight != null) {
    final lead = _leadTimeLabel(r);
    final tariffLines = <String>[];
    for (final (label, minKey, rateKey) in services) {
      if (selectedService != label) continue;
      final minimum = parseTariffNumber(r[minKey]);
      final rate = parseTariffNumber(r[rateKey]);
      if (minimum == null || rate == null || minimum <= 0 || rate <= 0) continue;

      final billable = billableWeight(weight, minimum);
      tariffLines.add('Berat aktual: ${formatPlainNumber(weight)} kg');
      if (weight < minimum) {
        tariffLines.add('Berat tagihan: ${formatPlainNumber(billable)} kg');
      }
      tariffLines.add(
        'Layanan: $label (min. ${formatPlainNumber(minimum)} kg)',
      );
      if (serviceNotice.isNotEmpty) tariffLines.add(serviceNotice);
      tariffLines.add('Tarif per kg selanjutnya: ${formatRupiah(rate)}');
      tariffLines.add('Estimasi ongkir: ${formatRupiah(billable * rate)}');
    }
    return [
      'ESTIMASI TARIF PENGIRIMAN',
      'Tujuan: $destination',
      '',
      if (tariffLines.isNotEmpty) tariffLines.join('\n'),
      '',
      if (lead.isNotEmpty) 'Estimasi Pengiriman: $lead',
    ].join('\n');
  }

  final lead = _leadTimeLabel(r);
  final tariffLines = <String>[];
  for (final (label, minKey, rateKey) in services) {
    if (selectedService != label) continue;
    final minimum = parseTariffNumber(r[minKey]);
    final rate = parseTariffNumber(r[rateKey]);
    if (minimum == null || rate == null || minimum <= 0 || rate <= 0) continue;
    tariffLines.add(
      '- $label (min. ${formatPlainNumber(minimum)} kg) : ${formatRupiah(minimum * rate)},\n'
      '  per kg selanjutnya ${formatRupiah(rate)}',
    );
  }
  if (tarif10 != null && tarif10 > 0) {
    tariffLines.add('- Tarif 10 kg (max.10 kg) : ${formatRupiah(tarif10 * 10)}');
  }
  return [
    'TARIF PENGIRIMAN',
    'Tujuan: $destination',
    '',
    if (tariffLines.isNotEmpty) tariffLines.join('\n\n'),
    '',
    if (lead.isNotEmpty) 'Estimasi Pengiriman: $lead',
  ].join('\n');
}
