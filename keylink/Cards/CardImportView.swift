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
