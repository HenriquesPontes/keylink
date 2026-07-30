import Foundation
import LocalAuthentication
import SwiftUI
import Combine

class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var error: String? = nil

    func authenticate() {
        let context = LAContext()
        var error: NSError?

        // Check if the device is capable of biometric authentication
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            let reason = "Authenticate to access your saved cards"

            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, authenticationError in
                DispatchQueue.main.async {
                    if success {
                        self.isAuthenticated = true
                        self.error = nil
                    } else {
                        self.isAuthenticated = false
                        self.error = authenticationError?.localizedDescription ?? "Failed to authenticate"
                    }
                }
            }
        } else {
            // Fallback for devices without biometrics or if it's not enrolled
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Authenticate to access your saved cards") { success, authenticationError in
                DispatchQueue.main.async {
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
}
