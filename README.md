# FakeGPS — sistem fake GPS untuk testing app iOS sendiri

Toolkit untuk menguji fitur berbasis lokasi di **Simulator dan iPhone fisik** tanpa jailbreak:

| Cara                                   | Butuh Mac tersambung? | Kapan dipakai                                          |
|----------------------------------------|-----------------------|--------------------------------------------------------|
| `MockLocationManager` + layar debug    | Tidak                 | Uji manual di jalan/kantor, demo, QA tanpa Mac         |
| GPX + Xcode *Simulate Location*        | Ya (kabel/Wi-Fi debug)| Uji jalur CoreLocation asli, termasuk `CLLocationManager` pihak ketiga (Maps SDK, dll.) |
| Unit test dengan `MockLocationManager` | Tidak                 | Logic geofence, jarak, izin: cepat & deterministik     |
| UI test (`-UITest_MockLocation` / `XCUIDevice.location`) | –   | Otomasi end-to-end                                     |

Target: iOS 16+, Swift 5, SwiftUI, MapKit, CoreLocation, XCTest.

---

## Struktur

```
project.yml                         # Definisi project (XcodeGen) -> FakeGPS.xcodeproj
Config/Signing.xcconfig             # Signing; override lokal di Config/Local.xcconfig
GPX/                                # File GPX untuk Xcode (TIDAK masuk bundle app)
  Office.gpx  Home.gpx  CommuteRoute.gpx
FakeGPS/
  App/
    FakeGPSApp.swift                # Entry point + injeksi provider
    AppEnvironment.swift            # Composition root + parsing launch argument
  Location/
    LocationProviding.swift         # Protocol + delegate
    RealLocationManager.swift       # CLLocationManager asli (satu-satunya di Release)
    CoordinateParsing.swift
    Mock/                           # #if DEBUG
      MockLocationManager.swift     # Koordinat manual + replay rute
      RouteInterpolator.swift       # Waypoint -> titik per interval (speed, course)
      SwitchableLocationProvider.swift  # Toggle GPS asli <-> palsu saat runtime
    GPX/GPXGenerator.swift          # #if DEBUG — generator GPX 1.1
  Debug/                            # #if DEBUG — layar kontrol Fake GPS
    FakeGPSDebugView.swift  FakeGPSDebugViewModel.swift
    MapPickerView.swift     LocationPreset.swift
  Features/Tracking/                # Contoh fitur yang memakai lokasi
    TrackingViewModel.swift  TrackingView.swift  Geofence.swift
FakeGPSTests/                       # Unit test (XCTest)
FakeGPSUITests/                     # UI test
.github/workflows/build-unsigned-ipa.yml
```

### Kenapa kode mock tidak ikut ke production

1. Semua file di `Location/Mock`, `Location/GPX`, dan `Debug/` dibungkus `#if DEBUG … #endif`.
   Konfigurasi Release tidak mendefinisikan `DEBUG`, jadi file itu kosong saat dikompilasi.
2. `AppEnvironment` (composition root) memilih provider:
   - **Release** → `RealLocationManager()`.
   - **Debug** → `SwitchableLocationProvider(real:mock:)`, sumber ditentukan launch argument atau pilihan terakhir di layar debug.
3. Workflow CI punya langkah yang **gagal kalau simbol mock ditemukan di binary Release**.

Untuk memakai di app kamu sendiri: salin folder `Location/` + `Debug/`, lalu buat ViewModel/Service kamu
menerima `any LocationProviding` lewat initializer (lihat `TrackingViewModel`).

```swift
// Production code hanya kenal protocol:
final class CheckInService {
    private let location: any LocationProviding
    init(location: any LocationProviding) { self.location = location }
}
```

---

## Setup awal (di Mac)

Kebutuhan: macOS + Xcode 15 atau lebih baru, [Homebrew](https://brew.sh).

```bash
brew install xcodegen
cd fake-gps
xcodegen generate          # menghasilkan FakeGPS.xcodeproj
open FakeGPS.xcodeproj
```

> Jalankan ulang `xcodegen generate` setiap kali menambah/menghapus file. Setting scheme
> (Allow Location Simulation, default GPX, launch argument) sudah didefinisikan di `project.yml`.

### Signing untuk iPhone fisik

Buat `Config/Local.xcconfig` (sudah di-ignore git):

```
DEVELOPMENT_TEAM = ABCDE12345
FAKEGPS_APP_BUNDLE_ID = com.namakamu.fakegps.app
```

Team ID ada di Xcode › Settings › Accounts › (Apple ID) › Team, atau di developer.apple.com › Membership.
Apple ID gratis (Personal Team) cukup; app-nya berlaku 7 hari lalu perlu di-run ulang.

---

## Run di Simulator

1. Pilih scheme **FakeGPS**, lalu destination iPhone simulator mana saja. Tekan ⌘R.
2. Tap **Mulai tracking**. Karena `Office.gpx` jadi default location, posisi langsung di kantor.
3. Tap ikon 🔍📍 (kanan atas) untuk membuka layar **Fake GPS**.

Opsi lokasi khusus Simulator:
- Menu Simulator: **Features › Location** › Custom Location… / City Run / Freeway Drive.
- Terminal (Xcode 14+):
  ```bash
  xcrun simctl location booted set -6.1754,106.8272
  xcrun simctl location booted start --speed=15 -6.2615,106.7810 -6.1300,106.7400 -6.131336,106.644936
  xcrun simctl location booted clear
  ```
- Reset izin lokasi: `xcrun simctl privacy booted reset location com.example.fakegps.app`

## Run di iPhone fisik

1. Sambungkan iPhone ke Mac dengan kabel, lalu tap **Trust**.
2. iOS 16+: aktifkan **Settings › Privacy & Security › Developer Mode**, lalu restart iPhone.
3. Di Xcode pilih iPhone kamu sebagai destination, tekan ⌘R.
4. Pertama kali: **Settings › General › VPN & Device Management** › trust sertifikat developer.
5. Setelah itu ada dua cara memalsukan lokasi:
   - **Tanpa Mac**: buka layar Fake GPS di app, lalu pilih *Fake GPS*. App tetap bisa dipakai setelah kabel dicabut.
     Mock hanya memengaruhi app ini; Maps & app lain tetap memakai GPS asli.
   - **Dengan Mac (GPX)**: lihat bagian berikut. Ini memalsukan lokasi di level sistem selama sesi debug.

---

## Panduan Xcode: Location Simulation dengan GPX

### 1. Aktifkan "Allow Location Simulation" di scheme

**Product › Scheme › Edit Scheme…** (⌘<) › **Run** (panel kiri) › tab **Options**:

- ☑ **Allow Location Simulation**
- **Default Location**: pilih `Office` (atau `None` kalau tidak mau lokasi otomatis saat run)

> Di project ini sudah diatur via `project.yml` (`simulateLocation.allow` & `defaultLocation`).
> Kalau Default Location terlihat kosong setelah generate, pilih ulang manual dari dropdown.
> Dropdown hanya menampilkan file `.gpx` yang sudah jadi bagian project.

### 2. Menambahkan file GPX ke project

**Cara A — buat baru di Xcode:** File › New › File… (⌘N) › cari **GPX File** › beri nama.
Di dialog simpan, **hilangkan centang target FakeGPS**. File GPX tidak perlu ikut ke bundle app.

**Cara B — pakai generator:**
- Dari app: layar Fake GPS › atur waypoint › **Buat file GPX** › **Bagikan** › AirDrop ke Mac.
- Salin file ke folder `GPX/` lalu jalankan `xcodegen generate` (atau drag ke navigator Xcode
  dengan *Add to targets* tidak dicentang).

Format yang dipahami Xcode:

```xml
<!-- Titik statis -->
<wpt lat="-6.1313360" lon="106.6449360"><name>Kantor (GSO)</name></wpt>

<!-- Rute: Xcode bergerak antar <wpt> mengikuti selisih <time> -->
<wpt lat="-6.2615" lon="106.7810"><time>2026-01-01T07:00:00Z</time></wpt>
<wpt lat="-6.131336" lon="106.644936"><time>2026-01-01T07:32:13Z</time></wpt>
```

`GPXGenerator.routeDocument(...)` menghitung `<time>` dari jarak ÷ kecepatan dan juga menulis `<trk>`
(diabaikan Xcode, tapi berguna untuk Google Earth/Strava). Jadi file hasil generator valid GPX 1.1
dan tetap bisa dipakai di Xcode.

### 3. Menjadikan GPX sebagai default saat run di device

Edit Scheme › Run › Options › **Default Location** › pilih file GPX (mis. `CommuteRoute`).
Setiap kali ⌘R ke iPhone, lokasi otomatis mengikuti file tersebut.

### 4. Live-switch lokasi saat app berjalan

Saat app sedang di-debug (iPhone tersambung, ikon ■ Stop aktif):

- Menu **Debug › Simulate Location** › pilih `Office`, `Home`, `CommuteRoute`, atau kota bawaan Apple.
- Atau klik ikon **panah lokasi** (➤) di debug bar (panel bawah Xcode) › pilih lokasi.
- **Add GPX File to Workspace…** di menu yang sama untuk memuat GPX tanpa memasukkannya ke project.
- Pilih **Don't Simulate Location** untuk kembali ke GPS asli.

Catatan device fisik:
- Pastikan di layar Fake GPS app sumber diset ke **GPS asli**. Lokasi GPX masuk lewat `CLLocationManager`,
  sedangkan mode Fake GPS mengabaikannya.
- Lokasi simulasi berlaku di seluruh sistem iPhone (Maps juga ikut) **selama sesi debug**.
  Kadang lokasi palsu tertinggal setelah stop. Solusinya: pilih *Don't Simulate Location* sebelum stop,
  atau matikan-nyalakan Location Services / restart iPhone.

---

## Launch argument (build Debug)

Atur di **Edit Scheme › Run › Arguments › Arguments Passed On Launch** (sudah ada entri yang tinggal dicentang)
atau lewat `XCUIApplication.launchArguments`.

| Argument                                 | Efek                                            |
|------------------------------------------|-------------------------------------------------|
| `-UITest_MockLocation`                   | Paksa fake GPS (tidak menyimpan pilihan)        |
| `-UITest_RealLocation`                   | Paksa GPS asli (untuk GPX / `XCUIDevice`)       |
| `-MockLocation_Coordinate -6.1754,106.8272` | Koordinat awal fake GPS                      |
| `-MockLocation_Route "lat,lon;lat,lon;…"`| Jalankan rute saat tracking dimulai             |
| `-MockLocation_SpeedKmh 40`              | Kecepatan rute                                  |
| `-MockLocation_Interval 1`               | Interval update (detik)                         |

Tanpa argument, sumber lokasi mengikuti pilihan terakhir di layar debug (default: GPS asli).

---

## Layar Fake GPS (Debug)

- **Sumber**: toggle *GPS asli* ↔ *Fake GPS*, berlaku langsung tanpa restart.
- **Input manual**: lat/long (koma atau titik sebagai desimal), lalu **Set lokasi**.
- **Peta**: mode *Pilih titik* (tap, lalu *Pakai titik yang dipilih*) atau *Tambah waypoint* (setiap tap menambah waypoint).
  Pin merah = lokasi palsu aktif, bergerak saat simulasi rute.
- **Preset**: Kantor, Rumah, lokasi uji. Tap untuk pindah, geser ke kiri untuk menambahkannya sebagai waypoint.
  Ubah daftar di `LocationPreset.swift`.
- **Simulasi rute**: daftar waypoint (bisa hapus/urutkan lewat *Edit*), kecepatan 1–150 km/j,
  interval 0.5–10 detik, loop, estimasi jarak & waktu, **Mulai/Stop simulasi** + progress.
  Lokasi yang dikirim berisi `speed` dan `course` yang realistis.
- **GPX**: ekspor waypoint/titik terpilih ke `.gpx` lalu bagikan.

---

## Testing

### Unit test

```bash
xcodebuild test -project FakeGPS.xcodeproj -scheme FakeGPS \
  -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FakeGPSTests
```

Pola dasar (lihat `FakeGPSTests/TrackingViewModelTests.swift`):

```swift
@MainActor
func test_routeLeavingOffice_emitsEnterThenExit() {
    let mock = MockLocationManager()
    let sut = TrackingViewModel(locationProvider: mock)
    sut.startTracking()

    mock.startRoute(waypoints: [office, north1km], speed: 20, updateInterval: 5, autoAdvance: false)
    while mock.advanceRoute() != nil {}          // deterministik, tanpa Timer

    XCTAssertEqual(sut.geofenceEvents, [.entered, .exited])
}
```

Fitur `MockLocationManager` untuk test: `setLocation`, `send(CLLocation)` (akurasi buruk, dll.),
`simulateAuthorizationChange(to:)`, `simulateError(_:)`, `startRoute(... autoAdvance: false)` + `advanceRoute()`.

### UI test

`FakeGPSUITests/LocationUITests.swift` berisi:

1. **Mock via launch argument**: stabil, tanpa dialog izin.
   ```swift
   app.launchArguments = ["-UITest_MockLocation", "-MockLocation_Coordinate", "-6.131336,106.644936"]
   ```
2. **`XCUIDevice.shared.location`** (iOS 16.4+, Xcode 14.3+): mengubah lokasi sistem, jadi app memakai
   `RealLocationManager` (`-UITest_RealLocation`). Test ini memakai `resetAuthorizationStatus(for: .location)`
   dan menekan tombol izin di alert SpringBoard.
   ```swift
   XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: -6.131336, longitude: 106.644936))
   ```
   Paling andal di Simulator. Di device fisik, dukungannya bergantung versi Xcode/iOS; kalau gagal,
   pakai pendekatan (1).
3. **Mengendalikan layar debug** lewat accessibility identifier `fakeGPS.*`.

---

## GitHub Actions: unsigned IPA

`.github/workflows/build-unsigned-ipa.yml`:

- **Trigger**: push ke `main`, PR, atau manual (*Actions › Build unsigned IPA › Run workflow*, pilih Debug/Release).
- **Job `test`**: `xcodegen generate` › pilih simulator iPhone yang tersedia › unit test (opsional UI test).
- **Job `build-ipa`**: `xcodebuild archive` dengan `CODE_SIGNING_ALLOWED=NO` › `Payload/FakeGPS.app` › zip jadi `.ipa`.
  Untuk Release, ada verifikasi bahwa binary bebas simbol mock.
- **Artifact**: `FakeGPS-<versi>-<config>-<sha>-unsigned.ipa` + dSYM (disimpan 14 hari).

**Penting:** IPA tanpa signature **tidak bisa langsung di-install** ke iPhone. Harus di-sign ulang dulu, misalnya:
- Sideloadly / AltStore dengan Apple ID kamu (paling mudah untuk personal testing), atau
- `codesign` manual dengan sertifikat development + provisioning profile yang memuat UDID iPhone kamu.

Untuk iterasi harian di device sendiri, run langsung dari Xcode (⌘R) tetap paling cepat.
IPA dari CI berguna sebagai build artefak yang bisa diulang, dan untuk memastikan Release tetap bersih.

Catatan biaya: runner macOS di repo private memakai kuota menit dengan pengali 10×.
Hapus job matrix `Debug` kalau tidak perlu.

---

## Troubleshooting

| Gejala                                             | Solusi                                                                 |
|----------------------------------------------------|------------------------------------------------------------------------|
| Lokasi GPX tidak berubah di app                    | Layar Fake GPS › Sumber = *GPS asli*; cek *Allow Location Simulation*  |
| Menu Debug › Simulate Location abu-abu             | App belum di-run dari Xcode / sesi debug belum aktif                   |
| Default Location kosong di scheme                  | Pilih ulang manual; pastikan `.gpx` ada di project navigator            |
| iPhone tetap di lokasi palsu setelah debug         | *Don't Simulate Location*, toggle Location Services, atau restart      |
| Build device gagal "requires a development team"   | Isi `Config/Local.xcconfig`, lalu `xcodegen generate`                  |
| UI test izin lokasi macet                          | Label tombol berbeda bahasa: helper memakai fallback index tombol ke-2 |
