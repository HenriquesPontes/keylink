import ActivityKit
import Foundation

struct EmulationAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var timeRemaining: Int
        var status: String
    }

    var cardName: String
}
