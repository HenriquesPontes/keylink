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
