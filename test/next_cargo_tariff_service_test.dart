import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lrt_voice_agent_offline/next_cargo_tariff_service.dart';

void main() {
  const header = 'Asal Kota,Tj. Propinsi,Tj. Kota,Tj. Kecamatan,Tj. Kelurahan,Handler,Stt Dooring,Lead Time,Tarif 10Kg,Min Reg,Tarif Reg,Min SP1,Tarif SP1,Min SP2,Tarif SP2,Min SP3,Tarif SP3,Tarif Khusus,Motor 100cc,Motor 125cc,Motor 150cc,Motor 250cc,Motor 500cc,Motor 750cc,Sepeda';
  const row = 'MALANG KOTA,BALI,BADUNG,ABIANSEMAL,ABIANSEMAL,DENPASAR AGEN,EKSPEDISI LAIN,6,0,25,4700,200,4500,500,4250,1000,4000,3400,705000,945900,1175000,1903500,2350000,3231250,293750';
  Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));

  test('detects header after title and blank row, retaining NEXT Cargo structure', () async {
    final result = await NextCargoTariffService.preview(bytes('NEXT TARIF 2026-11-21\n\n$header\n$row\n'));
    expect(result.rowCount, 1);
    expect(result.sampleDestinations.single, 'ABIANSEMAL, ABIANSEMAL, BADUNG, BALI');
  });

  test('rejects origin other than MALANG KOTA', () async {
    expect(
      () => NextCargoTariffService.preview(bytes('$header\nJAKARTA,BALI,BADUNG,ABIANSEMAL,ABIANSEMAL,DENPASAR AGEN,EKSPEDISI LAIN,6,0,25,4700,200,4500,500,4250,1000,4000,3400,705000,945900,1175000,1903500,2350000,3231250,293750')),
      throwsFormatException,
    );
  });

  test('rejects duplicate destination keys', () async {
    expect(
      () => NextCargoTariffService.preview(bytes('$header\n$row\n$row')),
      throwsFormatException,
    );
  });

  test('rejects a generic four-column fare CSV', () async {
    expect(
      () => NextCargoTariffService.preview(bytes('asal,tujuan,layanan,ongkir\nMALANG,SURABAYA,REG,15000')),
      throwsFormatException,
    );
  });
}
