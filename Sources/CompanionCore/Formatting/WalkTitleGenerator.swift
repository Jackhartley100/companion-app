import Foundation

/// Suggests a default title for a finished walk based on when it happened.
///
/// The owner can always edit it; this exists so that saving a walk never
/// requires typing, and so activity history reads as a diary rather than a list
/// of "Activity 14".
public struct WalkTitleGenerator: Sendable {
    public let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func title(for date: Date, activityType: ActivityType = .walk) -> String {
        let hour = calendar.component(.hour, from: date)
        let isWeekend = calendar.isDateInWeekend(date)

        switch activityType {
        case .run:
            return "\(timeOfDay(hour: hour)) Run"
        case .hike:
            return isWeekend ? "Weekend Hike" : "\(timeOfDay(hour: hour)) Hike"
        case .walk:
            // A long weekend walk earns a warmer name than "Afternoon Walk".
            if isWeekend, (10...16).contains(hour) {
                return "Weekend Adventure"
            }
            return "\(timeOfDay(hour: hour)) Walk"
        }
    }

    private func timeOfDay(hour: Int) -> String {
        switch hour {
        case 5..<12: "Morning"
        case 12..<14: "Lunchtime"
        case 14..<17: "Afternoon"
        case 17..<21: "Evening"
        default: "Night"
        }
    }
}
