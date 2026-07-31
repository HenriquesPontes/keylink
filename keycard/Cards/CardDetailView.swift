import SwiftUI
import SwiftData
import PhotosUI

struct CardDetailView: View {
    @Bindable var card: Card
    @State private var showEmulation = false
    @State private var showRecords = false
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var showRenameAlert = false
    @State private var newName = ""
    
    @State private var selectedPhotoItem: PhotosPickerItem? = nil

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Card Header
                    CardRow(card: card)
                    .padding(.top, 16)
                    .onTapGesture {
                        showEmulation = true
                    }

                // Action Buttons
                HStack(spacing: 12) {
                    ActionButton(
                        title: "Emulate", icon: "play.fill",
                        action: {
                            showEmulation = true
                        })

                    Menu {
                        Button {
                            alertTitle = "Firmware Update"
                            alertMessage = "Checking for Firmware OTA Updates..."
                            showAlert = true
                        } label: {
                            Label(
                                "Firmware OTA Updates", systemImage: "arrow.triangle.2.circlepath")
                        }
                    } label: {
                        ActionButtonView(title: "Update", icon: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)

                    ActionButton(
                        title: "Records", icon: "list.bullet.rectangle",
                        action: {
                            showRecords = true
                        })

                    Menu {
                        Button {
                            alertTitle = "Write"
                            alertMessage = "Writing to \(card.name)..."
                            showAlert = true
                        } label: {
                            Label("Write to \(card.name)", systemImage: "arrow.down.circle")
                        }

                        Menu {
                            Button("Advanced Write Option 1") {
                                alertTitle = "Advanced Write"
                                alertMessage = "Option 1 selected."
                                showAlert = true
                            }
                        } label: {
                            Label("Advanced", systemImage: "gearshape")
                        }

                        Divider()

                        Button {
                            alertTitle = "Write"
                            alertMessage = "Writing to any card..."
                            showAlert = true
                        } label: {
                            Label("Write to Any Card", systemImage: "arrow.down.circle")
                        }

                        Button {
                            alertTitle = "Batch Write"
                            alertMessage = "Starting batch write mode..."
                            showAlert = true
                        } label: {
                            Label(
                                "Write to Any Card - Batch Mode", systemImage: "arrow.down.circle")
                        }
                    } label: {
                        ActionButtonView(title: "Write", icon: "square.and.arrow.down.fill")
                    }
                    .buttonStyle(.plain)
                }

                // Tag Information
                VStack(alignment: .leading, spacing: 20) {
                    Text("Tag Information")
                        .font(.headline)
                        .foregroundColor(.primary)

                    InfoRow(
                        icon: "creditcard",
                        title: "UID",
                        description:
                            "The unique identifier (UID) is a hardware-based serial number permanently assigned to each NFC tag during manufacturing. This identifier cannot be changed and serves as the tag's digital fingerprint.",
                        value: card.displayUID
                    )

                    InfoRow(
                        icon: "plus.circle",
                        title: "Source",
                        description:
                            "Indicates how this NFC tag was obtained in the system. Tags can either be manually created by you through the app's creation feature, or scanned and cloned from existing physical NFC cards or tags.",
                        value: "Created"
                    )

                    InfoRow(
                        icon: "calendar",
                        title: "Created At",
                        description: "The date and time when this card was added to your library.",
                        value: card.createdAt.formatted(date: .abbreviated, time: .shortened)
                    )

                    if card.type == .mifareClassic, card.sectors != nil {
                        NavigationLink(destination: SectorKeysView(card: card)) {
                            HStack {
                                Image(systemName: "key.fill")
                                    .font(.title3)
                                Text("View Sector Keys")
                                    .fontWeight(.semibold)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .presentationDetents([.fraction(0.9)])
        .sheet(isPresented: $showEmulation) {
            EmulationView(card: card)
        }
        .sheet(isPresented: $showRecords) {
            RecordsView(card: card)
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .alert("Rename Card", isPresented: $showRenameAlert) {
            TextField("Card Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                card.name = newName
            }
        } message: {
            Text("Enter a new name for this card.")
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        newName = card.name
                        showRenameAlert = true
                    } label: {
                        Label("Pick Nickname", systemImage: "pencil")
                    }

                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label("Choose Card Image", systemImage: "photo")
                    }
                    .onChange(of: selectedPhotoItem) { _, newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                card.imageData = data
                            }
                        }
                    }

                    Divider()

                    Menu {
                        // TODO: Sort Options
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }

                    Menu {
                        // TODO: Advanced Options
                    } label: {
                        Label("Advanced", systemImage: "ellipsis")
                    }

                    Divider()

                    Button(role: .destructive) {
                        modelContext.delete(card)
                        dismiss()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title3)
                }
            }
        }
        }
    }
}

struct ActionButtonView: View {
    let title: String
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: 16).fill(
                        Color(UIColor.secondarySystemGroupedBackground))
                )
                .frame(height: 72)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 26))
                        .foregroundColor(.primary)
                )

            Text(title)
                .font(.caption)
                .foregroundColor(.primary)  // Keep text primary so it's readable in light/dark
        }
    }
}

struct ActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ActionButtonView(title: title, icon: icon)
        }
        .buttonStyle(.plain)
    }
}

struct InfoRow: View {
    let icon: String
    let title: String
    let description: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: icon)
                    .foregroundColor(.secondary)
                    .frame(width: 20)

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.bold)

                Spacer()

                Text(value)
                    .font(.subheadline)
                    .fontWeight(.bold)
            }

            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineSpacing(4)
        }
        .padding(.vertical, 8)
    }
}

struct SectorKeysView: View {
    @Bindable var card: Card

    var body: some View {
        Form {
            if let sectors = card.sectors {
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
                                    SectorEditView(
                                        card: card, sectorIndex: sectorIndex,
                                        trailerBlockIndex: trailerBlockIndex, keyA: keyA, keyB: keyB
                                    )
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
        .navigationTitle("Sector Keys")
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
            Section(
                header: Text("Sector \(sectorIndex) Keys"),
                footer: Text("Keys must be exactly 12 hex characters (6 bytes).")
            ) {
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
        card.sectors = sectors  // Trigger SwiftData update

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
