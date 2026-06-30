# thread_commissioner — Flutter control app

The phone app for the HVAC Thread-mesh system. It is the **control plane**: it
commissions hardware over **BLE** (standing next to it) and manages the fleet
through the [Cloud Server](https://github.com/maaz-shahid99/param-hvac-server) over **REST/JWT**. The
[web dashboard](https://github.com/maaz-shahid99/param-hvac-web) mirrors the cloud half for desktop; BLE
commissioning is app-only.

## What it does

### BLE — provisioning & commissioning (next to the hardware)
- Discovers the single active-gateway `ESP32C6-Thread-Bridge-XXXX`, PIN-authenticates,
  and changes the PIN (replicated fleet-wide by the firmware).
- **Router setup** (`widgets/router_setup_dialog.dart`): a **Wi-Fi scan** picker
  (`SCAN?` → signal + lock/enterprise icons), **WPA2-Enterprise (PEAP)** with
  username/identity, a **show/hide password** toggle, and the cloud URL + gateway
  API key — sent as one `PROVISION|{…}` payload.
- Commission routers/sensors by QR (`add <EUI> <PSKd>`), fleet OTA, factory reset.

### Cloud — monitoring & configuration (anywhere)
- **Rack Layout** (`screens/rack_layout_page.dart`): build rack→unit→port and
  assign each **DS18B20 probe** (by ROM) to an exhaust. Topology syncs to the
  cloud, which rebuilds its `sensor_map`. The sync is **serialized + debounced**
  so rapid assignments can't race/overwrite each other.
- **Environment & Logs** (`screens/env_data_page.dart`): router/gateway **BME**
  rows + **every sensor probe** (mapped name, or "Probe N"), 60 s poll, two-file
  CSV export (routers + per-probe sensors).
- **Crash Reports** (`screens/crash_reports_page.dart`): firmware crashes (reset
  reason, faulting PC, task) with CSV export.
- Live temps, alerts (view + ACK), thresholds, members, gateway API key, and
  **Settings** (alert granularity + collection interval).

## State (Provider / ChangeNotifier)
`AuthService` (JWT/session) · `BLEService` (`ble_service.dart`, scan + provision +
`WifiNetwork` parsing) · `CloudApi` (`services/cloud_api.dart`, REST) ·
`TopologyService` (rack layout + durable cloud sync) · `DeviceRegistry` (roster +
friendly names). The cloud is the source of truth once signed in; topology is also
cached locally for offline/instant load.

The build tag (`lib/app_version.dart`, `kAppBuild`) is shown in Settings — bump it
each change so you can confirm which build is installed.

## Run
```bash
flutter pub get
flutter run                       # device with BLE for commissioning
flutter analyze                   # static checks
```
On first launch, sign in (or create an org / join by code) and set the **Cloud
URL** to your server, e.g. `http://<server-ip>:8002`.

## Related
- [Bridge](https://github.com/maaz-shahid99/param-hvac-firmware) (ESP32-C3, BLE/Wi-Fi) · [Commissioner](https://github.com/maaz-shahid99/param-hvac-firmware)
  (ESP32-C6, Thread) · [Cloud Server](https://github.com/maaz-shahid99/param-hvac-server) ·
  [web-dashboard](https://github.com/maaz-shahid99/param-hvac-web).
