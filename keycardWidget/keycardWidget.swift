import WidgetKit
import SwiftUI
import ActivityKit

struct keycardWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EmulationAttributes.self) { context in
            // Lock screen / banner UI
            VStack {
                HStack {
                    Image(systemName: "wave.3.right.circle.fill")
                        .foregroundColor(.blue)
                    Text("Emulating \(context.attributes.cardName)")
                        .font(.headline)
                    Spacer()
                    Text("\(context.state.timeRemaining)s")
                        .font(.system(.title2, design: .rounded).monospacedDigit())
                        .foregroundColor(.blue)
                }
                .padding(.bottom, 4)
                
                Text(context.state.status)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.cardName, systemImage: "wave.3.right.circle.fill")
                        .font(.headline)
                        .foregroundColor(.blue)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.timeRemaining)s")
                        .font(.system(.title2, design: .rounded).monospacedDigit())
                        .foregroundColor(.blue)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.status)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } compactLeading: {
                Image(systemName: "wave.3.right.circle.fill")
                    .foregroundColor(.blue)
            } compactTrailing: {
                Text("\(context.state.timeRemaining)")
                    .font(.system(.body, design: .rounded).monospacedDigit())
                    .foregroundColor(.blue)
            } minimal: {
                Image(systemName: "wave.3.right.circle.fill")
                    .foregroundColor(.blue)
            }
        }
    }
}

@main
struct keycardWidgetBundle: WidgetBundle {
    var body: some Widget {
        keycardWidgetLiveActivity()
    }
}
