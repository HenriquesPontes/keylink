import SwiftUI
import SwiftData

struct CardLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Card.createdAt, order: .reverse) private var cards: [Card]
    
    @State private var showImport = false
    @State private var selectedCard: Card?
    @State private var showSettings = false
    
    @State private var searchText = ""
    @State private var showSearch = false
    
    private var filteredCards: [Card] {
        if searchText.isEmpty {
            return cards
        } else {
            return cards.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                HStack {
                    Text("Cards")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 10)
                
                if cards.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "square.dashed")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No Cards")
                            .font(.headline)
                        Text("Tap the add button to scan or edit")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 80)
                } else if filteredCards.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No Results")
                            .font(.headline)
                        Text("No cards matched your search.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 80)
                } else {
                    VStack(spacing: -150) {
                        ForEach(filteredCards) { card in
                            CardRow(card: card)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedCard = card
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        deleteCard(card)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .zIndex(zIndex(for: card))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 240) // Space for the last card
                }
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showImport = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(.primary)
                            .font(.title2)
                    }
                }
                
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        showSearch.toggle()
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.primary)
                    }
                    
                    Menu {
                        Button {
                            showSettings = true
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundColor(.primary)
                    }
                }
            }
            .sheet(isPresented: $showImport) {
                CardImportView { card in
                    selectedCard = card
                }
            }
            .sheet(item: $selectedCard) { card in
                CardDetailView(card: card)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
        .searchable(text: $searchText, isPresented: $showSearch, prompt: "Search cards")
    }
    
    private func deleteCard(_ card: Card) {
        modelContext.delete(card)
        try? modelContext.save()
    }
    
    private func zIndex(for card: Card) -> Double {
        Double(-(cards.firstIndex(where: { $0.id == card.id }) ?? 0))
    }
}

