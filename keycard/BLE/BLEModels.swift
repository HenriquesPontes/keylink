import Foundation

// MARK: - Incoming Commands (iPhone → Bridge)

struct LoadCardCommand: Codable {
    let cmd: String = "load_card"
    let uid: String
    let atqa: [UInt8]
    let sak: UInt8
    let sectors: [[UInt8]]?
}

struct EmulateCommand: Codable {
    let cmd: String = "emulate"
    let duration: Int
}

struct StopCommand: Codable {
    let cmd: String = "stop"
}

// MARK: - Outgoing Status (Bridge → iPhone)

struct BridgeStatus: Codable {
    let status: String
    let msg: String
    let uid: String?
}

// MARK: - Proxmark3 Import Format

struct ProxmarkImport: Codable {
    let cmd: String?
    let uid: String
    let atqa: [UInt8]?
    let sak: UInt8?
    let sectors: [[UInt8]]?
    
    func toCard(name: String) -> Card {
        Card(
            name: name,
            uid: uid,
            atqa: atqa ?? [0x00, 0x04],
            sak: sak ?? 0x08,
            sectors: sectors
        )
    }
}
