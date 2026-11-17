# Mac Gaming Launcher

Ein nativer SwiftUI-Launcher für macOS 27 auf Apple Silicon. Er richtet eine Windows-Umgebung mit Steam ein und startet deine Windows-Spiele per Klick. Das Prinzip entspricht CrossOver und Whisky: Wine übersetzt Windows-Aufrufe, Rosetta 2 den x86-Code, und DXMT, DXVK oder Apples **D3DMetal (Game Porting Toolkit 4)** übersetzen DirectX nach Metal.

> Die Spiele laufen übersetzt, nicht nativ. Titel mit Kernel-Anti-Cheat (Valorant, Fortnite, Call of Duty, viele Battle-Royale-Spiele) funktionieren unter Wine nicht.

## Funktionen

- **Einrichtungsassistent:** Rosetta → Wine-Runtime → Bottle → Steam → Anmeldung.
- **Verwaltete Runtime:**
  - Wine 11 auf CrossOver-Basis mit DXMT und DXVK, aus dem aktiv gepflegten Whisky-Fork [frankea/Whisky](https://github.com/frankea/Whisky).
  - Der Download wird per SHA-256 geprüft, danach installiert der Launcher die Runtime atomar. Updates erkennt er über den Versionskanal.
- **Game Porting Toolkit 3/4:**
  - Du importierst die `.dmg` von Apple, das enthaltene Evaluation-Image oder die `Game Porting Toolkit.app`. Der Launcher bindet D3DMetal dann in die Runtime ein.
  - Mit GPTK 4 auf macOS 27 ist der Metal-4-Pfad aktiv (`D3DM_MTL4`). Das MetalFX-Upscaling für DLSS-Spiele lässt sich einschalten.
- **Steam:** Der Launcher installiert den offiziellen Client still (`SteamSetup.exe /S`). Du meldest dich im Steam-Fenster an, danach erscheinen Konto und Bibliothek automatisch.
  - Der Steam-Client läuft auf DXVK, weil die Chromium-Oberfläche das braucht.
  - Spiele nutzen das Backend des Bottles. Das wird pro Programm über `AppDefaults`-DLL-Overrides in der Registry gesteuert, nicht über `WINEDLLOVERRIDES`.
- **Spielsitzungen:** Der Launcher erkennt den laufenden Spielprozess (nicht nur den Steam-Aufruf), zeigt den Status „Läuft“ an und erfasst die Spielzeit. „Beenden“ beendet das Spiel tatsächlich.
- **CrossOver-Bottles** werden erkannt und mit CrossOver gestartet (`wine --bottle … --cx-app …`).
- **Pro Bottle einstellbar:**
  - Grafik-Backend (Automatisch, D3DMetal, DXMT, DXVK, WineD3D)
  - MSync, AVX über Rosetta, Metal HUD, MetalFX, Retina, Windows-Version
- Controller-Anzeige mit Akkustand; jedes Bottle schreibt ein eigenes Log nach `~/Library/Logs/MacGamingLauncher/`.

## Voraussetzungen

- Apple Silicon, macOS 27 oder neuer, Xcode 27 (Swift 6.4)
- Etwa 3 GB freier Speicher plus Platz für die Spiele

## Bauen und Starten

```bash
./scripts/build_app.sh                 # erzeugt build/MacGamingLauncher.app
open build/MacGamingLauncher.app

swift test                             # Unit-Tests (Swift Testing)
swift run MacGamingLauncher            # Debug-Start
```

## D3DMetal (Game Porting Toolkit 4) einrichten

1. Lade das Game Porting Toolkit auf [developer.apple.com/games/game-porting-toolkit](https://developer.apple.com/games/game-porting-toolkit/) herunter. Dafür reicht ein kostenloses Entwicklerkonto.
2. Öffne im Launcher **Einstellungen → Apple Game Porting Toolkit → GPTK-.dmg importieren …**.
3. Im Bottle steht das Grafik-Backend auf **Automatisch**, damit nutzt es jetzt D3DMetal. Starte Steam einmal neu.

Apple erlaubt keine Weitergabe von D3DMetal. Deshalb liefert der Launcher es nicht mit, sondern du importierst es selbst.

## Nativer Steam-Client für macOS (optional)

Ist zusätzlich der normale Steam-Client für macOS installiert (`/Applications/Steam.app`), zeigt der Launcher auch dessen Bibliothek an. Diese Spiele sind mit „Steam (macOS)“ gekennzeichnet und werden über `steam://rungameid/<id>` an diesen Client übergeben. Die Spielzeit wird trotzdem erfasst. Das betrifft echte Mac-Spiele und, falls [NotProton](https://github.com/NotProtonNot/NotProton) eingerichtet ist, auch Windows-Spiele, die der Mac-Client per Steam Play über CrossOver startet. Der Launcher liest diese Bibliothek nur und verändert den Mac-Client nicht.

## Aufbau

```text
Sources/
├── LauncherCore/          # Plattformlogik, ohne UI, getestet
│   ├── Runtime/           # Runtime-Download und -Installation, D3DMetal-Import, Engine-Erkennung
│   ├── Bottles/           # Bottles erstellen, bottle.json, cxbottle.conf (abschnittsweise)
│   ├── Wine/              # Umgebung, Aufrufe, Grafik-Plan (DLL-Overrides, DXMT/DXVK), .reg-Import
│   ├── Steam/             # Bibliothek/ACF, Konten, Installation und Steuerung des Clients, Spielerkennung
│   ├── Process/           # Prozessstart ohne blockierende Pipes, Prozessliste über sysctl
│   ├── VDF/               # Parser für Valve KeyValues
│   └── Support/           # Pfade, Logging, Spielzeit
└── MacGamingLauncher/     # SwiftUI-App (Main-Actor als Standard)
    ├── Model/AppModel.swift
    └── Views/             # Sidebar, Bibliothek, Detailseite, Einrichtung, Einstellungen
```

## Datenablage

| Was | Wo |
| --- | --- |
| Runtime, Bottles, Spielzeit | `~/Library/Application Support/MacGamingLauncher/` |
| Importiertes D3DMetal | `~/Library/Application Support/MacGamingLauncher/D3DMetal/` |
| Logs | `~/Library/Logs/MacGamingLauncher/` |
| Artwork-Cache | `~/Library/Caches/MacGamingLauncher/` |

## Fehlersuche

- **Das Steam-Fenster bleibt schwarz:** Beende Steam über das Bottle-Menü („Steam beenden“) und öffne es wieder, oder nutze in den Bottle-Einstellungen „Sichern & Steam neu starten“. Hilft das nicht, trage in den Bottle-Einstellungen unter „Zusätzliche Steam-Argumente“ den Wert `-cef-disable-gpu` ein.
- **Das Spiel wird nicht erkannt:** Steam zeigt dann oft ein Fenster an, zum Beispiel für ein Update, eine EULA oder den Cloud-Sync. Bestätige es dort. Weitere Hinweise stehen im Log des Bottles.
- **Ein DirectX-12-Spiel startet nicht:** Importiere D3DMetal (siehe oben).
- **Runtime-Probleme:** Installiere die Runtime unter **Einstellungen → Wine-Runtime** neu.
