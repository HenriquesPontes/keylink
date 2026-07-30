import SwiftUI

struct EmulationView: View {
    let card: Card
    @Environment(\.dismiss) private var dismiss
    @StateObject private var ble = BLEManager()
    @StateObject private var nfcd = NFCDManager()
    
    @State private var isEmulating = false
    @State private var timeRemaining = 30
    @State private var timer: Timer?
    @State private var showSuccess = false
    @State private var selectedDuration = 30
    
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
                    
                    // NFCD Status
                    HStack {
                        Circle()
                            .fill(nfcd.statusMessage.contains("loaded") ? Color.green : Color.orange)
                            .frame(width: 10, height: 10)
                        Text("NFCD: \(nfcd.statusMessage)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Timer & Duration
                VStack {
                    if isEmulating {
                        Text("\(timeRemaining)s")
                            .font(.system(size: 64, weight: .thin, design: .rounded))
                            .foregroundColor(.blue)
                            .contentTransition(.numericText())
                    } else {
                        HStack {
                            Text("Emulate for:")
                                .foregroundColor(.secondary)
                            Picker("Duration", selection: $selectedDuration) {
                                Text("5s").tag(5)
                                Text("15s").tag(15)
                                Text("30s").tag(30)
                                Text("60s").tag(60)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 200)
                        }
                        .padding(.vertical)
                    }
                }
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 16) {
                    Button {
                        if isEmulating {
                            stopEmulation()
                        } else {
                            startEmulation()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: isEmulating && !nfcd.isEmulating ? "stop.fill" : "play.fill")
                            Text(isEmulating && !nfcd.isEmulating ? "Stop" : "Emulate (Bridge)")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isEmulating && !nfcd.isEmulating ? Color.red : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                    }
                    .disabled(!ble.isConnected || nfcd.isEmulating)
                    
                    Button {
                        if nfcd.isEmulating {
                            stopDirectEmulation()
                        } else {
                            startDirectEmulation()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: nfcd.isEmulating ? "stop.fill" : "iphone.radiowaves.left.and.right")
                            Text(nfcd.isEmulating ? "Stop" : "Direct Emulate (Jailbreak)")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(nfcd.isEmulating ? Color.red : Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                    }
                    .disabled(isEmulating && !nfcd.isEmulating)
                }
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let level = ble.batteryLevel {
                        HStack(spacing: 4) {
                            Text("\(level)%")
                                .font(.caption)
                                .foregroundColor(level > 20 ? .green : .red)
                            Image(systemName: level > 20 ? "battery.100" : "battery.25")
                                .foregroundColor(level > 20 ? .green : .red)
                        }
                    }
                }
            }
            .onAppear {
                // Auto-load card to bridge when view appears
                if ble.isConnected {
                    ble.loadCard(card)
                }
            }
            .onChange(of: ble.isConnected) { connected in
                if connected {
                    ble.loadCard(card)
                }
            }
        }
    }
    
    private func startEmulation() {
        ble.startEmulate(card: card, duration: selectedDuration)
        isEmulating = true
        timeRemaining = selectedDuration
        
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
    
    private func startDirectEmulation() {
        nfcd.startDirectEmulation(card: card)
        isEmulating = true
        timeRemaining = selectedDuration
        
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if timeRemaining > 0 {
                timeRemaining -= 1
            } else {
                stopDirectEmulation()
            }
        }
    }
    
    private func stopDirectEmulation() {
        nfcd.stopDirectEmulation()
        isEmulating = false
        timer?.invalidate()
        timer = nil
    }
}
