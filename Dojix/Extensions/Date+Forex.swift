import Foundation

extension Date {
    /// Calendar configured for UTC
    private static let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }()

    /// UTC hour component
    var utcHour: Int {
        Self.utcCalendar.component(.hour, from: self)
    }

    /// Primary trading session based on UTC hour (used for trade tagging)
    var tradingSession: TradingSession {
        let h = utcHour
        if h >= 12 && h < 16 {
            return .nyOverlap
        } else if h >= 7 && h < 12 {
            return .london
        } else if h >= 0 && h < 7 {
            return .asian
        } else if h >= 16 && h < 21 {
            return .ny
        } else {
            return .late
        }
    }

    /// All currently active trading sessions (multiple during overlaps)
    /// Asian: 00:00-09:00, London: 07:00-16:00, NY: 12:00-21:00, Late: 21:00-00:00
    var activeTradingSessions: [TradingSession] {
        let h = utcHour
        var sessions: [TradingSession] = []
        if h >= 0 && h < 9 { sessions.append(.asian) }
        if h >= 7 && h < 16 { sessions.append(.london) }
        if h >= 12 && h < 21 { sessions.append(.ny) }
        if h >= 21 { sessions.append(.late) }
        return sessions.isEmpty ? [.late] : sessions
    }

    /// Short day-of-week string (Mon, Tue, etc.)
    var shortDayName: String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "EEE"
        return formatter.string(from: self)
    }

    /// Format for display in trade table
    var tradeDisplayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        formatter.timeZone = .current
        return formatter.string(from: self)
    }

    /// Parse SA CSV datetime format: "YYYY.MM.DD HH:MM:SS"
    static func fromSADateTime(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = Configuration.saDateTimeFormat
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: string)
    }

    /// Time until next session boundary
    var timeToNextSession: TimeInterval {
        let h = utcHour
        let nextBoundary: Int
        if h < 7 { nextBoundary = 7 }
        else if h < 12 { nextBoundary = 12 }
        else if h < 16 { nextBoundary = 16 }
        else if h < 21 { nextBoundary = 21 }
        else { nextBoundary = 24 + 0 } // next day Asian

        let hoursUntil = nextBoundary - h
        let minuteComponent = Self.utcCalendar.component(.minute, from: self)
        return TimeInterval(hoursUntil * 3600 - minuteComponent * 60)
    }
}
