import 'package:flutter_test/flutter_test.dart';
import 'package:cargo_voice_agent_offline/answer_engine.dart';
import 'package:cargo_voice_agent_offline/tariff_utils.dart';

class FakeLookup implements TariffLookup {
  final List<Map<String, Object?>> rows;
  final int total;
  final bool failOnFind;
  FakeLookup({this.rows = const [], this.total = 0, this.failOnFind = false});

  // Meniru pencarian SQLite: semua kata tujuan harus ada di alamat.
  @override
  Future<List<Map<String, Object?>>> find(String query) async {
    if (failOnFind) throw StateError('db error');
    final tokens = destinationTokens(query);
    if (tokens.isEmpty) return [];
    return rows.where((r) {
      final text =
          [r['province'], r['city'], r['district'], r['village']].join(' ');
      return tokens.every(text.contains);
    }).toList();
  }

  @override
  Future<int> count() async => total;
}

const sibang = <String, Object?>{
  'province': 'BALI',
  'city': 'BADUNG',
  'district': 'ABIANSEMAL',
  'village': 'SIBANG KAJA',
  'handler': 'DENPASAR AGEN',
  'lead_time': '7',
  'min_reg': '25',
  'tarif_reg': '5200',
};

const bekasiJatiAsih = <String, Object?>{
  'province': 'JAWA BARAT',
  'city': 'BEKASI',
  'district': 'JATIASIH',
  'village': 'JATIASIH',
  'min_reg': '25',
  'tarif_reg': '4700',
  'min_sp1': '200',
  'tarif_sp1': '4500',
  'min_sp3': '1000',
  'tarif_sp3': '4000',
  'tarif_khusus': '3400',
  'lead_time': '3',
  'handler': 'BEKASI AGEN',
};

const abiansemal = <String, Object?>{
  'province': 'BALI',
  'city': 'BADUNG',
  'district': 'ABIANSEMAL',
  'village': 'ABIANSEMAL',
  'handler': 'DENPASAR AGEN',
  'lead_time': '6',
  'tarif_10kg': '0',
  'min_reg': '25',
  'tarif_reg': '4700',
  'min_sp1': '200',
  'tarif_sp1': '4500',
  'min_sp2': '',
  'tarif_sp2': '',
  'min_sp3': '1000',
  'tarif_sp3': '4000',
  'tarif_khusus': '3400',
};

void main() {
  group('sapaan', () {
    test('sapaan dan bantuan menjelaskan cara bertanya', () async {
      final engine = AnswerEngine(FakeLookup(total: 5));
      expect(await engine.answer('halo'), contains('ongkir NEXT Cargo'));
      expect(await engine.answer('bisa apa'), contains('ongkir NEXT Cargo'));
    });

    test('sapaan di depan pertanyaan ongkir tidak mengganggu', () async {
      final engine = AnswerEngine(FakeLookup(rows: [abiansemal], total: 1));
      expect(await engine.answer('selamat pagi ongkir ke Abiansemal'),
          contains('Reguler: minimum 25 kg'));
    });
  });

  group('pertanyaan kargo', () {
    test('tujuan cocok dengan berat dan layanan', () async {
      final engine = AnswerEngine(FakeLookup(rows: [abiansemal], total: 1));
      final a = await engine.answer('ongkir ke Abiansemal Badung 20 kilo reguler');
      expect(a, contains('Reguler: berat aktual 20 kg, berat tagihan 25 kg'));
      expect(a, contains('Rp 117.500'));
      expect(a, isNot(contains('SP1')));
      expect(a, isNot(contains('25.0')));
    });

    test('berat tanpa layanan memakai Reguler dan tidak mencampur kolom lain', () async {
      final engine = AnswerEngine(FakeLookup(rows: [bekasiJatiAsih], total: 1));
      final a = await engine.answer('Bekasi Jati Asih 30 kg');
      expect(a, contains('Reguler: berat aktual 30 kg, berat tagihan 30 kg'));
      expect(a, contains('Rp 141.000')); // 30 kg x Rp 4.700
      expect(a, isNot(contains('SP1')));
      expect(a, isNot(contains('SP3')));
      expect(a, isNot(contains('Tarif khusus')));
      expect(a, isNot(contains('Handler')));
      expect(a, isNot(contains('Lead time')));
    });

    test('layanan SP1 eksplisit memakai minimum SP1 dan hanya menghitung SP1', () async {
      final engine = AnswerEngine(FakeLookup(rows: [bekasiJatiAsih], total: 1));
      final a = await engine.answer('Bekasi Jati Asih 30 kg SP1');
      expect(a, contains('SP1: berat aktual 30 kg, berat tagihan 200 kg'));
      expect(a, contains('Rp 900.000')); // minimum 200 kg x Rp 4.500
      expect(a, isNot(contains('Reguler')));
      expect(a, isNot(contains('SP3')));
    });

    test('layanan SP3 eksplisit memakai minimum SP3 dan hanya menghitung SP3', () async {
      final engine = AnswerEngine(FakeLookup(rows: [bekasiJatiAsih], total: 1));
      final a = await engine.answer('Bekasi Jati Asih 30 kg SP3');
      expect(a, contains('SP3: berat aktual 30 kg, berat tagihan 1000 kg'));
      expect(a, contains('Rp 4.000.000')); // minimum 1000 kg x Rp 4.000
      expect(a, isNot(contains('Reguler')));
      expect(a, isNot(contains('SP1')));
    });

    test('berat 30 kg tidak memakai SP1 yang minimum 200 kg walau disebut', () async {
      final engine = AnswerEngine(FakeLookup(rows: [bekasiJatiAsih], total: 1));
      final a = await engine.answer('Bekasi Jati Asih 30 kg SP1');
      expect(a, contains('SP1 belum berlaku karena minimum 200 kg'));
      expect(a, contains('Reguler: berat aktual 30 kg, berat tagihan 30 kg'));
      expect(a, contains('Rp 141.000'));
      expect(a, isNot(contains('SP1: berat aktual')));
      expect(a, isNot(contains('Rp 900.000')));
    });

    test('berat 250 kg otomatis masuk SP1 jika minimum SP1 200 kg', () async {
      final engine = AnswerEngine(FakeLookup(rows: [bekasiJatiAsih], total: 1));
      final a = await engine.answer('Bekasi Jati Asih 250 kg');
      expect(a, contains('SP1: berat aktual 250 kg, berat tagihan 250 kg'));
      expect(a, contains('Rp 1.125.000'));
      expect(a, isNot(contains('Reguler:')));
      expect(a, isNot(contains('SP3:')));
    });

    test('berat di bawah minimum memakai berat minimum layanan', () async {
      final engine = AnswerEngine(FakeLookup(rows: [bekasiJatiAsih], total: 1));
      final a = await engine.answer('Bekasi Jati Asih 10 kg');
      expect(a, contains('berat aktual 10 kg, berat tagihan 25 kg'));
      expect(a, contains('Rp 117.500')); // minimum 25 kg x Rp 4.700
      expect(a, isNot(contains('SP1')));
    });

    test('tanpa berat menampilkan minimum dan tarif per kg', () async {
      final engine = AnswerEngine(FakeLookup(rows: [abiansemal], total: 1));
      final a = await engine.answer('tarif ke Abiansemal');
      expect(a, contains('Reguler: minimum 25 kg, tarif Rp 4.700/kg.'));
      expect(a, contains('SP3: minimum 1000 kg, tarif Rp 4.000/kg.'));
      expect(a, isNot(contains('SP2'))); // kolom kosong dilewati
      expect(a, contains('Tarif khusus Rp 3.400.'));
      expect(a, isNot(contains('Tarif 10 kg'))); // nilai 0 tidak dibacakan
    });

    test('beberapa tujuan cocok meminta perincian', () async {
      final engine =
          AnswerEngine(FakeLookup(rows: [abiansemal, abiansemal], total: 2));
      expect(await engine.answer('ongkir ke Abiansemal'),
          contains('2 tujuan yang cocok'));
    });

    test('tujuan tidak ditemukan menyebut jumlah tujuan tersedia', () async {
      final engine = AnswerEngine(FakeLookup(total: 3));
      expect(await engine.answer('ongkir paket 5 kg'),
          contains('tersedia untuk 3 tujuan'));
      expect(await engine.answer('ke Atlantis'),
          contains('tersedia untuk 3 tujuan'));
    });

    test('database kosong mengarahkan ke menu impor', () async {
      final engine = AnswerEngine(FakeLookup());
      expect(await engine.answer('ongkir paket 5 kg'),
          contains('belum diimpor'));
    });

    test('layanan yang diminta tetapi tidak ada', () async {
      final engine = AnswerEngine(FakeLookup(rows: [abiansemal], total: 1));
      expect(await engine.answer('ongkir sp2 ke Abiansemal'),
          contains('SP2 tidak tersedia'));
    });

    test('kegagalan database tidak melempar error', () async {
      final engine = AnswerEngine(FakeLookup(failOnFind: true));
      expect(await engine.answer('ongkir ke Abiansemal'),
          contains('tidak dapat dibaca'));
    });
  });

  group('dialog bertahap', () {
    final rows = [abiansemal, sibang];

    test('hasil ambigu memberi pilihan yang bisa diketuk', () async {
      final engine = AnswerEngine(FakeLookup(rows: rows, total: 2));
      final r = await engine.ask('ongkir ke Abiansemal 20 kilo');
      expect(r.text, contains('2 tujuan yang cocok'));
      expect(r.choices.length, 2);
      expect(r.choices.first.label, 'ABIANSEMAL, ABIANSEMAL, BADUNG, BALI');
      expect(engine.hasPendingChoice, true);
    });

    test('mengetuk pilihan memakai berat dari pertanyaan awal', () async {
      final engine = AnswerEngine(FakeLookup(rows: rows, total: 2));
      final r = await engine.ask('ongkir ke Abiansemal 20 kilo');
      final answer = engine.select(r.choices.last);
      expect(answer.text, contains('SIBANG KAJA'));
      expect(answer.text, contains('berat aktual 20 kg'));
      expect(answer.text, contains('Rp 130.000')); // 25 kg x 5.200
      expect(engine.hasPendingChoice, false);
    });

    test('menyebut kelurahan saja sudah cukup, berat tidak perlu diulang',
        () async {
      final engine = AnswerEngine(FakeLookup(rows: rows, total: 2));
      await engine.ask('ongkir ke Abiansemal 20 kilo');
      final r = await engine.ask('Sibang');
      expect(r.text, contains('SIBANG KAJA'));
      expect(r.text, contains('berat aktual 20 kg'));
      expect(r.choices, isEmpty);
      expect(engine.hasPendingChoice, false);
    });

    test('jawaban yang tidak cocok kandidat dianggap pertanyaan baru',
        () async {
      final engine = AnswerEngine(FakeLookup(rows: rows, total: 2));
      await engine.ask('ongkir ke Abiansemal');
      final r = await engine.ask('ongkir ke Atlantis');
      expect(r.text, contains('tersedia untuk 2 tujuan'));
      expect(engine.hasPendingChoice, false);
    });

    test('jawaban yang masih ambigu mempertahankan dialog', () async {
      final engine = AnswerEngine(FakeLookup(rows: rows, total: 2));
      await engine.ask('ongkir ke Bali');
      final r = await engine.ask('Badung');
      expect(r.text, contains('2 tujuan yang cocok'));
      expect(engine.hasPendingChoice, true);
    });
  });
}
