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
            for (_, block) in sectors.enumerated() {
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
            return (raw.count == 8 || raw.count == 14) ? raw : nil
        }
        return nil
    }
}
