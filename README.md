# Cargo Voice Agent Lite (100% Offline)

Asisten suara (Speech-to-Text & Text-to-Speech) untuk menghitung ongkir **NEXT Cargo dari MALANG KOTA**. Berjalan 100% offline di perangkat, tanpa koneksi internet maupun API key.

## Fitur
- Tanya lewat suara (bahasa Indonesia), misalnya "ongkir ke Abiansemal Badung 20 kilo reguler". Jawaban tampil sebagai teks dan dibacakan.
- Perhitungan per layanan (Reguler, SP1, SP2, SP3) dengan berat tagihan mengikuti minimum layanan tujuan.
- Kelola data tarif langsung di aplikasi tanpa build APK ulang.
- Impor JSON, CSV (pemisah koma, titik koma, atau tab), dan Excel `.xlsx`, dengan pratinjau dan validasi sebelum diterapkan. File dibaca di isolate terpisah sehingga UI tidak membeku.
- Kolom angka dinormalisasi saat impor ("4.700", "4,700", "4700.0" menjadi 4700); teks non-angka, rentang, dan sel rumus Excel ditolak dengan nomor baris.
- Mode gabung/perbarui atau ganti semua, backup otomatis (satu level), dan pemulihan backup. Ekspor JSON/CSV dan template CSV belum tersedia.
- Data tarif disimpan lokal (SQLite) agar tetap tersedia offline.

## Persiapan di perangkat (wajib agar benar-benar offline)
1. Unduh paket bahasa **Indonesia offline** di pengaturan suara Google perangkat.
2. Pasang data suara **TTS bahasa Indonesia**.

Tanpa paket tersebut, aplikasi akan menampilkan pesan error.

## Build APK
**Lewat GitHub Actions:** push ke branch `main` (atau jalankan manual di tab Actions), lalu unduh APK dari halaman **Releases** (tag `build-<nomor>-<percobaan>`).

**Lokal:**
```bash
flutter create --platforms=android --org com.example --project-name cargo_voice_agent_offline .
rm -f android/app/build.gradle.kts
flutter pub get
flutter build apk --release
```

## Struktur kode
- `lib/answer_engine.dart`: mesin jawaban dan penyusun jawaban tarif (Dart murni, mudah diuji).
- `lib/tariff_utils.dart`: parsing/format angka tarif.
- `lib/next_cargo_tariff_service.dart`: parsing file, validasi, dan penyimpanan SQLite.
- `lib/fare_manager_page.dart`, `lib/main.dart`: UI.

## Catatan
- Package name masih `com.example.cargo_voice_agent_offline` dan rilis ditandatangani dengan kunci debug. Ganti keduanya sebelum rilis ke Play Store.
- Folder `ios/` hanya berisi `Info.plist`. Jalankan `flutter create --platforms=ios .` bila ingin membangun untuk iOS.

## Kompatibilitas pembaruan Android

Build ini mempertahankan `applicationId` lama `com.example.lrt_voice_agent_offline` agar identitas paket tetap sama dengan aplikasi LRT yang sudah terpasang. Nama proyek, label aplikasi, dan namespace Android tetap menggunakan Cargo Voice Agent. `versionCode` dinaikkan menjadi 54.

**Penting tentang tanda tangan APK:** agar Android mengizinkan pembaruan tanpa uninstall, APK baru wajib ditandatangani dengan sertifikat/keystore yang sama persis dengan APK yang terpasang. Workflow debug signing di GitHub Actions tidak menjamin kunci yang sama antar-run. Jangan memasang APK hasil build baru sebagai pembaruan sebelum sidik jari sertifikatnya cocok dengan APK terpasang. Jangan uninstall aplikasi karena dapat menghilangkan database lokal.
