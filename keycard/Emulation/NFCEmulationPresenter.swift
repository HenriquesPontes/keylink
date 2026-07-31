import SwiftUI
import ActivityKit
import CoreNFC
import Combine

class NFCEmulationPresenter: NSObject, NFCTagReaderSessionDelegate, ObservableObject {
    @Published var isEmulating = false
    var session: NFCTagReaderSession?
    
    func showSystemNFCUI(message: String = "Hold Near Reader", cardName: String = "KeyCard") {
        if !NFCTagReaderSession.readingAvailable {
            print("NFC reading is not available on this device (e.g., Simulator). System NFC UI cannot be shown.")
            // On a real device, it will proceed.
        }
        
        session = NFCTagReaderSession(pollingOption: [.iso14443, .iso15693], delegate: self, queue: nil)
        session?.alertMessage = message
        session?.begin()
        
        DispatchQueue.main.async {
            self.isEmulating = true
        }
    }
    
    func stopSystemNFCUI(successMessage: String? = nil) {
        if let msg = successMessage {
            session?.alertMessage = msg
            // Delay invalidation slightly so the user sees the success message
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.session?.invalidate()
                self.session = nil
            }
        } else {
            session?.invalidate()
            session = nil
        }
        
        DispatchQueue.main.async {
            self.isEmulating = false
        }
    }
    
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        DispatchQueue.main.async {
            self.session = nil
            self.isEmulating = false
        }
    }
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {}
}
