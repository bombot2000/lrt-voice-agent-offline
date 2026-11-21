import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:excel/excel.dart' as xls;
import 'package:cargo_voice_agent_offline/next_cargo_tariff_service.dart';

void main() {
  const header = 'Asal Kota,Tj. Propinsi,Tj. Kota,Tj. Kecamatan,Tj. Kelurahan,Handler,Stt Dooring,Lead Time,Tarif 10Kg,Min Reg,Tarif Reg,Min SP1,Tarif SP1,Min SP2,Tarif SP2,Min SP3,Tarif SP3,Tarif Khusus,Motor 100cc,Motor 125cc,Motor 150cc,Motor 250cc,Motor 500cc,Motor 750cc,Sepeda';
  const row = 'MALANG KOTA,BALI,BADUNG,ABIANSEMAL,ABIANSEMAL,DENPASAR AGEN,EKSPEDISI LAIN,6,0,25,4700,200,4500,500,4250,1000,4000,3400,705000,945900,1175000,1903500,2350000,3231250,293750';
  Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));

  test('detects header after title and blank row, retaining NEXT Cargo structure', () async {
    final result = await NextCargoTariffService.preview('sample.csv', bytes('NEXT TARIF 2026-11-21\n\n$header\n$row\n'));
    expect(result.rowCount, 1);
    expect(result.sampleDestinations.single, 'ABIANSEMAL, ABIANSEMAL, BADUNG, BALI');
  });

  test('reads typed XLSX cells and finds tariff sheet after a cover sheet', () async {
    final workbook = xls.Excel.createExcel();
    final cover = workbook['Cover'];
    cover.cell(xls.CellIndex.indexByString('A1')).value =
        xls.TextCellValue('Keterangan tarif');
    final sheet = workbook['Tarif'];
    sheet.cell(xls.CellIndex.indexByString('A1')).value =
        xls.TextCellValue('DATA TARIF NEXT CARGO');
    for (var i = 0; i < header.split(',').length; i++) {
      sheet.cell(xls.CellIndex.indexByColumnRow(
        columnIndex: i,
        rowIndex: 2,
      )).value = xls.TextCellValue(header.split(',')[i]);
    }
    final values = row.split(',');
    for (var i = 0; i < values.length; i++) {
      final value = values[i];
      final numericColumns = {7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24};
      final cellValue = numericColumns.contains(i)
          ? xls.IntCellValue(int.parse(value))
          : xls.TextCellValue(value);
      sheet.cell(xls.CellIndex.indexByColumnRow(
        columnIndex: i,
        rowIndex: 3,
      )).value = cellValue;
    }
    final encoded = workbook.save();
    expect(encoded, isNotNull);
    final result = await NextCargoTariffService.preview(
      'sample.xlsx',
      Uint8List.fromList(encoded!),
    );
    expect(result.rowCount, 1);
    expect(result.sampleDestinations.single, 'ABIANSEMAL, ABIANSEMAL, BADUNG, BALI');
  });

  test('uses exact CSV service minimum when calculating billable weight', () {
    expect(NextCargoTariffService.billableWeight(5, 10), 10);
    expect(NextCargoTariffService.billableWeight(20, 20), 20);
    expect(NextCargoTariffService.billableWeight(20, 59), 59);
    expect(NextCargoTariffService.billableWeight(160, 150), 160);
  });

  test('rejects origin other than MALANG KOTA', () async {
    expect(
      () => NextCargoTariffService.preview('sample.csv', bytes('$header\nJAKARTA,BALI,BADUNG,ABIANSEMAL,ABIANSEMAL,DENPASAR AGEN,EKSPEDISI LAIN,6,0,25,4700,200,4500,500,4250,1000,4000,3400,705000,945900,1175000,1903500,2350000,3231250,293750')),
      throwsFormatException,
    );
  });

  test('merges identical duplicate destination aliases', () async {
    final result = await NextCargoTariffService.preview(
      'sample.csv',
      bytes('$header\n$row\n$row'),
    );
    expect(result.rowCount, 1);
  });

  test('rejects duplicate destination when tariff values conflict', () async {
    const conflictingRow = 'MALANG KOTA,BALI,BADUNG,ABIANSEMAL,ABIANSEMAL,DENPASAR AGEN,EKSPEDISI LAIN,6,0,25,9999,200,4500,500,4250,1000,4000,3400,705000,945900,1175000,1903500,2350000,3231250,293750';
    await expectLater(
      NextCargoTariffService.preview(
        'sample.csv',
        bytes('$header\n$row\n$conflictingRow'),
      ),
      throwsFormatException,
    );
  });

  test('rejects a generic four-column fare CSV', () async {
    expect(
      () => NextCargoTariffService.preview('sample.csv', bytes('asal,tujuan,layanan,ongkir\nMALANG,SURABAYA,REG,15000')),
      throwsFormatException,
    );
  });

  group('normalisasi dan validasi impor', () {
    test('membaca CSV titik koma dan akhir baris CRLF', () async {
      final semicolon = '$header\r\n$row'.replaceAll(',', ';');
      final parsed = await NextCargoTariffService.parse('id.csv', bytes(semicolon));
      expect(parsed.rowCount, 1);
      expect(parsed.records.single['tarif_reg'], '4700');
    });

    test('angka berformat ribuan dinormalisasi saat impor', () async {
      final formatted = row.replaceFirst(',4700,', ',"4.700",').replaceFirst(',25,', ',25.0,');
      final parsed = await NextCargoTariffService.parse('a.csv', bytes('$header\n$formatted'));
      expect(parsed.records.single['tarif_reg'], '4700');
      expect(parsed.records.single['min_reg'], '25');
    });

    test('nilai yang sama dengan format berbeda bukan konflik', () async {
      final alt = row.replaceFirst(',4700,', ',4700.0,');
      final result = await NextCargoTariffService.preview('a.csv', bytes('$header\n$row\n$alt'));
      expect(result.rowCount, 1);
    });

    test('menolak sel rumus Excel pada kolom tarif', () async {
      final formula = row.replaceFirst(',4700,', ',=B2*2,');
      await expectLater(
        NextCargoTariffService.preview('a.csv', bytes('$header\n$formula')),
        throwsFormatException,
      );
    });

    test('menolak kolom angka yang berisi teks atau rentang', () async {
      final text = row.replaceFirst(',4700,', ',10-20,');
      await expectLater(
        NextCargoTariffService.preview('a.csv', bytes('$header\n$text')),
        throwsFormatException,
      );
    });
  });
}
