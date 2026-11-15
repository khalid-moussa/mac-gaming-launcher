# Mac Gaming Launcher 🎮🍎

Ein nativer, performanter macOS Spiele-Launcher für Apple Silicon (M1 bis M4), der Windows Steam-Spiele über **Apples Game Porting Toolkit (GPTK 2 & 4 / Metal 4)**, **Whisky** und die bewährte **CrossOver / Wine-CX Architektur** mit nativer macOS SwiftUI-Benutzeroberfläche ausführt.

---

## Highlights & Features

* **100 % Nativ für macOS & Apple Silicon**:
  * Gebaut mit modernem **Swift 6 & SwiftUI** (unter Beachtung der Apple Human Interface Guidelines).
  * Volle Ausnutzung von ARM64, Rosetta 2 und **AVX2-Instruktionen** (`ROSETTA_ADVERTISE_AVX=1`).
* **Apple D3DMetal & Metal 4 Translation Layer**:
  * Hardwarebeschleunigte Übersetzung von DirectX 11 & DirectX 12 direkt in Apples Metal API (inkl. Ray Tracing Translation).
  * Umschaltbares **Metal Performance HUD** (Live-FPS, Frame Times, GPU-Auslastung).
  * Optionale Aktivierung von **MetalFX Upscaling** und **Retina / HiDPI-Modus**.
* **CrossOver-Engine, Whisky & MSync Integration**:
  * Nutzt **MSync** (Darwin Mach-Kernel Semaphore) für ruckelfreies Windows Multi-Threading ohne CPU-Overhead.
  * Automatische Erkennung vorhandener CrossOver-Installationen, Whisky und GPTK-Toolchains (Homebrew Apple Silicon `/opt/homebrew` & Standalone).
* **Intelligente Steam-Erkennung (`SteamBridge`)**:
  * Liest `libraryfolders.vdf` (inkl. beliebiger Laufwerks-Buchstaben wie `D:/`, `E:/`) und `appmanifest_*.acf` aus Windows-Bottles direkt aus.
  * Lädt automatisch hochauflösende 2x Vertical Posters (600x900) und Landscape Hero Banner vom offiziellen Steam CDN.
  * Startet Spiele direkt per One-Click ohne vorherigen Start der schweren Windows-Steam-Oberfläche.
* **Game Controller & Spielzeit-Tracking**:
  * Nativer GameController-Support (DualSense, Xbox, MFi) mit Live-Akkustandsanzeige in der Toolbar.
  * Persistentes Spielzeit-Tracking mit automatischer Sicherung bei App-Beendigung.

---

## Projektstruktur

```
MacGamingLauncher/
├── Package.swift                             # Swift Package Manager Konfiguration
├── scripts/
│   ├── build_app.sh                          # Erstellt das fertige macOS .app Bundle
│   └── generate_icon.swift                   # Generiert das High-Res App-Icon
├── Sources/
│   └── MacGamingLauncher/
│       ├── App/
│       │   ├── MacGamingLauncherApp.swift    # @main SwiftUI App-Einstiegspunkt
│       │   └── AppDelegate.swift             # macOS Fenster- und Lifecycle-Handling (Playtime-Flush)
│       ├── Models/
│       │   ├── SteamGame.swift               # Datenmodell für Steam-Titel (AppID, Pfade, CDN-URLs)
│       │   ├── Bottle.swift                  # Bottle-Konfiguration (MSync, D3DMetal, HUD, Retina)
│       │   └── Engine.swift                  # Erkannte GPTK / Whisky / CrossOver Runtimes
│       ├── Services/
│       │   ├── VDFParser.swift               # Robuster Valve KeyValues / VDF Parser
│       │   ├── SteamService.swift            # Scannt Bottles & extrahiert Spielemetadaten
│       │   ├── BottleService.swift           # Verwaltet Bottles & cxbottle.conf Persistierung
│       │   ├── EngineService.swift           # Findet installierte Runtimes (CrossOver, GPTK 2/4, Whisky)
│       │   ├── GameRunner.swift              # Startet Wine-Prozesse mit GPTK/AVX2 Environment
│       │   ├── PlaytimeTracker.swift         # Erfasst und formatiert Spielzeiten atomar
│       │   └── ControllerService.swift       # GameController Framework Observer & Batteriestatus
│       ├── State/
│       │   └── AppState.swift                # Zentrales SwiftUI State-Management (Background-Discovery)
│       └── Views/
│           ├── MainView.swift                # NavigationSplitView (Sidebar + Grid + Details)
│           ├── SidebarView.swift             # Bibliotheksfilter & Bottles-Navigation
│           ├── GameGridView.swift            # Animiertes Spielkarten-Grid
│           ├── GameCardView.swift            # 600x900 Poster-Karte mit Hover-Glow
│           └── GameDetailView.swift          # Hero-Banner, Statistiken, Retina & Performance-Toggles
└── Tests/
    └── MacGamingLauncherTests/
        └── MacGamingLauncherTests.swift      # Unit-Tests für VDF-Parser, Bottles & Discovery
```

---

## Schnellstart & Build

### 1. Als native App bauen (.app Bundle)
Führe das Build-Skript im Terminal aus:

```bash
./scripts/build_app.sh
```

Das fertige Bundle liegt anschließend unter:
`build/MacGamingLauncher.app`

Öffne die App direkt:
```bash
open build/MacGamingLauncher.app
```

### 2. Für Entwickler (Xcode oder CLI)
* **Unit-Tests ausführen:**
  ```bash
  swift test
  ```
* **Debug-Build ausführen:**
  ```bash
  swift run
  ```
* **In Xcode öffnen:**
  Öffne einfach den gesamten Ordner `AppleGaming` in Xcode.
