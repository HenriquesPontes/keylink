import Foundation
import SwiftData

enum CardType: String, Codable {
    case mifareClassic
    case hidProx26
}

@Model
final class Card {
    @Attribute(.unique) var id: UUID
    var name: String
    var uid: String          // Hex, uppercase, no spaces
    var atqa: [UInt8]        // 2 bytes
    var sak: UInt8
    var sectors: [[UInt8]]?  // nil = UID-only
    
    // 125kHz specific fields
    var type: CardType = CardType.mifareClassic
    var facilityCode: Int?
    var cardNumber: Int?
    
    var createdAt: Date
    
    init(name: String, type: CardType = .mifareClassic, uid: String = "", atqa: [UInt8] = [0x00, 0x04], sak: UInt8 = 0x08, sectors: [[UInt8]]? = nil, facilityCode: Int? = nil, cardNumber: Int? = nil) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.uid = uid.uppercased().replacingOccurrences(of: " ", with: "")
        self.atqa = atqa
        self.sak = sak
        self.sectors = sectors
        self.facilityCode = facilityCode
        self.cardNumber = cardNumber
        self.createdAt = Date()
    }
    
    var displayUID: String {
        if type == .hidProx26 {
            guard let fc = facilityCode, let cn = cardNumber else { return "Unknown" }
            return "FC: \(fc) | CN: \(cn)"
        }
        
        // Format: A1 B2 C3 D4
        return stride(from: 0, to: uid.count, by: 2).map {
            let start = uid.index(uid.startIndex, offsetBy: $0)
            let end = uid.index(start, offsetBy: 2, limitedBy: uid.endIndex) ?? uid.endIndex
            return String(uid[start..<end])
        }.joined(separator: " ")
    }
    
    var isFullClone: Bool {
        sectors != nil
    }
}
