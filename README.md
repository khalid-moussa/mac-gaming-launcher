# Mac Gaming Launcher 🎮🍎

Ein nativer, performanter macOS Spiele-Launcher für Apple Silicon (M1 bis M4), der Windows Steam-Spiele über **Apples Game Porting Toolkit (GPTK / Metal 4)** und die bewährte **CrossOver / Wine-CX Architektur** mit nativer macOS SwiftUI-Benutzeroberfläche ausführt.

---

## Highlights & Features

* **100 % Nativ für macOS & Apple Silicon**:
  * Gebaut mit modernem **Swift 6 & SwiftUI** (unter Beachtung der Apple Human Interface Guidelines).
  * Volle Ausnutzung von ARM64, Rosetta 2 und AVX2-Instruktionen.
* **Apple D3DMetal & Metal 4 Translation Layer**:
  * Hardwarebeschleunigte Übersetzung von DirectX 11 & DirectX 12 direkt in Apples Metal API.
  * Umschaltbares **Metal Performance HUD** (Live-FPS, Frame Times, GPU-Auslastung).
  * Optionale Aktivierung von **MetalFX Upscaling**.
* **CrossOver-Engine & MSync Integration**:
  * Nutzt **MSync** (Darwin Mach-Kernel Semaphore) für ruckelfreies Windows Multi-Threading ohne CPU-Overhead.
  * Automatische Erkennung vorhandener CrossOver-Installationen und GPTK-Toolchains.
* **Intelligente Steam-Erkennung (`SteamBridge`)**:
  * Liest `libraryfolders.vdf` und `appmanifest_*.acf` aus Windows-Bottles direkt aus.
  * Lädt automatisch hochauflösende 2x Vertical Posters (600x900) und Landscape Hero Banner vom offiziellen Steam CDN.
  * Startet Spiele direkt per One-Click ohne vorherigen Start der schweren Windows-Steam-Oberfläche.

---

## Projektstruktur

```
MacGamingLauncher/
├── Package.swift                             # Swift Package Manager Konfiguration
├── scripts/
│   └── build_app.sh                          # Erstellt das fertige macOS .app Bundle
├── Sources/
│   └── MacGamingLauncher/
│       ├── App/
│       │   ├── MacGamingLauncherApp.swift    # @main SwiftUI App-Einstiegspunkt
│       │   └── AppDelegate.swift             # macOS Fenster- und Lifecycle-Handling
│       ├── Models/
│       │   ├── SteamGame.swift               # Datenmodell für Steam-Titel (AppID, Pfade, CDN-URLs)
│       │   ├── Bottle.swift                  # Bottle-Konfiguration (MSync, D3DMetal, HUD)
│       │   └── Engine.swift                  # Erkannte GPTK / Wine Runtimes
│       ├── Services/
│       │   ├── VDFParser.swift               # Robuster Valve KeyValues / VDF Parser
│       │   ├── SteamService.swift            # Scannt Bottles & extrahiert Spielemetadaten
│       │   ├── BottleService.swift           # Verwaltet Bottles & cxbottle.conf
│       │   ├── EngineService.swift           # Findet installierte Runtimes (CrossOver, GPTK)
│       │   └── GameRunner.swift              # Startet Wine-Prozesse mit Environment-Variablen
│       ├── State/
│       │   └── AppState.swift                # Zentrales SwiftUI State-Management
│       └── Views/
│           ├── MainView.swift                # NavigationSplitView (Sidebar + Grid + Details)
│           ├── SidebarView.swift             # Bibliotheksfilter & Bottles-Navigation
│           ├── GameGridView.swift            # Animiertes Spielkarten-Grid
│           ├── GameCardView.swift            # 600x900 Poster-Karte mit Hover-Glow
│           └── GameDetailView.swift          # Hero-Banner, Statistiken & Performance-Toggles
└── Tests/
    └── MacGamingLauncherTests/
        └── MacGamingLauncherTests.swift      # Unit-Tests für VDF-Parser & Discovery
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
