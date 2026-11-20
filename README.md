# LRT Voice Agent Lite (100% Offline)

Asisten virtual berbasis suara (Speech-to-Text & Text-to-Speech) untuk informasi layanan LRT yang berjalan **100% offline** di perangkat tanpa koneksi internet maupun API key.

## Fitur
- Tanya lewat suara (bahasa Indonesia), jawaban tampil sebagai teks dan dibacakan.
- Topik: jam operasional, tarif, pembayaran, transit, rute stasiun.
- Pengenalan suara on-device (`speech_to_text`) dan TTS (`flutter_tts`).

## Persiapan di perangkat (wajib agar benar-benar offline)
1. Unduh paket bahasa **Indonesia offline** di pengaturan suara Google perangkat.
2. Pasang data suara **TTS bahasa Indonesia**.

Tanpa paket tersebut, aplikasi akan menampilkan pesan error.

## Build APK
**Lewat GitHub Actions:** push ke branch `main` (atau jalankan manual di tab Actions), lalu unduh artifact `lrt-voice-agent-apk`.

**Lokal:**
```bash
flutter create --platforms=android --org com.example --project-name lrt_voice_agent_offline .
rm -f android/app/build.gradle.kts
flutter pub get
flutter build apk --release
```

## Catatan
- Package name masih `com.example.lrt_voice_agent_offline` dan rilis ditandatangani dengan kunci debug. Ganti keduanya sebelum rilis ke Play Store.
- Folder `ios/` hanya berisi `Info.plist`. Jalankan `flutter create --platforms=ios .` bila ingin membangun untuk iOS.
- Tarif dan jam operasional pada basis pengetahuan ditulis langsung di `lib/main.dart`; verifikasi dengan sumber resmi sebelum rilis.
