import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'next_cargo_tariff_service.dart';

class FareManagerPage extends StatefulWidget {
  const FareManagerPage({super.key});

  @override
  State<FareManagerPage> createState() => _FareManagerPageState();
}

class _FareManagerPageState extends State<FareManagerPage> {
  int count = 0;
  bool _hasBackup = false;
  String? filename;
  ParsedTariff? parsed;
  bool replace = true;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      final values = await Future.wait<Object>([
        NextCargoTariffService.count(),
        NextCargoTariffService.hasBackup(),
      ]);
      if (!mounted) return;
      setState(() {
        count = values[0] as int;
        _hasBackup = values[1] as bool;
      });
    } catch (_) {
      msg('Data tarif belum dapat dibaca. Coba buka kembali halaman ini.', true);
    }
  }

  void msg(String s, [bool error = false]) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s), backgroundColor: error ? Colors.red : Colors.green),
    );
  }

  void clearSelection() {
    filename = null;
    parsed = null;
  }

  Future<void> pick() async {
    try {
      final f = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'json', 'xlsx'],
        withData: true,
      );
      if (f == null) return;
      final file = f.files.single;
      // Hapus pratinjau lama segera agar tombol Terapkan tidak mungkin
      // memakai data dari file sebelumnya.
      if (mounted) {
        setState(() {
          busy = true;
          clearSelection();
        });
      }
      final data = file.bytes;
      if (data == null) throw Exception('File tidak dapat dibaca.');
      // Parsing berjalan di isolate terpisah, jadi spinner tetap berputar.
      final result = await NextCargoTariffService.parse(file.name, data);
      if (mounted) {
        setState(() {
          filename = file.name;
          parsed = result;
        });
      }
    } catch (e) {
      if (mounted) setState(clearSelection);
      msg('File tarif tidak dapat dibaca. Pastikan format dan kolomnya sesuai.', true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> apply() async {
    if (busy) return;
    final data = parsed;
    if (data == null) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(replace ? 'Ganti seluruh tarif?' : 'Gabungkan tarif?'),
        content: Text(replace
            ? 'Data aktif diganti dengan ${data.rowCount} tujuan. Backup otomatis dibuat.'
            : 'Tujuan sama diperbarui dan tujuan lain dipertahankan. Backup otomatis dibuat.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Lanjutkan')),
        ],
      ),
    );
    if (yes != true) return;
    setState(() => busy = true);
    try {
      final n =
          await NextCargoTariffService.importParsed(data, replace: replace);
      await reload();
      if (!mounted) return;
      setState(clearSelection);
      msg('$n baris tersimpan offline.');
    } catch (e) {
      msg('Impor gagal. Data aktif tetap dipertahankan jika proses transaksi dibatalkan.', true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> restore() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Pulihkan backup?'),
        content: const Text(
            'Tarif aktif dikembalikan ke kondisi sebelum impor terakhir.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Pulihkan')),
        ],
      ),
    );
    if (yes != true) return;
    setState(() => busy = true);
    try {
      final ok = await NextCargoTariffService.restore();
      await reload();
      msg(ok ? 'Backup dipulihkan.' : 'Backup belum tersedia.', !ok);
    } catch (e) {
      msg('Pemulihan backup gagal. Data tarif aktif tidak berhasil diubah.', true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = parsed?.preview;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kelola Data Tarif',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFB71C1C), Color(0xFF8E1717)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.storage_rounded, color: Colors.white, size: 25),
                    SizedBox(width: 9),
                    Text('Database tarif offline',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('$count',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 34,
                            height: 1,
                            fontWeight: FontWeight.w900)),
                    const Padding(
                      padding: EdgeInsets.only(left: 8, bottom: 3),
                      child: Text('tujuan tersimpan',
                          style: TextStyle(color: Colors.white70, fontSize: 13)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Tarif asal MALANG KOTA tersimpan di perangkat dan dapat dicari tanpa internet.',
                  style: TextStyle(color: Colors.white, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text('Kelola file tarif',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15)),
                  ),
                  onPressed: busy ? null : pick,
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text('Impor file'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15)),
                  ),
                  onPressed: busy || !_hasBackup ? null : restore,
                  icon: const Icon(Icons.restore_rounded),
                  label: Text(_hasBackup ? 'Pulihkan backup' : 'Backup belum ada'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F3F7),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 19, color: Color(0xFF596579)),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Format: CSV, JSON, atau Excel XLSX. Periksa pratinjau sebelum menerapkan perubahan. Backup otomatis dibuat saat impor.',
                    style: TextStyle(
                        fontSize: 12.5, color: Color(0xFF596579), height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          if (busy) ...[
            const SizedBox(height: 18),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Center(
              child: Text('Sedang memproses data tarif…',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
            ),
          ],
          if (preview != null) ...[
            const SizedBox(height: 22),
            Text('Pratinjau impor',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 9),
            Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.description_outlined,
                            color: Color(0xFFB71C1C)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(filename ?? 'File tarif',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('${preview.rowCount} baris valid',
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900)),
                    const Text('Asal tarif: MALANG KOTA',
                        style: TextStyle(color: Colors.black54, fontSize: 12)),
                    const SizedBox(height: 15),
                    const Text('Cara menerapkan data',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 7),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: true,
                          icon: Icon(Icons.swap_horiz),
                          label: Text('Ganti semua'),
                        ),
                        ButtonSegment(
                          value: false,
                          icon: Icon(Icons.merge),
                          label: Text('Gabungkan'),
                        ),
                      ],
                      selected: {replace},
                      onSelectionChanged:
                          busy ? null : (v) => setState(() => replace = v.first),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      replace
                          ? 'Mengganti seluruh data tarif aktif dengan isi file ini.'
                          : 'Memperbarui tujuan yang sama dan mempertahankan tujuan lain.',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black54, height: 1.35),
                    ),
                    const Divider(height: 24),
                    const Text('Contoh tujuan dalam file',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    ...preview.sampleDestinations.map((s) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          leading: const Icon(Icons.place_outlined, size: 19),
                          title: Text(s, style: const TextStyle(fontSize: 13)),
                        )),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: busy ? null : apply,
                        icon: const Icon(Icons.check_circle_outline),
                        label: Text(replace ? 'Ganti seluruh tarif' : 'Gabungkan tarif'),
                      ),
                    ),
                    Center(
                      child: TextButton(
                        onPressed: busy ? null : () => setState(clearSelection),
                        child: const Text('Batalkan pratinjau'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            leading: const Icon(Icons.help_outline),
            title: const Text('Petunjuk format file',
                style: TextStyle(fontWeight: FontWeight.w700)),
            children: const [
              Padding(
                padding: EdgeInsets.fromLTRB(12, 0, 12, 14),
                child: Text(
                  'Header NEXT Cargo dideteksi otomatis dan seluruh 25 kolom wajib tersedia. CSV mendukung pemisah koma, titik koma, atau tab. Sel rumus Excel ditolak; simpan sebagai nilai terlebih dahulu. Jika salah memilih mode Ganti semua, gunakan Pulihkan backup untuk mengembalikan kondisi sebelum impor terakhir.',
                  style: TextStyle(
                      fontSize: 12.5, height: 1.45, color: Colors.black54),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

}
