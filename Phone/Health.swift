import Foundation
import HealthKit

struct HealthPoint: Identifiable {
    let id: UUID
    let date: Date
    let value: Double
}

@MainActor
final class Health {
    private let store = HKHealthStore()
    private let heart = HKQuantityType(.heartRate)
    private let hrv = HKQuantityType(.heartRateVariabilitySDNN)
    private let sleep = HKCategoryType(.sleepAnalysis)

    func requestAccess() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw CocoaError(.featureUnsupported)
        }
        try await store.requestAuthorization(toShare: [], read: [heart, hrv, sleep])
    }

    private func samples(_ type: HKSampleType, from start: Date, to end: Date) async throws -> [HKSample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) {
                _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples ?? []) }
            }
            store.execute(query)
        }
    }

    func points(isHRV: Bool, from start: Date, to end: Date) async throws -> [HealthPoint] {
        let type = isHRV ? hrv : heart
        let unit = isHRV ? HKUnit.secondUnit(with: .milli) : HKUnit.count().unitDivided(by: .minute())
        let values = try await samples(type, from: start, to: end)
        return values.compactMap { sample in
            guard let sample = sample as? HKQuantitySample else { return nil }
            return HealthPoint(id: sample.uuid, date: sample.startDate, value: sample.quantity.doubleValue(for: unit))
        }
    }

    func sleepHours(from start: Date, to end: Date) async throws -> Double? {
        let asleep = [HKCategoryValueSleepAnalysis.asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM]
            .map(\.rawValue)
        let values = try await samples(sleep, from: start, to: end)
        let intervals = values.compactMap { sample -> DateInterval? in
            guard let sample = sample as? HKCategorySample,
                  asleep.contains(sample.value) else { return nil }
            let lower = max(start, sample.startDate)
            let upper = min(end, sample.endDate)
            return lower < upper ? DateInterval(start: lower, end: upper) : nil
        }
        guard !intervals.isEmpty else { return nil }
        var total = 0.0
        var coveredUntil = start
        for interval in intervals {
            total += max(0, interval.end.timeIntervalSince(max(coveredUntil, interval.start)))
            coveredUntil = max(coveredUntil, interval.end)
        }
        return total / 3600
    }
}
