import Foundation

enum ImportError: LocalizedError, Equatable {
    case invalidJSON
    case missingUID
    case invalidUIDFormat
    case invalidSectorCount(expected: Int, got: Int)
    case invalidBlockSize(expected: Int, got: Int)
    case invalidBinSize(got: Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidJSON: return "File is not valid JSON or BIN format"
        case .missingUID: return "Missing UID field"
        case .invalidUIDFormat: return "UID must be 8 or 14 hex characters"
        case .invalidSectorCount(let exp, let got): return "Expected \(exp) sectors, got \(got)"
        case .invalidBlockSize(let exp, let got): return "Expected \(exp) bytes per block, got \(got)"
        case .invalidBinSize(let got): return "Invalid .bin file size (expected 64, 192, 540, 1024, or 4096 bytes, got \(got))"
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
        if let imported = try? decoder.decode(ProxmarkImport.self, from: data) {
            return try processJSONImport(imported)
        }
        
        // If JSON parsing fails, attempt to parse as a raw .bin dump
        do {
            return try importFromBin(data)
        } catch {
            throw ImportError.invalidJSON
        }
    }
    
    private func processJSONImport(_ imported: ProxmarkImport) throws -> Card {
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
        
        let atqa = imported.atqa ?? [0x00, 0x04]
        let sak = imported.sak ?? 0x08
        
        var cardType: CardType = .mifareClassic
        if atqa == [0x44, 0x03] && sak == 0x20 {
            cardType = .desfireLight
        } else if atqa == [0x44, 0x00] && sak == 0x00 {
            cardType = .mifareUltralight
        }
        
        return Card(
            name: name,
            type: cardType,
            uid: cleanUID,
            atqa: atqa,
            sak: sak,
            sectors: imported.sectors
        )
    }
    
    private func importFromBin(_ data: Data) throws -> Card {
        let size = data.count
        
        // MIFARE Classic: 1024 (1K) or 4096 (4K)
        if size == 1024 || size == 4096 {
            let block0 = [UInt8](data[0..<16])
            let uidBytes = block0[0..<4]
            let uidString = uidBytes.map { String(format: "%02X", $0) }.joined()
            
            let atqa: [UInt8] = [0x00, 0x04]
            let sak: UInt8 = 0x08
            
            let numBlocks = size / 16
            var sectors: [[UInt8]] = []
            
            for i in 0..<numBlocks {
                let start = i * 16
                let blockData = [UInt8](data[start..<(start + 16)])
                sectors.append(blockData)
            }
            
            return Card(
                name: "MIFARE Classic \(uidString.prefix(4))",
                type: .mifareClassic,
                uid: uidString,
                atqa: atqa,
                sak: sak,
                sectors: sectors
            )
        } 
        // MIFARE Ultralight / NTAG: 64, 192, or 540 bytes
        else if size == 64 || size == 192 || size == 540 {
            // Read page 0 and 1 for 7-byte UID. (Byte 0-2 from page 0, Byte 0-3 from page 1)
            let uidBytes = [UInt8](data[0..<3]) + [UInt8](data[4..<8])
            let uidString = uidBytes.map { String(format: "%02X", $0) }.joined()
            
            let atqa: [UInt8] = [0x44, 0x00] // Ultralight standard
            let sak: UInt8 = 0x00            // Ultralight standard
            
            let numPages = size / 4
            var pages: [[UInt8]] = []
            
            for i in 0..<numPages {
                let start = i * 4
                let pageData = [UInt8](data[start..<(start + 4)])
                pages.append(pageData)
            }
            
            return Card(
                name: "Ultralight/NTAG \(uidString.prefix(4))",
                type: .mifareUltralight,
                uid: uidString,
                atqa: atqa,
                sak: sak,
                pages: pages
            )
        } else {
            throw ImportError.invalidBinSize(got: size)
        }
    }

    
    /// Quick-parse just the UID from raw Proxmark3 console output
    func parseUIDFromConsoleOutput(_ text: String) -> String? {
        // Match patterns like: UID: A1 B2 C3 D4  or  [+] UID: A1B2C3D4
        let pattern = #"UID:\s*([A-Fa-f0-9 ]{8,})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        if let range = Range(match.range(at: 1), in: text) {
            let raw = String(text[range]).components(separatedBy: .whitespaces).joined().uppercased()
            return (raw.count == 8 || raw.count == 14) ? raw : nil
        }
        return nil
    }
}
