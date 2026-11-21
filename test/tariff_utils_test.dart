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

  test('formatPlainNumber dan formatRupiah', () {
    expect(formatPlainNumber(25.0), '25');
    expect(formatPlainNumber(12.5), '12.5');
    expect(formatRupiah(117500), 'Rp 117.500');
    expect(formatRupiah(0), 'Rp 0');
  });

  test('destinationTokens membuang kata perintah, angka, dan kata pendek', () {
    expect(destinationTokens('Tolong ongkir ke Abiansemal Badung 20 kilo reguler'),
        equals(['ABIANSEMAL', 'BADUNG']));
    expect(destinationTokens('selamat pagi'), equals(<String>[]));
  });
}
