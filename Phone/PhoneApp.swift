import Charts
import SwiftUI

@main
struct MigrainePhoneApp: App {
    @StateObject private var journal = Journal()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                DiaryView(journal: journal)
            }
            .tint(.teal)
        }
    }
}

struct DiaryView: View {
    @ObservedObject var journal: Journal
    @State private var month = Date()
    private let calendar = Calendar.current

    private var period: DateInterval {
        calendar.dateInterval(of: .month, for: month)!
    }

    private var entries: [Attack] {
        journal.data.attacks.filter {
            journal.start(for: $0) < period.end && ($0.end ?? Date()) >= period.start
        }
        .sorted { journal.start(for: $0) > journal.start(for: $1) }
    }

    private var days: Int {
        var dates = Set<Date>()
        for attack in entries {
            var day = calendar.startOfDay(for: max(period.start, journal.start(for: attack)))
            let end = attack.end ?? Date()
            while day < period.end && day <= end {
                dates.insert(day)
                day = calendar.date(byAdding: .day, value: 1, to: day)!
            }
        }
        return dates.count
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Button("Föregående månad", systemImage: "chevron.left") { moveMonth(-1) }
                        .labelStyle(.iconOnly)
                    Spacer()
                    Text(month.formatted(.dateTime.month(.wide).year()))
                        .font(.headline)
                    Spacer()
                    Button("Nästa månad", systemImage: "chevron.right") { moveMonth(1) }
                        .labelStyle(.iconOnly)
                        .disabled(calendar.isDate(month, equalTo: Date(), toGranularity: .month))
                }
                .buttonStyle(.borderless)

                HStack(spacing: 24) {
                    VStack(alignment: .leading) {
                        Text(days, format: .number).font(.largeTitle.bold())
                        Text("Migrändagar").foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading) {
                        Text(entries.count, format: .number).font(.largeTitle.bold())
                        Text("Anfall").foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }
            Section("Anfall") {
                if entries.isEmpty {
                    Text("Inga anfall den här månaden. Registrera nästa anfall på din Apple Watch.")
                        .foregroundStyle(.secondary)
                }
                ForEach(entries) { attack in
                    NavigationLink {
                        AttackDetail(journal: journal, id: attack.id,
                                     notes: journal.data.notes[attack.id] ?? Notes(),
                                     start: journal.start(for: attack))
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(journal.start(for: attack).formatted(date: .abbreviated, time: .shortened))
                                .font(.headline)
                            if let end = attack.end {
                                Text(Duration.seconds(end.timeIntervalSince(journal.start(for: attack)))
                                    .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Pågår").foregroundStyle(.teal)
                            }
                        }
                    }
                }
            }
            if let error = journal.error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Migrändagbok")
        .environment(\.locale, Locale(identifier: "sv_SE"))
    }

    private func moveMonth(_ amount: Int) {
        if let next = calendar.date(byAdding: .month, value: amount, to: period.start) {
            month = next
        }
    }
}

struct AttackDetail: View {
    @ObservedObject var journal: Journal
    let id: UUID
    @State var notes: Notes
    @State var start: Date
    @State private var health = Health()
    @State private var pulse: [HealthPoint] = []
    @State private var hrv: [HealthPoint] = []
    @State private var sleep: Double?
    @State private var referenceSleep: Double?
    @State private var referenceDate: Date?
    @State private var message: String?
    @State private var healthError: String?
    @State private var loading = false
    @State private var loaded = false

    init(journal: Journal, id: UUID, notes: Notes, start: Date) {
        self.journal = journal
        self.id = id
        _notes = State(initialValue: notes)
        _start = State(initialValue: start)
    }

    private var attack: Attack? { journal.data.attacks.first { $0.id == id } }

    var body: some View {
        Form {
            Section("Anfall") {
                DatePicker("Start", selection: $start, in: ...min(attack?.end ?? Date(), Date()))
                    .onChange(of: start) { _, _ in
                        loaded = false
                        healthError = nil
                    }
                if let end = attack?.end {
                    LabeledContent("Slut", value: end.formatted(date: .abbreviated, time: .shortened))
                }
                Picker("Intensitet", selection: $notes.intensity) {
                    Text("Ej angiven").tag(0)
                    ForEach(1...10, id: \.self) { Text("\($0) av 10").tag($0) }
                }
                Toggle("Aura", isOn: $notes.aura)
                TextField("Läkemedel", text: $notes.medication)
                TextField("Upplevd effekt", text: $notes.effect, axis: .vertical)
                Button("Spara ändringar") {
                    guard start <= (attack?.end ?? Date()) else {
                        message = "Starten måste vara före eller vid sluttiden."
                        return
                    }
                    notes.start = start
                    message = journal.updateNotes(notes, for: id) ? "Sparat" : journal.error
                }
                if let message { Text(message).foregroundStyle(.secondary) }
            }

            Section {
                Button(loading ? "Hämtar mätningar…" : "Hämta mätningar") {
                    loading = true
                    Task { await loadHealth() }
                }
                .disabled(loading)
            
                if let healthError {
                    Text(healthError).foregroundStyle(.secondary)
                }
            
                if loaded {
                    LabeledContent("Sömn, föregående 24 timmar", value: hours(sleep))
                    if let referenceDate {
                        LabeledContent(
                            "Sömn före \(referenceDate.formatted(date: .abbreviated, time: .shortened))",
                            value: hours(referenceSleep)
                        )
                        Text("Jämförelsen visar 24 timmar utan registrerat anfall.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    pointChart("Puls (slag/min)", values: pulse)
                    pointChart("Pulsvariation (ms)", values: hrv)
                }
            } header: {
                Text("Apple Hälsa")
            } footer: {
                Text("Visar tillgängliga mätningar under de 24 timmar som föregår vald starttid. Tomma perioder har inga tillgängliga mätvärden.")
            }
        }
        .navigationTitle("Anfallsdetaljer")
        .environment(\.locale, Locale(identifier: "sv_SE"))
    }

    private func hours(_ value: Double?) -> String {
        guard let value else { return "Saknas" }
        return "\(value.formatted(.number.precision(.fractionLength(1)))) h"
    }

    @ViewBuilder
    private func pointChart(_ title: String, values: [HealthPoint]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.bold())
            if values.isEmpty {
                Text("Inga tillgängliga värden").foregroundStyle(.secondary)
            } else {
                Chart(values) { point in
                    PointMark(x: .value("Tid", point.date), y: .value(title, point.value))
                        .foregroundStyle(.teal)
                        .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .shortened))
                        .accessibilityValue(point.value.formatted())
                }
                .chartXScale(domain: start.addingTimeInterval(-86_400)...start)
                .frame(height: 120)
            }
        }
    }

    private func loadHealth() async {
        defer { loading = false }
        loaded = false
        healthError = nil
        let selectedStart = start
        let lower = selectedStart.addingTimeInterval(-86_400)
        let comparison = (1...14).lazy.compactMap {
            Calendar.current.date(byAdding: .day, value: -$0, to: selectedStart)
        }.first { candidate in
            candidate <= lower && !journal.data.attacks.contains {
                journal.start(for: $0) < candidate && ($0.end ?? Date()) >= candidate.addingTimeInterval(-86_400)
            }
        }
        do {
            try await health.requestAccess()
            let pulseValues = try await health.points(isHRV: false, from: lower, to: selectedStart)
            let hrvValues = try await health.points(isHRV: true, from: lower, to: selectedStart)
            let sleepValue = try await health.sleepHours(from: lower, to: selectedStart)
            var comparisonValue: Double?
            if let comparison {
                comparisonValue = try await health.sleepHours(from: comparison.addingTimeInterval(-86_400),
                                                              to: comparison)
            }
            guard start == selectedStart else { return }
            pulse = pulseValues
            hrv = hrvValues
            sleep = sleepValue
            referenceSleep = comparisonValue
            referenceDate = comparison
            loaded = true
        } catch {
            healthError = "Kunde inte läsa Apple Hälsa. Kontrollera att Hälsa är tillgängligt på enheten."
        }
    }
}
