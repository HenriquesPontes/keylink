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
