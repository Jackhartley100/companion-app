import SwiftUI
import CompanionCore

private struct FormattersKey: EnvironmentKey {
    static let defaultValue = Formatters()
}

private struct CompanionCalendarKey: EnvironmentKey {
    static let defaultValue = Calendar.current
}

public extension EnvironmentValues {
    /// Locale- and preference-aware formatting, injected once at the root so no
    /// view has to know the owner's unit choices to display a distance.
    var formatters: Formatters {
        get { self[FormattersKey.self] }
        set { self[FormattersKey.self] = newValue }
    }

    /// The calendar with the owner's week-start preference applied. Views must
    /// use this rather than `Calendar.current`, or weeks on screen will not
    /// match weeks in the statistics.
    var companionCalendar: Calendar {
        get { self[CompanionCalendarKey.self] }
        set { self[CompanionCalendarKey.self] = newValue }
    }
}
