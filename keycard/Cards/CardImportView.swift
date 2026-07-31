import SwiftUI
import UniformTypeIdentifiers
import SwiftData

struct CardImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var showDocumentPicker = false
    @State private var importedCard: Card?
    @State private var cardName: String = ""
    @State private var errorMessage: String?
    @State private var showError = false
    
    // 125kHz Manual Entry
    @State private var showManualEntry = false
    @State private var manualFC: String = ""
    @State private var manualCN: String = ""
    
    // NFC Reader
    @State private var nfcReader = NFCReaderManager()
    

    var onImport: ((Card) -> Void)?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Import method selection
                VStack(spacing: 16) {
                    Button {
                        nfcReader.scan { card in
                            importedCard = card
                            cardName = card.name
                        } onError: { error in
                            errorMessage = error
                            showError = true
                        }
                    } label: {
                        HStack {
                            Image(systemName: "wave.3.right.circle")
                                .font(.title2)
                            VStack(alignment: .leading) {
                                Text("Scan NFC Card")
                                    .font(.headline)
                                Text("Hold card near top of iPhone")
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
                    
                    Button {
                        showManualEntry = true
                    } label: {
                        HStack {
                            Image(systemName: "keyboard")
                                .font(.title2)
                            VStack(alignment: .leading) {
                                Text("Manual Entry (125kHz)")
                                    .font(.headline)
                                Text("Enter Facility Code & Card Number")
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
                            
                            if card.type == .mifareClassic {
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
                            } else {
                                HStack {
                                    Text("Type")
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("HID Prox (26-bit)")
                                        .foregroundColor(.blue)
                                }
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
            .alert("Manual Entry (125kHz)", isPresented: $showManualEntry) {
                TextField("Facility Code (0-255)", text: $manualFC)
                    .keyboardType(.numberPad)
                TextField("Card Number (0-65535)", text: $manualCN)
                    .keyboardType(.numberPad)
                Button("Cancel", role: .cancel) { }
                Button("Add") {
                    if let fc = Int(manualFC), let cn = Int(manualCN) {
                        let uidHex = String(format: "%02X%04X", fc, cn)
                        importedCard = Card(name: "HID Prox", type: .hidProx26, uid: uidHex, facilityCode: fc, cardNumber: cn)
                        cardName = importedCard?.name ?? ""
                    } else {
                        errorMessage = "Invalid Facility Code or Card Number"
                        showError = true
                    }
                }
            } message: {
                Text("Enter the Facility Code and Card Number found on the back of the HID Prox badge.")
            }

        }
    }
}

// MARK: - Document Picker Wrapper

struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.json, UTType.plainText, UTType.data])
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
