# CF23 Booth Map

Aplikasi web untuk melihat peta booth creator di acara Comifuro 23 (CF23).

## Fitur

- 🗺️ **Peta Interaktif** - Lihat seluruh layout booth acara CF23
- 🔍 **Pencarian Creator** - Cari dan temukan booth creator favorit kamu
- 🔗 **Share Link** - Bagikan link langsung ke booth creator tertentu

## Cara Pakai

1. Buka website
2. Geser dan zoom untuk navigasi peta
3. Tap search bar di atas untuk cari creator
4. Pilih creator untuk lihat lokasi booth mereka
5. Tap booth di peta untuk lihat detail creator

## Build (Khusus buat developer)

App ini dibuat menggunakan Flutter.

```bash
# Install dependencies
flutter pub get

# Run di browser
flutter run -d chrome

# Build untuk production
flutter build web --release
```

### Data jarak booth

Rekomendasi lokasi memakai jarak jalan kaki yang sudah dihitung dari
`data/map.json`, bukan menghitung BFS di perangkat pengguna. Setelah layout peta
berubah, buat ulang datanya dan commit kedua file tersebut:

```bash
python tools/generate_booth_proximity.py
git add data/map.json data/booth-proximity.json
```

Untuk memastikan data yang di-commit masih sesuai dengan peta:

```bash
python tools/generate_booth_proximity.py --check
```

Benchmark untuk inti kalkulasi rekomendasi (tanpa waktu render UI) dapat
dijalankan dengan:

```bash
dart run tools/benchmark_recommendation.dart
```

## Kontribusi (Khusus buat developer)

App ini merupakan app eksperimentasi saya, artinya saya bakal ngutak-ngatik terus app ini. Jika ada saran dan ingin contribute sesuatu, mungkin submit Issues dahulu. Kalau sudah oke, silakan submit PR. Mohon maaf atas keterbatasannya 🙇‍♂️


---

See you at CF23 💖

