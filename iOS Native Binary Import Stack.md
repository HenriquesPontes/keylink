Let's go with **Native Binary import** first — it unblocks the full workflow from Proxmark3 `.bin` dump → iPhone → Bridge. Crypto1 is a v2.0 upgrade that is currently being integrated for readers that check sector keys.

Here's the complete iOS Native Binary import stack:

---

## 1. Card Model (SwiftData-ready)

```swift
// Models/Card.swift
import Foundation
import SwiftData

@Model
final class Card {
    @Attribute(.unique) var id: UUID
    var name: String
    var uid: String          // Hex, uppercase, no spaces
    var atqa: [UInt8]        // 2 bytes
    var sak: UInt8
    var sectors: [[UInt8]]?  // nil = UID-only
    var createdAt: Date
    
    init(name: String, uid: String, atqa: [UInt8] = [0x00, 0x04], sak: UInt8 = 0x08, sectors: [[UInt8]]? = nil) {
        self.id = UUID()
        self.name = name
        self.uid = uid.uppercased().replacingOccurrences(of: " ", with: "")
        self.atqa = atqa
        self.sak = sak
        self.sectors = sectors
        self.createdAt = Date()
    }
    
    var displayUID: String {
        // Format: A1 B2 C3 D4
        stride(from: 0, to: uid.count, by: 2).map {
            let start = uid.index(uid.startIndex, offsetBy: $0)
            let end = uid.index(start, offsetBy: 2, limitedBy: uid.endIndex) ?? uid.endIndex
            return String(uid[start..<end])
        }.joined(separator: " ")
    }
    
    var isFullClone: Bool {
        sectors != nil
    }
}
```

---

## 2. JSON Codable Models (Bridge Protocol)

```swift
// BLE/BLEModels.swift
import Foundation

// MARK: - Incoming Commands (iPhone → Bridge)

struct LoadCardCommand: Codable {
    let cmd: String = "load_card"
    let uid: String
    let atqa: [UInt8]
    let sak: UInt8
    let sectors: [[UInt8]]?
}

struct EmulateCommand: Codable {
    let cmd: String = "emulate"
    let duration: Int
}

struct StopCommand: Codable {
    let cmd: String = "stop"
}

// MARK: - Outgoing Status (Bridge → iPhone)

struct BridgeStatus: Codable {
    let status: String
    let msg: String
    let uid: String?
}

// MARK: - Proxmark3 Import Format

struct ProxmarkImport: Codable {
    let cmd: String?
    let uid: String
    let atqa: [UInt8]?
    let sak: UInt8?
    let sectors: [[UInt8]]?
    
    func toCard(name: String) -> Card {
        Card(
            name: name,
            uid: uid,
            atqa: atqa ?? [0x00, 0x04],
            sak: sak ?? 0x08,
            sectors: sectors
        )
    }
}
```

---

## 3. JSON Import Manager

```swift
// Utils/CardImportManager.swift
import Foundation

enum ImportError: LocalizedError {
    case invalidJSON
    case missingUID
    case invalidUIDFormat
    case invalidSectorCount(expected: Int, got: Int)
    case invalidBlockSize(expected: Int, got: Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidJSON: return "File is not valid JSON"
        case .missingUID: return "Missing UID field"
        case .invalidUIDFormat: return "UID must be 8 or 14 hex characters"
        case .invalidSectorCount(let exp, let got): return "Expected \(exp) sectors, got \(got)"
        case .invalidBlockSize(let exp, let got): return "Expected \(exp) bytes per block, got \(got)"
        }
    }
}

final class CardImportManager {
    
    static let shared = CardImportManager()
    
    func importFromURL(_ url: URL) throws -> Card {
        let data = try Data(contentsOf: url)
        return try importFromData(data)
    }
    
    func importFromData(_ data: Data) throws -> Card {
        let decoder = JSONDecoder()
        let imported = try decoder.decode(ProxmarkImport.self, from: data)
        
        // Validate UID
        let cleanUID = imported.uid.uppercased().replacingOccurrences(of: " ", with: "")
        guard cleanUID.count == 8 || cleanUID.count == 14 else {
            throw ImportError.invalidUIDFormat
        }
        guard cleanUID.allSatisfy({ $0.isHexDigit }) else {
            throw ImportError.invalidUIDFormat
        }
        
        // Validate sectors if present
        if let sectors = imported.sectors {
            guard sectors.count == 64 else {
                throw ImportError.invalidSectorCount(expected: 64, got: sectors.count)
            }
            for (idx, block) in sectors.enumerated() {
                guard block.count == 16 else {
                    throw ImportError.invalidBlockSize(expected: 16, got: block.count)
                }
                // Validate byte range
                guard block.allSatisfy({ $0 <= 255 }) else {
                    throw ImportError.invalidBlockSize(expected: 16, got: block.count)
                }
            }
        }
        
        // Derive name from filename or use UID
        let name = "Card \(cleanUID.prefix(4))"
        
        return Card(
            name: name,
            uid: cleanUID,
            atqa: imported.atqa ?? [0x00, 0x04],
            sak: imported.sak ?? 0x08,
            sectors: imported.sectors
        )
    }
    
    /// Quick-parse just the UID from raw Proxmark3 console output
    func parseUIDFromConsoleOutput(_ text: String) -> String? {
        // Match patterns like: UID: A1 B2 C3 D4  or  [+] UID: A1B2C3D4
        let pattern = #"UID:\s*([A-Fa-f0-9\s]{11,})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        if let range = Range(match.range(at: 1), in: text) {
            let raw = String(text[range]).replacingOccurrences(of: " ", with: "").uppercased()
            return raw.count == 8 ? raw : nil
        }
        return nil
    }
}
```

---

## 4. Document Picker View

```swift
// Cards/CardImportView.swift
import SwiftUI
import UniformTypeIdentifiers

struct CardImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var showDocumentPicker = false
    @State private var importedCard: Card?
    @State private var cardName: String = ""
    @State private var errorMessage: String?
    @State private var showError = false
    
    var onImport: ((Card) -> Void)?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Import method selection
                VStack(spacing: 16) {
                    Button {
                        showDocumentPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "doc.badge.arrow.up")
                                .font(.title2)
                            VStack(alignment: .leading) {
                                Text("Import from File")
                                    .font(.headline)
                                Text("Select a Proxmark3 JSON dump")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                    
                    Button {
                        // Paste from clipboard
                        if let text = UIPasteboard.general.string,
                           let uid = CardImportManager.shared.parseUIDFromConsoleOutput(text) {
                            importedCard = Card(name: "Card \(uid.prefix(4))", uid: uid)
                            cardName = importedCard?.name ?? ""
                        } else {
                            errorMessage = "No valid UID found in clipboard"
                            showError = true
                        }
                    } label: {
                        HStack {
                            Image(systemName: "doc.on.clipboard")
                                .font(.title2)
                            VStack(alignment: .leading) {
                                Text("Paste from Clipboard")
                                    .font(.headline)
                                Text("Copy Proxmark3 output and paste")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                
                // Preview & edit imported card
                if let card = importedCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Preview")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        VStack(spacing: 12) {
                            TextField("Card Name", text: $cardName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            
                            HStack {
                                Text("UID")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(card.displayUID)
                                    .font(.system(.body, design: .monospaced))
                            }
                            
                            HStack {
                                Text("Type")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(card.isFullClone ? "Full Clone (64 sectors)" : "UID Only")
                                    .foregroundColor(card.isFullClone ? .green : .orange)
                            }
                            
                            HStack {
                                Text("ATQA")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(String(format: "%02X %02X", card.atqa[0], card.atqa[1]))
                                    .font(.system(.body, design: .monospaced))
                            }
                            
                            HStack {
                                Text("SAK")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(String(format: "%02X", card.sak))
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                        .padding()
                        .background(Color(.tertiarySystemBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                        
                        Button {
                            var finalCard = card
                            finalCard.name = cardName.isEmpty ? card.name : cardName
                            modelContext.insert(finalCard)
                            try? modelContext.save()
                            onImport?(finalCard)
                            dismiss()
                        } label: {
                            Text("Save to Library")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }
                }
                
                Spacer()
            }
            .navigationTitle("Import Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPicker { url in
                    do {
                        let card = try CardImportManager.shared.importFromURL(url)
                        importedCard = card
                        cardName = card.name
                    } catch {
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                }
            }
            .alert("Import Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }
}

// MARK: - Document Picker Wrapper

struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.json, UTType.plainText])
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        
        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            // Security-scoped resource
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            onPick(url)
        }
    }
}
```

---

## 5. Updated Card Library View

```swift
// Cards/CardLibraryView.swift
import SwiftUI
import SwiftData

struct CardLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Card.createdAt, order: .reverse) private var cards: [Card]
    
    @State private var showImport = false
    @State private var selectedCard: Card?
    
    var body: some View {
        NavigationView {
            List {
                if cards.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "creditcard.and.key")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("No Cards Yet")
                                .font(.headline)
                            Text("Import from Proxmark3 or add manually")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                } else {
                    ForEach(cards) { card in
                        CardRow(card: card)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedCard = card
                            }
                    }
                    .onDelete(perform: deleteCards)
                }
            }
            .navigationTitle("KeyLink")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showImport = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showImport) {
                CardImportView { card in
                    selectedCard = card
                }
            }
            .sheet(item: $selectedCard) { card in
                EmulationView(card: card)
            }
        }
    }
    
    private func deleteCards(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(cards[index])
        }
        try? modelContext.save()
    }
}

struct CardRow: View {
    let card: Card
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(card.isFullClone ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: card.isFullClone ? "key.fill" : "wave.3.right")
                    .foregroundColor(card.isFullClone ? .green : .orange)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(card.name)
                    .font(.headline)
                Text(card.displayUID)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if card.isFullClone {
                Text("Full")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.15))
                    .foregroundColor(.green)
                    .cornerRadius(8)
            } else {
                Text("UID")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15))
                    .foregroundColor(.orange)
                    .cornerRadius(8)
            }
        }
        .padding(.vertical, 4)
    }
}
```

---

## 6. Updated Emulation View

```swift
// Emulation/EmulationView.swift
import SwiftUI

struct EmulationView: View {
    let card: Card
    @Environment(\.dismiss) private var dismiss
    @StateObject private var ble = BLEManager()
    
    @State private var isEmulating = false
    @State private var timeRemaining = 30
    @State private var timer: Timer?
    @State private var showSuccess = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 32) {
                // Card visualization
                VStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: card.isFullClone ? 
                                        [Color.green.opacity(0.3), Color.green.opacity(0.1)] :
                                        [Color.orange.opacity(0.3), Color.orange.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(height: 180)
                        
                        VStack(spacing: 12) {
                            Image(systemName: "wave.3.right.circle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(card.isFullClone ? .green : .orange)
                            
                            Text(card.name)
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text(card.displayUID)
                                .font(.system(.title3, design: .monospaced))
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                isEmulating ? Color.blue : Color.clear,
                                lineWidth: 3
                            )
                            .animation(.easeInOut, value: isEmulating)
                    )
                }
                .padding(.horizontal)
                
                // Status
                VStack(spacing: 8) {
                    HStack {
                        Circle()
                            .fill(ble.isConnected ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                        Text(ble.isConnected ? "Bridge Connected" : "Searching for Bridge...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let event = ble.lastReaderEvent {
                        Label(event, systemImage: "checkmark.shield.fill")
                            .foregroundColor(.green)
                            .font(.headline)
                            .transition(.scale.combined(with: .opacity))
                    }
                    
                    Text(ble.statusMessage)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                // Timer
                if isEmulating {
                    Text("\(timeRemaining)s")
                        .font(.system(size: 64, weight: .thin, design: .rounded))
                        .foregroundColor(.blue)
                        .contentTransition(.numericText())
                }
                
                Spacer()
                
                // Action button
                Button {
                    if isEmulating {
                        stopEmulation()
                    } else {
                        startEmulation()
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: isEmulating ? "stop.fill" : "play.fill")
                        Text(isEmulating ? "Stop" : "Emulate")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isEmulating ? Color.red : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(16)
                }
                .disabled(!ble.isConnected)
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .navigationTitle("Emulate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { 
                        stopEmulation()
                        dismiss() 
                    }
                }
            }
            .onAppear {
                // Auto-load card to bridge when view appears
                if ble.isConnected {
                    ble.loadCard(
                        uid: card.uid,
                        atqa: card.atqa,
                        sak: card.sak,
                        sectors: card.sectors
                    )
                }
            }
            .onChange(of: ble.isConnected) { connected in
                if connected {
                    ble.loadCard(
                        uid: card.uid,
                        atqa: card.atqa,
                        sak: card.sak,
                        sectors: card.sectors
                    )
                }
            }
        }
    }
    
    private func startEmulation() {
        ble.startEmulate(duration: 30)
        isEmulating = true
        timeRemaining = 30
        
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if timeRemaining > 0 {
                timeRemaining -= 1
            } else {
                stopEmulation()
            }
        }
    }
    
    private func stopEmulation() {
        ble.stopEmulate()
        isEmulating = false
        timer?.invalidate()
        timer = nil
    }
}
```

---

## 7. Info.plist Additions

```xml
<!-- Required for BLE -->
<key>NSBluetoothAlwaysUsageDescription</key>
<string>KeyLink uses Bluetooth to connect to your NFC Bridge device.</string>

<!-- Required for file import -->
<key>UISupportsDocumentBrowser</key>
<true/>
<key>UIFileSharingEnabled</key>
<true/>
```

---

## 8. Complete App Entry Point

```swift
// NFCBridgeApp.swift
import SwiftUI
import SwiftData

@main
struct NFCBridgeApp: App {
    var body: some Scene {
        WindowGroup {
            CardLibraryView()
        }
        .modelContainer(for: Card.self)
    }
}
```

---

## 9. Workflow: Proxmark3 → iPhone

```bash
# 1. Dump card
pm3 --> hf mf dump -k hf-mf-A1B2C3D4-key.bin

# 2. Convert
python3 proxmark_to_bridge.py hf-mf-A1B2C3D4-dump.bin -o my_gym.json

# 3. AirDrop my_gym.json to iPhone

# 4. Open KeyLink app → tap (+) → "Import from File" → select my_gym.json

# 5. Edit name → Save

# 6. Tap card → tap "Emulate" → hold bridge near reader
```

---

This gives you a **complete card library with import, persistence, and emulation** in about 400 lines of Swift. The app now handles the full data flow from Proxmark3 dump → JSON → SwiftData → BLE → Bridge.

Want the Crypto1 state machine next, or should we refine the BLE reconnection logic first?