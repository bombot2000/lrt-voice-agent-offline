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
    }).take(kMaxTariffMatches).toList();
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
          contains('Reguler 25 kg: 25 kg × Rp 4.700/kg = Rp 117.500'));
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

    test('tarif khusus 1 kg memakai minimum Reguler dikali tarif khusus', () async {
      final engine = AnswerEngine(FakeLookup(rows: [bekasiJatiAsih], total: 1));
      final a = await engine.answer('Bekasi Jati Asih 1 kg tarif khusus');
      expect(a, contains('Tarif khusus: minimum Reguler 25 kg, berat tagihan 25 kg'));
      expect(a, contains('25 kg × Rp 3.400/kg = Rp 85.000'));
      expect(a, isNot(contains('Reguler:')));
      expect(a, isNot(contains('SP1')));
      expect(a, isNot(contains('SP3')));
    });

    test('tarif khusus 30 kg memakai berat aktual dikali tarif khusus', () async {
      final engine = AnswerEngine(FakeLookup(rows: [bekasiJatiAsih], total: 1));
      final a = await engine.answer('Bekasi Jati Asih 30 kg tarif khusus');
      expect(a, contains('berat tagihan 30 kg'));
      expect(a, contains('30 kg × Rp 3.400/kg = Rp 102.000'));
      expect(a, isNot(contains('Reguler:')));
      expect(a, isNot(contains('SP1')));
      expect(a, isNot(contains('SP3')));
    });

    test('SP1 tidak berlaku di bawah minimum dan turun ke Reguler', () async {
      final engine = AnswerEngine(FakeLookup(rows: [bekasiJatiAsih], total: 1));
      final a = await engine.answer('Bekasi Jati Asih 30 kg SP1');
      expect(a, contains('SP1 belum berlaku karena minimum 200 kg'));
      expect(a, contains('Reguler: berat aktual 30 kg, berat tagihan 30 kg'));
      expect(a, contains('Rp 141.000'));
      expect(a, isNot(contains('SP1: berat aktual')));
    });

    test('SP3 tidak berlaku di bawah minimum dan turun ke SP1 yang memenuhi', () async {
      final engine = AnswerEngine(FakeLookup(rows: [bekasiJatiAsih], total: 1));
      final a = await engine.answer('Bekasi Jati Asih 250 kg SP3');
      expect(a, contains('SP3 belum berlaku karena minimum 1000 kg'));
      expect(a, contains('SP1: berat aktual 250 kg, berat tagihan 250 kg'));
      expect(a, contains('Rp 1.125.000'));
      expect(a, isNot(contains('SP3: berat aktual')));
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

    test('permintaan Reguler diberi tahu bila berat masuk tier lebih tinggi', () async {
      final row = <String, Object?>{
        ...bekasiJatiAsih,
        'min_sp2': '300',
        'tarif_sp2': '4300',
      };
      final engine = AnswerEngine(FakeLookup(rows: [row], total: 1));
      final a = await engine.answer('Bekasi Jati Asih 300 kg Reguler');
      expect(a, contains('Berat memenuhi minimum SP2, memakai tarif SP2.'));
      expect(a, contains('SP2: berat aktual 300 kg'));
    });

    test('berat tidak menghasilkan jawaban tanpa angka jika tarif Reguler kosong', () async {
      final row = <String, Object?>{
        ...abiansemal,
        'min_reg': '',
        'tarif_reg': '',
      };
      final engine = AnswerEngine(FakeLookup(rows: [row], total: 1));
      final a = await engine.answer('Abiansemal 20 kg');
      expect(a, contains('Tarif Reguler tidak tersedia'));
      expect(a, isNot(contains('minimum layanan berlaku).')));
    });

    test('SP2 dipilih saat berat memenuhi minimum SP2 dan belum SP3', () async {
      final row = <String, Object?>{
        ...bekasiJatiAsih,
        'min_sp2': '500',
        'tarif_sp2': '4300',
      };
      final engine = AnswerEngine(FakeLookup(rows: [row], total: 1));
      final a = await engine.answer('Bekasi Jati Asih 600 kg');
      expect(a, contains('SP2: berat aktual 600 kg, berat tagihan 600 kg'));
      expect(a, contains('Rp 2.580.000'));
      expect(a, isNot(contains('SP1:')));
      expect(a, isNot(contains('SP3:')));
    });

    test('SP2 tidak berlaku di bawah minimum dan turun ke SP1', () async {
      final row = <String, Object?>{
        ...bekasiJatiAsih,
        'min_sp2': '500',
        'tarif_sp2': '4300',
      };
      final engine = AnswerEngine(FakeLookup(rows: [row], total: 1));
      final a = await engine.answer('Bekasi Jati Asih 250 kg SP2');
      expect(a, contains('SP2 belum berlaku karena minimum 500 kg'));
      expect(a, contains('SP1: berat aktual 250 kg'));
      expect(a, contains('Rp 1.125.000'));
      expect(a, isNot(contains('SP2: berat aktual')));
    });

    test('SP3 dipilih saat berat memenuhi minimum SP3', () async {
      final row = <String, Object?>{
        ...bekasiJatiAsih,
        'min_sp2': '500',
        'tarif_sp2': '4300',
      };
      final engine = AnswerEngine(FakeLookup(rows: [row], total: 1));
      final a = await engine.answer('Bekasi Jati Asih 1200 kg');
      expect(a, contains('SP3: berat aktual 1200 kg, berat tagihan 1200 kg'));
      expect(a, contains('Rp 4.800.000'));
      expect(a, isNot(contains('SP1:')));
      expect(a, isNot(contains('SP2:')));
    });

    test('berat 1200 kg tetap memilih SP3 meski pertanyaan menyebut Reguler', () async {
      final row = <String, Object?>{
        ...bekasiJatiAsih,
        'min_sp2': '500',
        'tarif_sp2': '4300',
      };
      final engine = AnswerEngine(FakeLookup(rows: [row], total: 1));
      final a = await engine.answer('Bekasi Jati Asih 1200 kg Reguler');
      expect(a, contains('SP3: berat aktual 1200 kg'));
      expect(a, contains('Rp 4.800.000'));
      expect(a, isNot(contains('Reguler:')));
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
      expect(a, contains('Reguler 25 kg: 25 kg × Rp 4.700/kg = Rp 117.500; setiap kg berikutnya Rp 4.700/kg.'));
      expect(a, isNot(contains('SP1')));
      expect(a, isNot(contains('SP2')));
      expect(a, isNot(contains('SP3')));
      expect(a, isNot(contains('Tarif khusus')));
      expect(a, isNot(contains('Tarif 10 kg'))); // nilai 0 tidak dibacakan
    });


    test('Wonosobo default menampilkan tarif 10 kg dan 20 kg tanpa tarif khusus; khusus hanya saat diminta', () async {
      final row = <String, Object?>{
        'province': 'JAWA TENGAH',
        'city': 'WONOSOBO',
        'district': 'WONOSOBO',
        'village': 'BOMERTO',
        'tarif_10kg': '3900',
        'min_reg': '20',
        'tarif_reg': '2700',
        'tarif_khusus': '1950',
        'min_sp1': '200',
        'tarif_sp1': '2600',
        'min_sp2': '500',
        'tarif_sp2': '2450',
        'min_sp3': '1000',
        'tarif_sp3': '2300',
      };
      final engine = AnswerEngine(FakeLookup(rows: [row], total: 1));

      final regular = await engine.answer('Wonosobo Wonosobo');
      expect(regular, contains('Tarif 10 kg Rp 3.900.'));
      expect(regular, contains('Reguler 20 kg: 20 kg × Rp 2.700/kg = Rp 54.000'));
      expect(regular, isNot(contains('Tarif khusus')));
      expect(regular, isNot(contains('Rp 1.950')));

      final special = await engine.answer('Wonosobo Wonosobo tarif khusus');
      expect(special, contains('Tarif khusus: minimum Reguler 20 kg'));
      expect(special, contains('20 kg × Rp 1.950/kg = Rp 39.000'));
      expect(special, isNot(contains('Tarif 10 kg')));
      expect(special, isNot(contains('Reguler 20 kg:')));
    });

    test('tarif tujuan tanpa berat memakai Reguler dan menampilkan total minimum', () async {
      final row = <String, Object?>{
        ...bekasiJatiAsih,
        'min_reg': '20',
        'tarif_reg': '3100',
      };
      final engine = AnswerEngine(FakeLookup(rows: [row], total: 1));
      final a = await engine.answer('tarif ke Bekasi Jati Asih');
      expect(a, contains('Reguler 20 kg: 20 kg × Rp 3.100/kg = Rp 62.000; setiap kg berikutnya Rp 3.100/kg.'));
      expect(a, isNot(contains('SP1')));
      expect(a, isNot(contains('SP2')));
      expect(a, isNot(contains('SP3')));
    });

    test('pencarian nama kota menampilkan semua saran kecamatan', () async {
      final districts = [
        'KEPANJEN', 'PAKISAJI', 'TAJINAN', 'BULULAWANG',
        'TUREN', 'DAMPIT', 'PAGELARAN', 'WAGIR',
      ];
      final rows = districts.map((district) => <String, Object?>{
        ...abiansemal,
        'city': 'KABUPATEN MALANG',
        'district': district,
        'village': district,
        '_suggestion_level': 'district',
      }).toList();
      final engine = AnswerEngine(FakeLookup(rows: rows, total: rows.length));
      final reply = await engine.ask('Malang');
      expect(reply.choices.length, districts.length);
      expect(
        reply.choices.map((choice) => choice.label.split(', ')[1]).toSet(),
        districts.toSet(),
      );
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
      expect(r.choices.first.label, 'BADUNG, ABIANSEMAL, ABIANSEMAL, BALI');
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

    test('follow-up menemukan tujuan di luar delapan kandidat awal', () async {
      final many = <Map<String, Object?>>[
        for (var i = 0; i < 12; i++)
          <String, Object?>{
            ...abiansemal,
            'village': 'VILLAGE $i',
            'district': 'BADUNG',
          },
        sibang,
      ];
      final engine = AnswerEngine(FakeLookup(rows: many, total: many.length));
      final first = await engine.ask('ongkir ke Badung 20 kilo');
      expect(first.choices.length, 6);
      final narrowed = await engine.ask('Sibang');
      expect(narrowed.text, contains('SIBANG KAJA'));
      expect(narrowed.text, contains('berat aktual 20 kg'));
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
