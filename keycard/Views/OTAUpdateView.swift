import SwiftUI
import UniformTypeIdentifiers

struct OTAUpdateView: View {
    @EnvironmentObject var bleManager: BLEManager
    @StateObject private var otaManager = OTAUpdateManager()
    
    @State private var showFilePicker = false
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 60))
                .foregroundColor(.blue)
                .padding(.top, 40)
            
            Text("Firmware Update")
                .font(.title)
                .bold()
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Instructions:")
                    .font(.headline)
                
                Label("Tap 'Enter OTA Mode' to prepare the bridge.", systemImage: "1.circle.fill")
                Label("Go to Settings > Wi-Fi and connect to **KeyCard-OTA** (Password: `keycard_update`).", systemImage: "2.circle.fill")
                Label("Tap 'Select Firmware File' to upload the `.bin` update.", systemImage: "3.circle.fill")
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            
            Spacer()
            
            if otaManager.isUpdating {
                VStack(spacing: 10) {
                    ProgressView(value: otaManager.progress, total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle())
                        .padding(.horizontal)
                    Text(otaManager.updateStatus)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                if let error = otaManager.updateError {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                } else if otaManager.progress == 1.0 {
                    Text(otaManager.updateStatus)
                        .foregroundColor(.green)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                }
                
                Button(action: {
                    bleManager.enterOTA()
                }) {
                    Text("Enter OTA Mode")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(bleManager.isConnected ? Color.orange : Color.gray)
                        .cornerRadius(12)
                }
                .disabled(!bleManager.isConnected)
                
                Button(action: {
                    showFilePicker = true
                }) {
                    Text("Select Firmware File (.bin)")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
            }
        }
        .padding()
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [UTType.data], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                otaManager.startUpdate(fileURL: url)
            case .failure(let error):
                otaManager.updateError = error.localizedDescription
            }
        }
        .navigationTitle("Update Bridge")
    }
}
