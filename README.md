# Cargo Voice Agent Lite (100% Offline)

Asisten suara (Speech-to-Text & Text-to-Speech) untuk menghitung ongkir **NEXT Cargo dari MALANG KOTA**. Berjalan 100% offline di perangkat, tanpa koneksi internet maupun API key.

## Fitur
- Tanya lewat suara (bahasa Indonesia), misalnya "ongkir ke Abiansemal Badung 20 kilo reguler". Jawaban tampil sebagai teks dan dibacakan.
- Bisa juga **mengetik** pertanyaan di kolom teks (jawaban hasil ketikan tidak dibacakan).
- **Dialog bertahap:** bila tujuan ambigu, aplikasi menampilkan pilihan yang bisa diketuk. Cukup sebut kelurahan/kecamatan berikutnya ("Sibang"), berat dan layanan dari pertanyaan awal tetap dipakai.
- Perhitungan per layanan (Reguler, SP1, SP2, SP3) dengan berat tagihan mengikuti minimum layanan tujuan.
- Memahami berat angka maupun terbilang bahasa Indonesia, termasuk desimal: “lima belas kilo”, “dua puluh lima koma lima kg”, “seratus kilo”, dan “seribu lima ratus kilo”. Frasa berat dikeluarkan dari pencarian nama tujuan.
- Mengenali akhiran kata perintah seperti “ongkirnya”, “tarifnya”, dan “hitungkan” tanpa mengubah ejaan nama wilayah.
- Pencarian tujuan memiliki fuzzy fallback berbasis jarak edit terhadap kosakata wilayah dari SQLite. Kata pendek dan koreksi ambigu/tidak mirip tidak dipaksakan; kosakata di-cache dan direset setelah impor atau pemulihan backup.
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
**Lewat GitHub Actions:** push ke branch `main` (atau jalankan manual di tab Actions), lalu unduh APK dari halaman **Releases** (tag `cargo-build-<nomor-run>-<percobaan>`).

**Lokal:**
```bash
flutter create --platforms=android --org com.example --project-name cargo_voice_agent_offline .
rm -f android/app/build.gradle.kts
flutter pub get
flutter build apk --release
```

## Struktur kode
- `lib/answer_engine.dart`: mesin jawaban dan penyusun jawaban tarif (Dart murni, mudah diuji).
- `lib/tariff_utils.dart`: parsing/format angka tarif, berat terbilang, token tujuan, dan koreksi fuzzy.
- `lib/next_cargo_tariff_service.dart`: parsing file, validasi, dan penyimpanan SQLite.
- `lib/fare_manager_page.dart`, `lib/main.dart`: UI.

## Catatan
- Namespace Android adalah `com.example.cargo_voice_agent_offline`, sedangkan `applicationId` tetap `com.example.lrt_voice_agent_offline` untuk mempertahankan identitas instalasi aplikasi. `versionName` mengikuti `pubspec.yaml`, sedangkan `versionCode` otomatis memakai nomor run GitHub Actions. Rilis Build 115 masih memakai debug key sementara. Untuk pembaruan tanpa uninstall, seluruh rilis harus memakai keystore permanen yang sama. Saat pertama kali berpindah dari APK debug ke APK bertanda tangan permanen, Android akan menolak pembaruan karena tanda tangan berbeda; perpindahan ini memerlukan uninstall sekali dan akan menghapus database lokal. **Ekspor/cadangkan data tarif terlebih dahulu dan pastikan backup dapat dipulihkan sebelum melakukan perpindahan.** Jangan uninstall jika data belum dicadangkan. Keystore lama harus dipakai apa adanya melalui GitHub Secrets; jangan membuat atau mengganti keystore baru.
- Folder `ios/` hanya berisi `Info.plist`. Jalankan `flutter create --platforms=ios .` bila ingin membangun untuk iOS.
