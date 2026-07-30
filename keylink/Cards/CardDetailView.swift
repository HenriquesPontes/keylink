import SwiftUI

struct CardDetailView: View {
    @Bindable var card: Card
    
    var body: some View {
        Form {
            Section(header: Text("Card Info")) {
                LabeledContent("Name", value: card.name)
                LabeledContent("UID", value: card.displayUID)
                LabeledContent("Type", value: card.type.rawValue)
            }
            
            if card.type == .mifareClassic, let sectors = card.sectors {
                let numSectors = sectors.count / 4
                ForEach(0..<numSectors, id: \.self) { sectorIndex in
                    Section(header: Text("Sector \(sectorIndex)")) {
                        let trailerBlockIndex = (sectorIndex * 4) + 3
                        if trailerBlockIndex < sectors.count {
                            let trailerData = sectors[trailerBlockIndex]
                            if trailerData.count == 16 {
                                let keyA = Array(trailerData[0..<6])
                                let keyB = Array(trailerData[10..<16])
                                
                                NavigationLink {
                                    SectorEditView(card: card, sectorIndex: sectorIndex, trailerBlockIndex: trailerBlockIndex, keyA: keyA, keyB: keyB)
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text("Key A:")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text(keyA.map { String(format: "%02X", $0) }.joined())
                                                .font(.system(.caption, design: .monospaced))
                                        }
                                        HStack {
                                            Text("Key B:")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text(keyB.map { String(format: "%02X", $0) }.joined())
                                                .font(.system(.caption, design: .monospaced))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Card Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SectorEditView: View {
    @Bindable var card: Card
    let sectorIndex: Int
    let trailerBlockIndex: Int
    
    @State private var keyAString: String
    @State private var keyBString: String
    @State private var errorMessage: String?
    
    init(card: Card, sectorIndex: Int, trailerBlockIndex: Int, keyA: [UInt8], keyB: [UInt8]) {
        self.card = card
        self.sectorIndex = sectorIndex
        self.trailerBlockIndex = trailerBlockIndex
        _keyAString = State(initialValue: keyA.map { String(format: "%02X", $0) }.joined())
        _keyBString = State(initialValue: keyB.map { String(format: "%02X", $0) }.joined())
    }
    
    var body: some View {
        Form {
            Section(header: Text("Sector \(sectorIndex) Keys"), footer: Text("Keys must be exactly 12 hex characters (6 bytes).")) {
                TextField("Key A (Hex)", text: $keyAString)
                    .font(.system(.body, design: .monospaced))
                    .autocapitalization(.allCharacters)
                    .disableAutocorrection(true)
                
                TextField("Key B (Hex)", text: $keyBString)
                    .font(.system(.body, design: .monospaced))
                    .autocapitalization(.allCharacters)
                    .disableAutocorrection(true)
            }
            
            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            
            Section {
                Button("Save Keys") {
                    saveKeys()
                }
            }
        }
        .navigationTitle("Edit Sector \(sectorIndex)")
    }
    
    private func saveKeys() {
        guard keyAString.count == 12, keyBString.count == 12 else {
            errorMessage = "Both keys must be exactly 12 characters long."
            return
        }
        
        guard let keyABytes = keyAString.hexBytes, let keyBBytes = keyBString.hexBytes else {
            errorMessage = "Invalid hex format."
            return
        }
        
        guard var sectors = card.sectors else { return }
        
        // Update trailer block (bytes 0-5 for Key A, bytes 10-15 for Key B)
        var newTrailer = sectors[trailerBlockIndex]
        for i in 0..<6 {
            newTrailer[i] = keyABytes[i]
            newTrailer[i + 10] = keyBBytes[i]
        }
        
        sectors[trailerBlockIndex] = newTrailer
        card.sectors = sectors // Trigger SwiftData update
        
        errorMessage = "Saved successfully."
    }
}

extension String {
    var hexBytes: [UInt8]? {
        var bytes = [UInt8]()
        bytes.reserveCapacity(count / 2)
        var index = startIndex
        while index < endIndex {
            let nextIndex = self.index(index, offsetBy: 2)
            if nextIndex > endIndex { return nil }
            let hex = String(self[index..<nextIndex])
            if let byte = UInt8(hex, radix: 16) {
                bytes.append(byte)
            } else {
                return nil
            }
            index = nextIndex
        }
        return bytes
    }
}
