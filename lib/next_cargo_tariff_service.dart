import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'answer_engine.dart' show TariffLookup;
import 'tariff_utils.dart' as util;

const headers = [
  'Asal Kota', 'Tj. Propinsi', 'Tj. Kota', 'Tj. Kecamatan', 'Tj. Kelurahan',
  'Handler', 'Stt Dooring', 'Lead Time', 'Tarif 10Kg', 'Min Reg', 'Tarif Reg',
  'Min SP1', 'Tarif SP1', 'Min SP2', 'Tarif SP2', 'Min SP3', 'Tarif SP3',
  'Tarif Khusus', 'Motor 100cc', 'Motor 125cc', 'Motor 150cc', 'Motor 250cc',
  'Motor 500cc', 'Motor 750cc', 'Sepeda',
];
const cols = [
  'origin', 'province', 'city', 'district', 'village', 'handler',
  'stt_dooring', 'lead_time', 'tarif_10kg', 'min_reg', 'tarif_reg', 'min_sp1',
  'tarif_sp1', 'min_sp2', 'tarif_sp2', 'min_sp3', 'tarif_sp3', 'tarif_khusus',
  'motor_100cc', 'motor_125cc', 'motor_150cc', 'motor_250cc', 'motor_500cc',
  'motor_750cc', 'sepeda',
];

/// Kolom yang harus berisi angka. Nilainya dinormalisasi saat impor
/// ("4.700" / "4,700" / "4700.0" -> "4700"), kosong atau "-" berarti tidak ada.
const numericCols = {
  'tarif_10kg', 'min_reg', 'tarif_reg', 'min_sp1', 'tarif_sp1', 'min_sp2',
  'tarif_sp2', 'min_sp3', 'tarif_sp3', 'tarif_khusus', 'motor_100cc',
  'motor_125cc', 'motor_150cc', 'motor_250cc', 'motor_500cc', 'motor_750cc',
  'sepeda',
};

const _addressFields = ['province', 'city', 'district', 'village'];

String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
String sqlCols() => cols.map((c) => '$c TEXT').join(', ');

String excelCellText(CellValue? value) {
  switch (value) {
    case null:
      return '';
    case TextCellValue(:final value):
      return excelTextSpan(value);
    case IntCellValue(:final value):
      return value.toString();
    case DoubleCellValue(:final value):
      return value.toString();
    case BoolCellValue(:final value):
      return value ? 'TRUE' : 'FALSE';
    case FormulaCellValue(:final formula):
      // Nilai hasil rumus tidak tersedia, jadi ditandai dengan "=" agar
      // ditolak saat validasi (bukan diam-diam dijadikan tarif).
      return formula.startsWith('=') ? formula : '=$formula';
    default:
      return value.toString();
  }
}

String excelTextSpan(TextSpan span) {
  final ownText = span.text ?? '';
  final childText =
      (span.children ?? const <TextSpan>[]).map(excelTextSpan).join();
  return '$ownText$childText';
}

class NextCargoImportPreview {
  final int rowCount;
  final List<String> sampleDestinations;
  const NextCargoImportPreview(this.rowCount, this.sampleDestinations);
}

/// Hasil parsing file tarif: baris sudah divalidasi, dinormalisasi, dan
/// didedupe, sehingga impor ke database tidak perlu mengurai file lagi.
class ParsedTariff {
  final List<Map<String, String>> records;
  final NextCargoImportPreview preview;
  const ParsedTariff(this.records, this.preview);
  int get rowCount => records.length;
}

class _ParseOutcome {
  final ParsedTariff? parsed;
  final String? error;
  const _ParseOutcome({this.parsed, this.error});
}

class NextCargoTariffService {
  static Database? _db;
  static Set<String>? _destinationVocabulary;

  /// Mengisolasi database antar pengujian integrasi tanpa memengaruhi aplikasi.
  static Future<void> resetForTesting() async {
    final db = _db;
    _db = null;
    _destinationVocabulary = null;
    if (db != null && db.isOpen) await db.close();
    final root = await getDatabasesPath();
    await deleteDatabase(p.join(root, 'next_cargo_tariffs.db'));
  }

  static Future<Database> open() async {
    if (_db != null) return _db!;
    final root = await getDatabasesPath();
    _db = await openDatabase(
      p.join(root, 'next_cargo_tariffs.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute(
            'CREATE TABLE tariffs (id INTEGER PRIMARY KEY AUTOINCREMENT, ${sqlCols()}, UNIQUE(province,city,district,village))');
        await db.execute(
            'CREATE TABLE tariff_backup (id INTEGER PRIMARY KEY, ${sqlCols()})');
        await db.execute(
            'CREATE TABLE tariff_backup_meta (id INTEGER PRIMARY KEY CHECK(id = 1), available INTEGER NOT NULL)');
        await db.insert('tariff_backup_meta', {'id': 1, 'available': 0});
        for (final f in _addressFields) {
          await db.execute('CREATE INDEX idx_tariff_$f ON tariffs($f)');
        }
      },
    );
    return _db!;
  }

  // ---------------------------------------------------------------- decode

  /// Memilih pemisah kolom CSV (koma, titik koma, atau tab) dari baris header.
  static String detectDelimiter(String text) {
    for (final line in const LineSplitter().convert(text)) {
      if (!norm(line).contains('asalkota')) continue;
      var best = ',';
      var bestCount = 0;
      for (final d in const [',', ';', '\t']) {
        final n = line.split(d).length - 1;
        if (n > bestCount) {
          best = d;
          bestCount = n;
        }
      }
      return best;
    }
    return ',';
  }

  static List<List<dynamic>> decode(String name, Uint8List bytes) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.csv')) {
      final text = utf8
          .decode(bytes, allowMalformed: true)
          .replaceFirst('\uFEFF', '')
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n');
      return CsvToListConverter(
        fieldDelimiter: detectDelimiter(text),
        shouldParseNumbers: false,
        eol: '\n',
      ).convert(text);
    }
    if (lower.endsWith('.xlsx')) {
      final book = Excel.decodeBytes(bytes);
      if (book.tables.isEmpty) {
        throw const FormatException('Sheet Excel tidak ditemukan.');
      }
      // Workbook bisa memiliki sheet cover/keterangan sebelum sheet tarif.
      // Pilih sheet yang benar-benar memiliki header NEXT Cargo.
      for (final sheet in book.tables.values) {
        final candidate = sheet.rows
            .map((row) => row.map((cell) => excelCellText(cell?.value)).toList())
            .toList();
        try {
          headerAt(candidate);
          return candidate;
        } on FormatException {
          // Lanjutkan memeriksa sheet berikutnya.
        }
      }
      throw const FormatException(
        'Header Asal Kota tidak ditemukan pada semua sheet Excel.',
      );
    }
    if (lower.endsWith('.json')) {
      final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      final data = decoded is List
          ? decoded
          : decoded is Map
              ? (decoded['data'] ?? decoded['tarif'] ?? decoded['fares'])
              : null;
      if (data is! List || data.isEmpty || data.first is! Map) {
        throw const FormatException(
            'JSON harus berisi daftar objek tarif NEXT Cargo.');
      }
      final jsonHeaders =
          (data.first as Map).keys.map((k) => k.toString()).toList();
      return [
        jsonHeaders,
        ...data.map((item) =>
            jsonHeaders.map((h) => (item as Map)[h] ?? '').toList()),
      ];
    }
    throw const FormatException('Gunakan file CSV, JSON, atau Excel .xlsx.');
  }

  static int headerAt(List<List<dynamic>> rows) {
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].isNotEmpty &&
          norm(rows[i][0].toString().trim()) == 'asalkota') {
        return i;
      }
    }
    throw const FormatException('Header Asal Kota tidak ditemukan.');
  }

  static Map<String, int> mapHeader(List<dynamic> row) {
    final found = <String, int>{};
    for (var i = 0; i < row.length; i++) {
      found[norm(row[i].toString())] = i;
    }
    final expected = headers.map(norm).toList();
    final missing = expected.where((h) => !found.containsKey(h)).toList();
    if (missing.isNotEmpty) {
      throw FormatException('Kolom hilang: ${missing.join(', ')}');
    }
    return {for (var i = 0; i < cols.length; i++) cols[i]: found[expected[i]]!};
  }

  static String cell(List<dynamic> row, int i) =>
      i < row.length ? row[i].toString().trim() : '';

  // ----------------------------------------------------------------- parse

  static final _numericText =
      RegExp(r'^(rp\.?\s*)?[0-9][0-9.,\s]*$', caseSensitive: false);

  /// Membangun satu record tervalidasi dari satu baris file.
  static Map<String, String> _record(
      List<dynamic> row, Map<String, int> map, int rowNumber) {
    final rec = <String, String>{};
    for (final field in cols) {
      final text = cell(row, map[field]!);
      if (text.startsWith('=')) {
        throw FormatException(
            'Baris $rowNumber: kolom ${headers[cols.indexOf(field)]} berisi rumus Excel ($text). Simpan sebagai nilai (salin lalu tempel sebagai values) dan impor ulang.');
      }
      rec[field] = text;
    }
    if (norm(rec['origin']!) != 'malangkota') {
      throw FormatException('Baris $rowNumber: asal harus MALANG KOTA.');
    }
    if (_addressFields.any((f) => rec[f]!.isEmpty)) {
      throw FormatException('Baris $rowNumber: data tujuan tidak lengkap.');
    }
    for (final field in numericCols) {
      final text = rec[field]!;
      if (text.isEmpty || text == '-') {
        rec[field] = '';
        continue;
      }
      final value =
          _numericText.hasMatch(text) ? util.parseTariffNumber(text) : null;
      if (value == null) {
        throw FormatException(
            'Baris $rowNumber: kolom ${headers[cols.indexOf(field)]} bukan angka ("$text").');
      }
      rec[field] = util.formatPlainNumber(value);
    }
    return rec;
  }

  static String _destinationKey(Map<String, String> rec) =>
      _addressFields.map((f) => norm(rec[f]!)).join('|');

  // Nama tujuan yang hanya berbeda spasi/tanda baca dianggap alias, dan
  // hanya boleh dilewati jika tarif/layanan selain nama wilayah identik.
  static bool _sameTariffRecord(Map<String, String> a, Map<String, String> b) {
    for (final field in cols) {
      if (_addressFields.contains(field)) continue;
      if (a[field] != b[field]) return false;
    }
    return true;
  }

  static ParsedTariff _parseRows(List<List<dynamic>> rows) {
    final at = headerAt(rows), map = mapHeader(rows[at]);
    final byKey = <String, Map<String, String>>{};
    final samples = <String>[];
    for (var i = at + 1; i < rows.length; i++) {
      final r = rows[i];
      if (r.every((v) => v.toString().trim().isEmpty)) continue;
      final rec = _record(r, map, i + 1);
      final key = _destinationKey(rec);
      final previous = byKey[key];
      if (previous != null) {
        if (!_sameTariffRecord(previous, rec)) {
          throw FormatException(
              'Tujuan ganda dengan tarif/layanan berbeda pada baris ${i + 1}: ${_addressFields.map((f) => rec[f]).join(' / ')}. Periksa sumber tarif sebelum impor.');
        }
        continue;
      }
      byKey[key] = rec;
      if (samples.length < 8) {
        samples.add(
            [rec['village'], rec['district'], rec['city'], rec['province']]
                .join(', '));
      }
    }
    if (byKey.isEmpty) {
      throw const FormatException('File tidak memiliki baris tarif.');
    }
    return ParsedTariff(
      byKey.values.toList(),
      NextCargoImportPreview(byKey.length, samples),
    );
  }

  /// Parsing sinkron (dipakai di dalam isolate dan oleh tes).
  static ParsedTariff parseSync(String name, Uint8List bytes) =>
      _parseRows(decode(name, bytes));

  static _ParseOutcome _parseSafely(String name, Uint8List bytes) {
    try {
      return _ParseOutcome(parsed: parseSync(name, bytes));
    } on FormatException catch (e) {
      return _ParseOutcome(error: e.message);
    } catch (e) {
      return _ParseOutcome(error: 'File tidak dapat dibaca: $e');
    }
  }

  /// Mengurai dan memvalidasi file di isolate terpisah agar UI tidak membeku
  /// saat membaca XLSX besar. Melempar [FormatException] bila file tidak valid.
  static Future<ParsedTariff> parse(String name, Uint8List bytes) async {
    final outcome = await Isolate.run(() => _parseSafely(name, bytes));
    final error = outcome.error;
    if (error != null) throw FormatException(error);
    return outcome.parsed!;
  }

  static Future<NextCargoImportPreview> preview(
          String name, Uint8List bytes) async =>
      (await parse(name, bytes)).preview;

  // ---------------------------------------------------------------- import

  static Future<int> importFile(String name, Uint8List bytes,
          {required bool replace}) async =>
      importParsed(await parse(name, bytes), replace: replace);

  static Future<int> importParsed(ParsedTariff parsed,
      {required bool replace}) async {
    final db = await open();
    var count = 0;
    await db.transaction((txn) async {
      count = 0;
      await txn.delete('tariff_backup');
      await txn.execute(
          'INSERT INTO tariff_backup (id,${cols.join(',')}) SELECT id,${cols.join(',')} FROM tariffs');
      final previousCount = Sqflite.firstIntValue(
            await txn.rawQuery('SELECT COUNT(*) AS n FROM tariff_backup')) ??
          0;
      await txn.update(
        'tariff_backup_meta',
        {'available': previousCount > 0 ? 1 : 0},
        where: 'id = 1',
      );
      if (replace) await txn.delete('tariffs');
      var batch = txn.batch();
      var pending = 0;
      for (final rec in parsed.records) {
        batch.insert('tariffs', rec,
            conflictAlgorithm: ConflictAlgorithm.replace);
        count++;
        pending++;
        if (pending >= 400) {
          await batch.commit(noResult: true);
          batch = txn.batch();
          pending = 0;
        }
      }
      if (pending > 0) await batch.commit(noResult: true);
    });
    _destinationVocabulary = null;
    return count;
  }

  /// Berat yang ditagihkan mengikuti minimum layanan pada baris tujuan.
  static num billableWeight(num actualWeight, num serviceMinimum) =>
      util.billableWeight(actualWeight, serviceMinimum);

  static Future<int> count() async {
    final db = await open();
    return Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) AS n FROM tariffs')) ??
        0;
  }

  static Future<bool> restore() async {
    final db = await open();
    return db.transaction((t) async {
      final available = Sqflite.firstIntValue(await t
              .rawQuery('SELECT available FROM tariff_backup_meta WHERE id = 1')) ??
          0;
      if (available == 0) return false;
      await t.delete('tariffs');
      await t.execute(
          'INSERT INTO tariffs (id,${cols.join(',')}) SELECT id,${cols.join(',')} FROM tariff_backup');
      await t.update('tariff_backup_meta', {'available': 0}, where: 'id = 1');
      _destinationVocabulary = null;
      return true;
    });
  }

  static Future<Set<String>> _loadDestinationVocabulary(Database db) async {
    final cached = _destinationVocabulary;
    if (cached != null) return cached;
    final words = <String>{};
    for (final field in _addressFields) {
      final rows = await db.rawQuery(
        'SELECT DISTINCT $field FROM tariffs WHERE $field IS NOT NULL',
      );
      for (final row in rows) {
        final value = (row[field] ?? '').toString().toUpperCase();
        words.addAll(value.split(RegExp(r'[^A-Z0-9]+')).where((w) => w.length > 3));
      }
    }
    _destinationVocabulary = words;
    return words;
  }

  /// Memisahkan penanda wilayah dari nama wilayah. Contoh:
  /// "ongkir ke Wonosobo kec Wonosobo 20 kg" menghasilkan
  /// city=WONOSOBO dan district=WONOSOBO, bukan satu token yang ambigu.
  static ({String? city, String? district}) _scopedAddress(String query) {
    final text = query.toLowerCase().replaceAll(RegExp(r'[,;]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    final districtMatch = RegExp(
      r'\b(?:kec(?:amatan)?|kec\.)\s+(.+?)(?=\s+\d|\s+(?:kg|kilo|kilogram|reguler|reg|sp1|sp2|sp3|tarif|ongkir|ongkos|berat)\b|$)',
    ).firstMatch(text);

    String? district;
    String? city;
    if (districtMatch != null) {
      district = districtMatch.group(1)!.trim();
      var cityPart = text.substring(0, districtMatch.start).trim();
      final destinationStart = RegExp(r'\bke\s+').allMatches(cityPart).toList();
      if (destinationStart.isNotEmpty) {
        cityPart = cityPart.substring(destinationStart.last.end).trim();
      }
      cityPart = cityPart
          .replaceFirst(RegExp(r'^(?:(?:tolong|mohon|coba|cek|cari|carikan|ongkir|ongkos|tarif|tujuan|kirim|pengiriman)\s+)+'), '')
          .replaceFirst(RegExp(r'^(?:kota|kabupaten|kab\.?|city)\s+'), '')
          .trim();
      if (cityPart.isNotEmpty) city = cityPart;
    } else {
      final cityMatch = RegExp(
        r'\b(?:kota|kabupaten|kab\.?)\s+(.+?)(?=\s+\d|\s+(?:kg|kilo|kilogram|reguler|reg|sp1|sp2|sp3|tarif|ongkir|ongkos|berat)\b|$)',
      ).firstMatch(text);
      if (cityMatch != null) city = cityMatch.group(1)!.trim();
    }

    // "Wonosobo Wonosobo" means city=Wonosobo and district=Wonosobo.
    // Preserve this repeated-name meaning before destinationTokens() uses Set.
    if (city == null && district == null) {
      final repeated = text
          .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
          .split(RegExp(r'\s+'))
          .where((word) => word.length >= 3 &&
              !const {
                'tolong', 'mohon', 'coba', 'cek', 'cari', 'carikan',
                'ongkir', 'ongkos', 'tarif', 'tujuan', 'kirim',
                'pengiriman', 'kota', 'kabupaten', 'kab', 'kecamatan',
                'kec', 'kelurahan', 'desa', 'malang', 'next', 'cargo',
                'reg', 'reguler', 'sp1', 'sp2', 'sp3', 'berat',
              }.contains(word))
          .toList();
      if (repeated.length == 2 && repeated[0] == repeated[1]) {
        city = repeated.first;
        district = repeated.last;
      }
    }

    String? clean(String? value) {
      if (value == null || value.isEmpty) return null;
      return value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9 ]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    return (city: clean(city), district: clean(district));
  }

  static Future<List<Map<String, Object?>>> _queryTokens(
    Database db,
    List<String> tokens, {
    String? city,
    String? district,
  }) async {
    final clauses = <String>[];
    final args = <Object?>[];
    for (final token in tokens) {
      clauses.add('(${_addressFields.map((f) => '$f LIKE ?').join(' OR ')})');
      for (var i = 0; i < _addressFields.length; i++) {
        args.add('%$token%');
      }
    }
    if (city != null) {
      clauses.add('UPPER(city) LIKE ?');
      args.add('%$city%');
    }
    if (district != null) {
      clauses.add('UPPER(district) LIKE ?');
      args.add('%$district%');
    }
    if (clauses.isEmpty) return [];
    return db.query(
      'tariffs',
      columns: cols,
      where: clauses.join(' AND '),
      whereArgs: args,
      orderBy: 'province ASC, city ASC, district ASC, village ASC',
      limit: util.kMaxTariffMatches,
    );
  }

  static Future<List<Map<String, Object?>>> findDestination(
      String query) async {
    final db = await open();
    final tokens = util.destinationTokens(query);
    final scope = _scopedAddress(query);
    if (tokens.isEmpty && scope.city == null && scope.district == null) return [];

    // A single exact city name takes precedence over incidental matches
    // in other cities' district or village columns.
    if (scope.city == null && scope.district == null && tokens.length == 1) {
      final name = tokens.single;
      // Untuk input nama kota saja, ambil satu baris per kecamatan,
      // bukan membatasi delapan kelurahan pertama. Dengan begitu seluruh
      // kecamatan kota tersebut dapat ditampilkan sebagai saran.
      final cityMatches = await db.query(
        'tariffs',
        columns: cols,
        where: 'UPPER(city) LIKE ?',
        whereArgs: ['%$name%'],
        groupBy: 'province, city, district',
        orderBy: 'province ASC, city ASC, district ASC',
      );
      if (cityMatches.isNotEmpty) {
        return cityMatches
            .map((row) => <String, Object?>{
                  ...row,
                  '_suggestion_level': 'district',
                })
            .toList();
      }

      final districtMatches = await db.query(
        'tariffs',
        columns: cols,
        where: 'UPPER(district) = ?',
        whereArgs: [name],
        orderBy: 'province ASC, city ASC, district ASC, village ASC',
        limit: util.kMaxTariffMatches,
      );
      if (districtMatches.isNotEmpty) return districtMatches;
    }

    final exact = await _queryTokens(
      db,
      tokens,
      city: scope.city,
      district: scope.district,
    );
    if (exact.isNotEmpty) return exact;

    // Koreksi ejaan hanya untuk token bebas. Batas kota/kecamatan yang
    // disebut eksplisit tetap dipertahankan agar tidak pindah kolom wilayah.
    final vocabulary = await _loadDestinationVocabulary(db);
    final corrected = util.resolveTokens(tokens, vocabulary);
    if (corrected.join('|') == tokens.join('|')) return [];
    return _queryTokens(
      db,
      corrected,
      city: scope.city,
      district: scope.district,
    );
  }
}

/// Penghubung mesin jawaban ke database SQLite.
class SqliteTariffLookup implements TariffLookup {
  const SqliteTariffLookup();

  @override
  Future<List<Map<String, Object?>>> find(String query) =>
      NextCargoTariffService.findDestination(query);

  @override
  Future<int> count() => NextCargoTariffService.count();
}
