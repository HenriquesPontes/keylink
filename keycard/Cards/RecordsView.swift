import SwiftUI
import SwiftData

struct RecordsView: View {
    @Bindable var card: Card
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 60))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 16)
                
                Text("No Records")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("There are no NDEF records or activity history associated with this card yet.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 4)
                
                Spacer()
            }
            .padding(.top, 100)
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Records")
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
