import Testing
import Foundation
@testable import CompanionCore

@Suite("Formatting")
struct FormattersTests {
    private let metric = Formatters(
        distanceUnit: .kilometres, weightUnit: .kilograms, locale: Locale(identifier: "en_GB")
    )
    private let imperial = Formatters(
        distanceUnit: .miles, weightUnit: .pounds, locale: Locale(identifier: "en_US")
    )

    /// Regression: Today showed "0.00 mi" for the day and "0 ft" for the week,
    /// which reads as two different measurements of the same nothing.
    @Test("Zero distance stays in the major unit")
    func zeroUsesMajorUnit() {
        #expect(metric.distance(0).contains("km"))
        #expect(imperial.distance(0).contains("mi"))
        #expect(metric.distance(0).contains("m ") == false)
    }

    @Test("Short distances use metres or feet")
    func shortDistancesUseShortUnit() {
        #expect(metric.distance(250).contains("m"))
        #expect(metric.distance(250).contains("km") == false)
        #expect(imperial.distance(50).contains("ft"))
    }

    @Test("Long distances use kilometres or miles")
    func longDistancesUseMajorUnit() {
        #expect(metric.distance(5_000).contains("km"))
        #expect(imperial.distance(5_000).contains("mi"))
    }

    @Test("Distance conversion is correct")
    func conversionIsCorrect() {
        // 5 km is about 3.11 miles.
        #expect(imperial.distance(5_000).hasPrefix("3.1"))
        #expect(metric.distance(5_000).hasPrefix("5"))
    }

    @Test("Duration is compact under an hour and includes hours above it")
    func durationFormatting() {
        #expect(metric.duration(0) == "0:00")
        #expect(metric.duration(65) == "1:05")
        #expect(metric.duration(3_661) == "1:01:01")
    }

    @Test("Spelled duration reads naturally for VoiceOver")
    func spelledDuration() {
        #expect(metric.spelledDuration(60) == "1 minute")
        #expect(metric.spelledDuration(120) == "2 minutes")
        #expect(metric.spelledDuration(3_600) == "1 hour")
        #expect(metric.spelledDuration(3_720) == "1 hour 2 minutes")
        #expect(metric.spelledDuration(0) == "0 minutes")
    }

    @Test("Pace is shown per kilometre or per mile")
    func paceFormatting() {
        // 1 m/s is 1000 s/km == 16:40 per km.
        let pace = metric.pace(metresPerSecond: 1.0)
        #expect(pace == "16:40 /km")
    }

    @Test("Implausibly slow pace is withheld rather than shown as nonsense")
    func implausiblePaceWithheld() {
        #expect(metric.pace(metresPerSecond: 0.01) == nil)
        #expect(metric.pace(metresPerSecond: 0) == nil)
        #expect(metric.pace(metresPerSecond: nil) == nil)
    }

    @Test("Speed is shown per hour")
    func speedFormatting() {
        // 1 m/s is 3.6 km/h.
        #expect(metric.speed(metresPerSecond: 1.0)?.contains("3.6") == true)
    }

    @Test("Walks read as speed and runs read as pace")
    func rateMatchesActivityType() {
        let walkRate = metric.rate(metresPerSecond: 1.4, activityType: .walk)
        let runRate = metric.rate(metresPerSecond: 1.4, activityType: .run)
        #expect(walkRate?.contains("km/h") == true)
        #expect(runRate?.contains("/km") == true)
    }

    @Test("Weight converts to the owner's preferred unit")
    func weightFormatting() {
        #expect(metric.weight(kilograms: 27).contains("27"))
        // 27 kg is about 59.5 lb.
        #expect(imperial.weight(kilograms: 27).hasPrefix("59"))
    }

    @Test("An estimated age is never presented as exact")
    func estimatedAgeIsQualified() {
        let exact = metric.age(.estimatedMonths(36))
        #expect(exact?.hasPrefix("About") == true)

        let known = metric.age(
            .dateOfBirth(Calendar.current.date(byAdding: .month, value: -10, to: Date())!)
        )
        #expect(known?.hasPrefix("About") == false)
        #expect(known?.contains("10") == true)
    }

    @Test("Unknown age has nothing to show")
    func unknownAge() {
        #expect(metric.age(.unknown) == nil)
    }

    @Test("Age switches from months to years at two years old")
    func ageUnits() {
        #expect(metric.age(.estimatedMonths(18))?.contains("month") == true)
        #expect(metric.age(.estimatedMonths(36))?.contains("year") == true)
    }
}

@Suite("Walk titles")
struct WalkTitleGeneratorTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func date(day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 2, day: day, hour: hour))!
    }

    @Test("Titles follow the time of day")
    func timeOfDay() {
        let generator = WalkTitleGenerator(calendar: calendar)
        // 2 February 2026 is a Monday.
        #expect(generator.title(for: date(day: 2, hour: 8)) == "Morning Walk")
        #expect(generator.title(for: date(day: 2, hour: 13)) == "Lunchtime Walk")
        #expect(generator.title(for: date(day: 2, hour: 15)) == "Afternoon Walk")
        #expect(generator.title(for: date(day: 2, hour: 19)) == "Evening Walk")
        #expect(generator.title(for: date(day: 2, hour: 23)) == "Night Walk")
    }

    @Test("A long weekend walk earns a warmer name")
    func weekendAdventure() {
        let generator = WalkTitleGenerator(calendar: calendar)
        // 7 February 2026 is a Saturday.
        #expect(generator.title(for: date(day: 7, hour: 12)) == "Weekend Adventure")
    }

    @Test("Activity type is reflected in the title")
    func activityType() {
        let generator = WalkTitleGenerator(calendar: calendar)
        #expect(generator.title(for: date(day: 2, hour: 8), activityType: .run) == "Morning Run")
        #expect(generator.title(for: date(day: 7, hour: 9), activityType: .hike) == "Weekend Hike")
    }
}
