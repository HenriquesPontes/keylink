import SwiftUI

struct CardRow: View {
    let card: Card
    
    var body: some View {
        ZStack(alignment: .top) {
            // Background
            if let imageData = card.imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.black.opacity(0.4))
                    )
            } else {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(
                        gradient: Gradient(colors: getColors(for: card.type)),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(height: 220)
                    .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            
            // Subtle inner border for glass effect
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                .frame(height: 220)
            
            VStack {
                HStack(alignment: .top) {
                    Text(card.name)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(getTextColor(for: card))
                        .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                    
                    Spacer()
                    
                    // Card logo / icon
                    Image(systemName: getIcon(for: card.type))
                        .foregroundColor(getTextColor(for: card))
                        .font(.system(size: 28, weight: .semibold))
                        .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                }
                
                Spacer()
                
                HStack {
                    Text(card.displayUID)
                        .font(.system(.title3, design: .monospaced))
                        .foregroundColor(getTextColor(for: card).opacity(0.9))
                        .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                    Spacer()
                }
            }
            .padding(24)
            .frame(height: 220)
        }
    }
    
    private func getTextColor(for card: Card) -> Color {
        // We can use white for all of these as the background colors will be relatively dark/vibrant
        return .white
    }
    
    private func getColors(for type: CardType) -> [Color] {
        switch type {
        case .mifareClassic:
            // Blue gradient for Mifare Classic
            return [Color(hex: "117ACA") ?? .blue, Color(hex: "004085") ?? .blue]
        case .hidProx26:
            // Red gradient for HID Prox
            return [Color(hex: "D42937") ?? .red, Color(hex: "8B0000") ?? .red]
        case .mifareUltralight:
            // Purple gradient for Mifare Ultralight
            return [Color(hex: "BB80E0") ?? .purple, Color(hex: "7030A0") ?? .purple]
        case .desfireLight:
            // Green/Teal gradient for Desfire
            return [Color(hex: "006241") ?? .green, Color(hex: "1E3932") ?? .green]
        }
    }
    
    private func getIcon(for type: CardType) -> String {
        switch type {
        case .mifareClassic:
            return "creditcard.fill"
        case .hidProx26:
            return "sensor.tag.radiowaves.forward"
        case .mifareUltralight:
            return "bolt.horizontal.circle.fill"
        case .desfireLight:
            return "lock.shield.fill"
        }
    }
}

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
