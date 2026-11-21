import 'package:flutter_test/flutter_test.dart';
import 'package:cargo_voice_agent_offline/answer_engine.dart';

class FakeLookup implements TariffLookup {
  final List<Map<String, Object?>> rows;
  final int total;
  final bool failOnFind;
  FakeLookup({this.rows = const [], this.total = 0, this.failOnFind = false});

  @override
  Future<List<Map<String, Object?>>> find(String query) async {
    if (failOnFind) throw StateError('db error');
    return rows;
  }

  @override
  Future<int> count() async => total;
}

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
          contains('beberapa tujuan'));
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
}
