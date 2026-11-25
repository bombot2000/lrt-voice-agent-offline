import 'package:flutter_test/flutter_test.dart';
import 'package:cargo_voice_agent_offline/tariff_utils.dart';

void main() {
  group('parseTariffNumber', () {
    test('angka polos dan desimal titik', () {
      expect(parseTariffNumber('4700'), 4700);
      expect(parseTariffNumber('4700.0'), 4700);
      expect(parseTariffNumber('25.5'), 25.5);
      expect(parseTariffNumber('0.500'), 0.5);
    });

    test('pemisah ribuan Indonesia dan Inggris tidak jadi desimal', () {
      expect(parseTariffNumber('4.700'), 4700);
      expect(parseTariffNumber('4,700'), 4700);
      expect(parseTariffNumber('1.250.000'), 1250000);
      expect(parseTariffNumber('Rp 4.700'), 4700);
    });

    test('pemisah ribuan dan desimal bersamaan', () {
      expect(parseTariffNumber('4.700,50'), 4700.5);
      expect(parseTariffNumber('4,700.50'), 4700.5);
      expect(parseTariffNumber('12,5'), 12.5);
    });

    test('kosong atau bukan angka menghasilkan null', () {
      expect(parseTariffNumber(''), isNull);
      expect(parseTariffNumber(null), isNull);
      expect(parseTariffNumber('-'), isNull);
      expect(parseTariffNumber('abc'), isNull);
    });
  });


  test('formatTypedReply structures typed fare answer', () {
    expect(
      formatTypedReply(
        'Perkiraan ongkir NEXT Cargo dari MALANG KOTA ke Sibang, Abiansemal, Badung untuk berat 30 kg (minimum layanan berlaku). Berat memenuhi minimum Reguler, memakai tarif Reguler. Reguler: berat aktual 30 kg, berat tagihan 30 kg × Rp 5.200/kg = Rp 156.000.',
      ),
      'PERKIRAAN ONGKIR NEXT CARGO\nTujuan: Sibang, Abiansemal, Badung\nBerat: 30 kg\n\nCatatan:\n• Berat memenuhi minimum Reguler, memakai tarif Reguler.\n\nRincian tarif:\n• Reguler: berat aktual 30 kg, berat tagihan 30 kg × Rp 5.200/kg = Rp 156.000',
    );
  });

  test('formatTypedReply structures tariff without weight', () {
    expect(
      formatTypedReply(
        'Tarif NEXT Cargo dari MALANG KOTA ke Blitar. Reguler: minimum 10 kg, total tarif minimum Rp 47.000; setiap kg berikutnya Rp 4.700/kg. Tarif khusus Rp 4.500.',
      ),
      'INFORMASI TARIF NEXT CARGO\nTujuan: Blitar\n\nRincian tarif:\n• Reguler: minimum 10 kg, total tarif minimum Rp 47.000; setiap kg berikutnya Rp 4.700/kg\n• Tarif khusus Rp 4.500',
    );
  });

  test('spokenVersion preserves sentence punctuation and words containing kg', () {
    expect(spokenVersion('Tarif khusus Rp 3.400. Tarif Pakgading tersedia.'),
        'Tarif khusus tiga ribu empat ratus rupiah. Tarif Pakgading tersedia.');
  });

  test('spokenVersion keeps automatic service-tier explanation readable', () {
    const notice = 'Berat memenuhi minimum SP2, memakai tarif SP2.';
    expect(spokenVersion(notice), 'Berat memenuhi minimum S P dua, memakai tarif S P dua.');
  });

  test('spokenVersion expands district abbreviation, service tiers and equals', () {
    expect(
      spokenVersion('Kab. MALANG SP1 = Rp 25.000'),
      'Kabupaten MALANG S P satu sama dengan dua puluh lima ribu rupiah',
    );
  });

  test('formatDestination uses village-first title case and skips empty levels', () {
    expect(
      formatDestination(
        village: 'SIBANG KAJA',
        district: 'ABIANSEMAL',
        city: 'BADUNG',
        province: 'BALI',
      ),
      'Sibang Kaja, Abiansemal, Badung, Bali',
    );
    expect(
      formatDestination(district: 'PAKISAJI', city: 'KABUPATEN MALANG', province: 'JAWA TIMUR'),
      'Pakisaji, Kabupaten Malang, Jawa Timur',
    );
  });

  test('spokenVersion reads rupiah and tariff operators naturally', () {
    expect(spokenVersion('Rp 117.500 × Rp 4.700/kg'),
        'seratus tujuh belas ribu lima ratus rupiah kali empat ribu tujuh ratus rupiah per kilogram');
  });

  test('formatPlainNumber dan formatRupiah', () {
    expect(formatPlainNumber(25.0), '25');
    expect(formatPlainNumber(12.5), '12.5');
    expect(formatRupiah(117500), 'Rp 117.500');
    expect(formatRupiah(0), 'Rp 0');
  });

  test('destinationTokens menyatukan ejaan Jati Asih menjadi Jatiasih', () {
    expect(destinationTokens('Bekasi Jati Asih 30 kg'), ['BEKASI', 'JATIASIH']);
  });

  test('destinationTokens membuang kata perintah, angka, dan kata pendek', () {
    expect(destinationTokens('Tolong ongkir ke Abiansemal Badung 20 kilo reguler'),
        equals(['ABIANSEMAL', 'BADUNG']));
    expect(destinationTokens('selamat pagi'), equals(<String>[]));
    expect(destinationTokens('Kabupaten Blitar'), ['BLITAR']);
    expect(destinationTokens('Kota Blitar'), ['BLITAR']);
    expect(destinationTokens('ongkir dari Malang Kota ke Sibang 20 kilo'), ['SIBANG']);
  });

  group('berat terbilang dan token tujuan', () {
    test('membaca berat angka dalam kata dan desimal', () {
      expect(parseWeight('lima belas kilo'), 15);
      expect(parseWeight('dua puluh lima koma lima kg'), 25.5);
      expect(parseWeight('seratus kilo'), 100);
      expect(parseWeight('seratus dua puluh kilo'), 120);
      expect(parseWeight('dua ratus lima puluh kilo'), 250);
      expect(parseWeight('dua ribu tiga ratus empat puluh kilo'), 2340);
      expect(parseWeight('2.500 kg'), 2500);
      expect(parseWeight('1.500 kg'), 1500);
      expect(parseWeight('2,5 kg'), 2.5);
      // Spasi antara angka dan satuan bersifat opsional.
      expect(parseWeight('10 kg'), 10);
      expect(parseWeight('10kg'), 10);
      expect(parseWeight('10 KG'), 10);
      expect(parseWeight('10KG'), 10);
      expect(parseWeight('seribu lima ratus kilo'), 1500);
    });

    test('frasa berat tidak menjadi token tujuan', () {
      expect(destinationTokens('ongkir ke Abiansemal dua puluh kilo'),
          ['ABIANSEMAL']);
      expect(destinationTokens('ongkir ke Abiansemal 10 kg'), ['ABIANSEMAL']);
      expect(destinationTokens('ongkir ke Abiansemal 10kg'), ['ABIANSEMAL']);
      expect(destinationTokens('ongkir ke Abiansemal 2,5kg'), ['ABIANSEMAL']);
      expect(destinationTokens('ongkir ke Abiansemal dua puluh lima koma lima kilogram'), ['ABIANSEMAL']);
      expect(destinationTokens('tarif ke Denpasaar lima belas kilo'),
          ['DENPASAAR']);
    });

    test('akhiran kata perintah dikenali tanpa memotong nama tujuan', () {
      expect(destinationTokens('ongkirnya ke Abiansemal hitungkan'),
          ['ABIANSEMAL']);
      expect(destinationTokens('tarifnya ke Jatiasih'), ['JATIASIH']);
    });

    test('fuzzy koreksi hanya untuk kata yang cukup mirip', () {
      expect(resolveTokens(['ABIANSEMEL'], ['ABIANSEMAL']), ['ABIANSEMAL']);
      expect(resolveTokens(['DENPASAAR'], ['DENPASAR']),
          ['DENPASAR']);
      expect(resolveTokens(['ATLANTIS'], ['ABIANSEMAL', 'DENPASAR']),
          ['ATLANTIS']);
      expect(resolveTokens(['KOT'], ['KOTA']), ['KOT']);
    });
  });

}
