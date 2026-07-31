import SwiftUI
import ActivityKit
import Combine

class NFCEmulationPresenter: ObservableObject {
    @Published var isEmulating = false
    var currentActivity: Activity<EmulationAttributes>?
    
    func showSystemNFCUI(message: String = "Hold Near Reader", cardName: String = "KeyCard") {
        if ActivityAuthorizationInfo().areActivitiesEnabled {
            let attributes = EmulationAttributes(cardName: cardName)
            let state = EmulationAttributes.ContentState(timeRemaining: 15, status: message)
            
            do {
                if #available(iOS 16.2, *) {
                    currentActivity = try Activity.request(
                        attributes: attributes,
                        content: .init(state: state, staleDate: nil),
                        pushType: nil
                    )
                } else {
                    currentActivity = try Activity.request(
                        attributes: attributes,
                        contentState: state,
                        pushType: nil
                    )
                }
            } catch {
                print("Failed to request Live Activity: \(error.localizedDescription)")
            }
        } else {
            print("Live Activities are not enabled on this device.")
        }
    }
    
    func stopSystemNFCUI(successMessage: String? = nil) {
        let finalStatus = successMessage ?? "Completed"
        let state = EmulationAttributes.ContentState(timeRemaining: 0, status: finalStatus)
        
        Task {
            if #available(iOS 16.2, *) {
                await currentActivity?.end(
                    ActivityContent(state: state, staleDate: nil),
                    dismissalPolicy: .default
                )
            } else {
                await currentActivity?.end(using: state, dismissalPolicy: .default)
            }
            self.currentActivity = nil
        }
    }
}
