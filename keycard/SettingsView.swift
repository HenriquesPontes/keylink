import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Build")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Hardware") {
                    NavigationLink(destination: HardwareSettingsView()) {
                        HStack {
                            Image(systemName: "cpu")
                            Text("KeyCard Bridge Settings")
                        }
                    }
                }
                
                Section {
                    Button(role: .destructive) {
                        // TODO: Reset app data logic
                    } label: {
                        Text("Reset App Data")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
