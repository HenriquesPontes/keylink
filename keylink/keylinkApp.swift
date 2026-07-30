import SwiftUI
import SwiftData

@main
struct keylinkApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Card.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .automatic)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @StateObject private var authManager = AuthenticationManager()
    @Environment(\.scenePhase) var scenePhase

    var body: some Scene {
        WindowGroup {
            if authManager.isAuthenticated {
                CardLibraryView()
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "faceid")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                    
                    Text("Authentication Required")
                        .font(.title2)
                        .bold()
                    
                    if let error = authManager.error {
                        Text(error)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    Button("Unlock KeyLink") {
                        authManager.authenticate()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .onAppear {
                    authManager.authenticate()
                }
            }
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background {
                authManager.isAuthenticated = false
            } else if newPhase == .active && !authManager.isAuthenticated {
                authManager.authenticate()
            }
        }
    }
}
