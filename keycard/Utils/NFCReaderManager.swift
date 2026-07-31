import Foundation
import CoreNFC

class NFCReaderManager: NSObject, NFCTagReaderSessionDelegate {
    var session: NFCTagReaderSession?
    var onTagDetected: ((Card) -> Void)?
    var onError: ((String) -> Void)?
    
    func scan(onTagDetected: @escaping (Card) -> Void, onError: @escaping (String) -> Void) {
        self.onTagDetected = onTagDetected
        self.onError = onError
        
        guard NFCTagReaderSession.readingAvailable else {
            onError("NFC reading is not available on this device.")
            return
        }
        
        session = NFCTagReaderSession(pollingOption: [.iso14443, .iso15693], delegate: self, queue: nil)
        session?.alertMessage = "Hold your tag near the camera area on the back of your device to read it."
        session?.begin()
    }
    
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        // Session active
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        if let readerError = error as? NFCReaderError, readerError.code != .readerSessionInvalidationErrorUserCanceled {
            DispatchQueue.main.async {
                self.onError?(error.localizedDescription)
            }
        }
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first else { return }
        
        session.connect(to: tag) { error in
            if let error = error {
                session.invalidate(errorMessage: "Connection error: \(error.localizedDescription)")
                return
            }
            
            var uidString = ""
            var type: CardType = .mifareClassic
            
            switch tag {
            case .miFare(let miFareTag):
                uidString = miFareTag.identifier.map { String(format: "%02hhX", $0) }.joined()
                if miFareTag.mifareFamily == .ultralight {
                    type = .mifareUltralight
                }
            case .feliCa(let feliCaTag):
                uidString = feliCaTag.currentIDm.map { String(format: "%02hhX", $0) }.joined()
            case .iso15693(let iso15693Tag):
                uidString = iso15693Tag.identifier.map { String(format: "%02hhX", $0) }.joined()
            case .iso7816(let iso7816Tag):
                uidString = iso7816Tag.identifier.map { String(format: "%02hhX", $0) }.joined()
                type = .desfireLight
            @unknown default:
                session.invalidate(errorMessage: "Unsupported tag type.")
                return
            }
            
            let card = Card(name: "Card \(uidString.prefix(4))", type: type, uid: uidString)
            
            session.alertMessage = "Card read successfully!"
            session.invalidate()
            
            DispatchQueue.main.async {
                self.onTagDetected?(card)
            }
        }
    }
}
