Here's the complete **KeyLink iOS project folder structure**, organized the way a real SwiftUI app should be laid out:

```
KeyLink/
├── KeyLink.xcodeproj/
│   └── (Xcode project files)
│
├── KeyLink/
│   ├── KeyLinkApp.swift                    # @main entry point
│   ├── Info.plist                          # BLE permissions, file sharing
│   │
│   ├── Models/
│   │   └── Card.swift                      # SwiftData @Model
│   │
│   ├── BLE/
│   │   ├── BLEManager.swift                # CoreBluetooth central
│   │   └── BLEModels.swift                 # Codable JSON protocol structs
│   │
│   ├── Cards/
│   │   ├── CardLibraryView.swift           # Main list of saved cards
│   │   ├── CardRow.swift                   # List row component
│   │   ├── CardImportView.swift            # Import sheet (file + clipboard)
│   │   └── CardDetailView.swift            # (optional) Edit card name
│   │
│   ├── Emulation/
│   │   ├── EmulationView.swift             # Active emulation screen
│   │   └── EmulationTimer.swift            # Countdown ring component
│   │
│   ├── Utils/
│   │   ├── CardImportManager.swift         # JSON parser + validation
│   │   ├── HexHelpers.swift                # UInt8 <-> Hex conversions
│   │   └── DocumentPicker.swift            # UIDocumentPicker wrapper
│   │
│   ├── Assets.xcassets/
│   │   └── AppIcon.appiconset/
│   │       └── (icon images)
│   │
│   └── Preview Content/
│       └── Preview Assets.xcassets/
│
├── KeyLinkTests/
│   └── CardImportManagerTests.swift        # Unit tests for JSON parsing
│
└── KeyLinkUITests/
    └── KeyLinkUITests.swift
```

---

## File-by-File Breakdown

| File | Lines | Purpose |
|---|---|---|
| `KeyLinkApp.swift` | ~15 | Bootstraps SwiftUI + SwiftData container |
| `Card.swift` | ~50 | Data model with `@Model`, computed properties |
| `BLEManager.swift` | ~150 | `CBCentralManagerDelegate`, GATT read/write/notify |
| `BLEModels.swift` | ~40 | `Codable` structs for bridge JSON protocol |
| `CardLibraryView.swift` | ~80 | Root view, `@Query` for card list, delete, navigation |
| `CardRow.swift` | ~60 | Reusable row with UID, full/UID-only badge |
| `CardImportView.swift` | ~150 | Document picker, clipboard paste, preview, save |
| `EmulationView.swift` | ~140 | Card visualization, timer, emulate/stop button |
| `CardImportManager.swift` | ~80 | Parse Proxmark3 JSON, validate UID/sectors |
| `HexHelpers.swift` | ~20 | `String.hexToBytes()`, `[UInt8].toHexString()` |
| `DocumentPicker.swift` | ~40 | `UIViewControllerRepresentable` wrapper |

**Total Swift code: ~825 lines** — a lean, focused codebase.

---

## Grouping in Xcode

In Xcode, organize with **folder references** (yellow folders) like this:

```
KeyLink (blue project icon)
├── Models          ← yellow folder
├── BLE             ← yellow folder  
├── Cards           ← yellow folder
├── Emulation       ← yellow folder
├── Utils           ← yellow folder
├── Assets.xcassets ← default
└── Preview Content ← default
```

This keeps every screen's logic isolated and makes it easy for another developer to jump in and know exactly where to look.

Want me to also write the `HexHelpers.swift` and `CardDetailView.swift` to complete the structure?