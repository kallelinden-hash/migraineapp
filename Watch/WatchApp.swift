import SwiftUI
import WatchKit

@main
struct MigraineWatchApp: App {
    @StateObject private var journal = Journal()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ScrollView {
                VStack(spacing: 10) {
                    Image(systemName: "waveform.path")
                        .font(.title2)
                        .foregroundStyle(.mint)
                    if let attack = journal.active {
                        Text("Pågår sedan \(attack.start.formatted(date: .omitted, time: .shortened))")
                            .font(.footnote)
                    }
                    Button(journal.active == nil ? "Anfall startat" : "Anfall slut") {
                        if journal.toggleAttack() {
                            WKInterfaceDevice.current().play(.success)
                        }
                    }
                    .font(.headline)
                    .buttonStyle(.borderedProminent)
                    .tint(journal.active == nil ? .teal : .orange)
                    if let error = journal.error {
                        Text(error).font(.caption2)
                    }
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("Migrän")
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active { journal.refresh() }
            }
        }
    }
}
