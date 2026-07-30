import SwiftUI

struct EmulationView: View {
    let card: Card
    @Environment(\.dismiss) private var dismiss
    @StateObject private var ble = BLEManager()
    
    @State private var isEmulating = false
    @State private var timeRemaining = 30
    @State private var timer: Timer?
    @State private var showSuccess = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 32) {
                // Card visualization
                VStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: card.isFullClone ? 
                                        [Color.green.opacity(0.3), Color.green.opacity(0.1)] :
                                        [Color.orange.opacity(0.3), Color.orange.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(height: 180)
                        
                        VStack(spacing: 12) {
                            Image(systemName: "wave.3.right.circle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(card.isFullClone ? .green : .orange)
                            
                            Text(card.name)
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text(card.displayUID)
                                .font(.system(.title3, design: .monospaced))
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                isEmulating ? Color.blue : Color.clear,
                                lineWidth: 3
                            )
                            .animation(.easeInOut, value: isEmulating)
                    )
                }
                .padding(.horizontal)
                
                // Status
                VStack(spacing: 8) {
                    HStack {
                        Circle()
                            .fill(ble.isConnected ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                        Text(ble.isConnected ? "Bridge Connected" : "Searching for Bridge...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let event = ble.lastReaderEvent {
                        Label(event, systemImage: "checkmark.shield.fill")
                            .foregroundColor(.green)
                            .font(.headline)
                            .transition(.scale.combined(with: .opacity))
                    }
                    
                    Text(ble.statusMessage)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                // Timer
                if isEmulating {
                    Text("\(timeRemaining)s")
                        .font(.system(size: 64, weight: .thin, design: .rounded))
                        .foregroundColor(.blue)
                        .contentTransition(.numericText())
                }
                
                Spacer()
                
                // Action button
                Button {
                    if isEmulating {
                        stopEmulation()
                    } else {
                        startEmulation()
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: isEmulating ? "stop.fill" : "play.fill")
                        Text(isEmulating ? "Stop" : "Emulate")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isEmulating ? Color.red : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(16)
                }
                .disabled(!ble.isConnected)
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .navigationTitle("Emulate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { 
                        stopEmulation()
                        dismiss() 
                    }
                }
            }
            .onAppear {
                // Auto-load card to bridge when view appears
                if ble.isConnected {
                    ble.loadCard(
                        uid: card.uid,
                        atqa: card.atqa,
                        sak: card.sak,
                        sectors: card.sectors
                    )
                }
            }
            .onChange(of: ble.isConnected) { connected in
                if connected {
                    ble.loadCard(
                        uid: card.uid,
                        atqa: card.atqa,
                        sak: card.sak,
                        sectors: card.sectors
                    )
                }
            }
        }
    }
    
    private func startEmulation() {
        ble.startEmulate(duration: 30)
        isEmulating = true
        timeRemaining = 30
        
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if timeRemaining > 0 {
                timeRemaining -= 1
            } else {
                stopEmulation()
            }
        }
    }
    
    private func stopEmulation() {
        ble.stopEmulate()
        isEmulating = false
        timer?.invalidate()
        timer = nil
    }
}
