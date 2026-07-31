import Foundation
import LocalAuthentication
import SwiftUI
import Combine

class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var error: String? = nil
    private var isAuthenticating = false

    func authenticate() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        
        let context = LAContext()
        let reason = "Authenticate to access your saved cards"

        // .deviceOwnerAuthentication automatically uses FaceID/TouchID if available,
        // and provides a working "Enter Password" fallback to the device passcode.
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, authenticationError in
            DispatchQueue.main.async {
                self.isAuthenticating = false
                if success {
                    self.isAuthenticated = true
                    self.error = nil
                } else {
                    self.isAuthenticated = false
                    self.error = authenticationError?.localizedDescription ?? "Failed to authenticate"
                }
            }
        }
    }
}
