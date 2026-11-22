import Foundation
import SwiftUI
import WatchConnectivity

struct Attack: Codable, Identifiable {
    var id = UUID()
    var start = Date()
    var end: Date?
}

struct Notes: Codable {
    var start: Date?
    var intensity = 0
    var aura = false
    var medication = ""
    var effect = ""
}

struct JournalData: Codable {
    var attacks: [Attack] = []
    var notes: [UUID: Notes] = [:]
}

@MainActor
final class Journal: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var data = JournalData()
    @Published var error: String?
    private let file = URL.applicationSupportDirectory.appending(path: "journal.json")
    private var canWrite = true

    override init() {
        super.init()
        do {
            data = try JSONDecoder().decode(JournalData.self, from: Data(contentsOf: file))
        } catch let failure as CocoaError where failure.code == .fileReadNoSuchFile {
            // First launch.
        } catch {
            canWrite = false
            self.error = "Dagboken kunde inte läsas."
        }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    var active: Attack? { data.attacks.first { $0.end == nil } }

    func start(for attack: Attack) -> Date {
        data.notes[attack.id]?.start ?? attack.start
    }

    @discardableResult
    private func save(_ updated: JournalData) -> Bool {
        guard canWrite else { error = "Dagboken kunde inte läsas."; return false }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(updated).write(to: file, options: .atomic)
            data = updated
            return true
        } catch {
            self.error = "Ändringen kunde inte sparas på enheten."
            return false
        }
    }

    #if os(watchOS)
    @discardableResult
    func toggleAttack() -> Bool {
        var updated = data
        if let index = updated.attacks.firstIndex(where: { $0.end == nil }) {
            updated.attacks[index].end = max(Date(), updated.attacks[index].start)
        } else {
            updated.attacks.insert(Attack(), at: 0)
        }
        guard save(updated) else { return false }
        sync()
        return true
    }

    private func sync() {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        do {
            let payload = try JSONEncoder().encode(data.attacks)
            try session.updateApplicationContext(["attacks": payload])
        } catch {
            self.error = "Sparat på klockan. Överföring försöks igen när appen öppnas."
        }
    }

    func refresh() { sync() }
    #else
    @discardableResult
    func updateNotes(_ notes: Notes, for id: UUID) -> Bool {
        var updated = data
        updated.notes[id] = notes
        return save(updated)
    }

    private func receive(_ payload: Data) {
        guard let incoming = try? JSONDecoder().decode([Attack].self, from: payload) else { return }
        var merged = Dictionary(uniqueKeysWithValues: data.attacks.map { ($0.id, $0) })
        for attack in incoming {
            if merged[attack.id]?.end == nil { merged[attack.id] = attack }
        }
        var updated = data
        updated.attacks = merged.values.sorted { $0.start > $1.start }
        save(updated)
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        guard state == .activated else { return }
        #if os(watchOS)
        Task { @MainActor in self.sync() }
        #else
        if let payload = session.receivedApplicationContext["attacks"] as? Data {
            Task { @MainActor in self.receive(payload) }
        }
        #endif
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        #if os(iOS)
        if let payload = context["attacks"] as? Data {
            Task { @MainActor in self.receive(payload) }
        }
        #endif
    }
}
