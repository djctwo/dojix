import Foundation

/// Input hygiene for imported trades.
///
/// Trade files come from many platforms and may be malformed or hostile
/// (e.g. "nan", "inf", an hour of 99, a 10,000-character symbol). Every trade
/// passes through `sanitizedForStorage()` before it is written to the database,
/// so analytics and charts never see values that could crash or distort them.
extension Trade {
    /// Largest magnitude accepted for pip/R/size style metrics
    static let metricLimit = 1_000_000_000.0
    /// Largest magnitude accepted for prices and money amounts (P&L included)
    static let moneyLimit = Decimal(1_000_000_000_000)
    /// Ten years, in minutes
    static let durationLimit = 10 * 366 * 24 * 60
    /// Largest position size accepted, in lots
    static let maximumLots = 1_000_000.0
    /// Smallest non-zero position size: one unit of currency (0.00001 standard lots, the
    /// smallest trade OANDA allows). Zero means "size unknown" and is kept as is.
    static let minimumLots = 0.000_01
    private static let symbolMaxLength = 32
    private static let commentMaxLength = 256

    private static let validDays: Set<String> = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    /// A copy of this trade with every field forced into a safe, finite range.
    func sanitizedForStorage() -> Trade {
        var t = self
        t.symbol = Self.clean(symbol, maxLength: Self.symbolMaxLength)
        t.comment = Self.clean(comment, maxLength: Self.commentMaxLength)
        t.lots = Self.lotSize(lots)
        t.openPrice = Self.money(openPrice)
        t.closePrice = Self.money(closePrice)
        t.sl = Self.money(sl)
        t.tp = Self.money(tp)
        t.netProfit = Self.money(netProfit)
        t.commission = Self.money(commission)
        t.swap = Self.money(swap)
        t.maePips = Self.metric(maePips)
        t.mfePips = Self.metric(mfePips)
        t.rMultiple = Self.metric(rMultiple)
        t.rangeSize = Self.metric(rangeSize)
        t.sweepDepth = Self.metric(sweepDepth)
        t.slDistPips = Self.metric(slDistPips)
        t.slippagePips = Self.metric(slippagePips)
        t.postClose15m = Self.metric(postClose15m)
        t.postClose30m = Self.metric(postClose30m)
        t.durationMin = min(max(durationMin, 0), Self.durationLimit)
        t.timeToMFEMin = min(max(timeToMFEMin, 0), Self.durationLimit)
        if !(0...23).contains(hour) {
            t.hour = openTime.utcHour
        }
        if !Self.validDays.contains(dayOfWeek) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE"
            t.dayOfWeek = formatter.string(from: openTime)
        }
        if closeTime < openTime {
            t.closeTime = openTime
        }
        return t
    }

    /// Field names whose values are outside what Dojix ever stores (non-finite or out of
    /// range numbers, control characters in the symbol, unsafe screenshot names). An
    /// imported file is cleaned by `sanitizedForStorage()`; a restored backup with any of
    /// these is refused, because Dojix itself never writes them.
    func storageViolations() -> [String] {
        var bad: [String] = []
        let hasControls = symbol.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
        if symbol.isEmpty || symbol.count > Self.symbolMaxLength || hasControls { bad.append("symbol") }
        if !lots.isFinite || lots < 0 || lots > Self.maximumLots || (lots > 0 && lots < Self.minimumLots) {
            bad.append("lots")
        }
        let money: [(String, Decimal)] = [
            ("openPrice", openPrice), ("closePrice", closePrice), ("sl", sl), ("tp", tp),
            ("netProfit", netProfit), ("commission", commission), ("swap", swap),
        ]
        for (name, value) in money where value.isNaN || abs(value) > Self.moneyLimit {
            bad.append(name)
        }
        let metrics: [(String, Double)] = [
            ("maePips", maePips), ("mfePips", mfePips), ("rMultiple", rMultiple),
            ("rangeSize", rangeSize), ("sweepDepth", sweepDepth), ("slDistPips", slDistPips),
            ("slippagePips", slippagePips), ("postClose15m", postClose15m), ("postClose30m", postClose30m),
        ]
        for (name, value) in metrics where !value.isFinite || abs(value) > Self.metricLimit {
            bad.append(name)
        }
        if !(0...Self.durationLimit).contains(durationMin) { bad.append("durationMin") }
        if !(0...Self.durationLimit).contains(timeToMFEMin) { bad.append("timeToMFEMin") }
        if !(0...23).contains(hour) { bad.append("hour") }
        if !Self.validDays.contains(dayOfWeek) { bad.append("dayOfWeek") }
        if !screenshotList.allSatisfy(ScreenshotManager.isValidFilename) { bad.append("screenshots") }
        return bad
    }

    /// A restored trade: `sanitizedForStorage()` plus control characters removed from the
    /// free-text fields (line breaks and tabs in notes are kept).
    func sanitizedForRestore() -> Trade {
        var t = sanitizedForStorage()
        t.notes = Self.stripControls(notes, keepingLineBreaks: true)
        t.tags = Self.stripControls(tags, keepingLineBreaks: false)
        t.emotion = Self.stripControls(emotion, keepingLineBreaks: false)
        t.checklistData = Self.stripControls(checklistData, keepingLineBreaks: false)
        t.screenshots = screenshotList.filter(ScreenshotManager.isValidFilename).joined(separator: ",")
        return t
    }

    static func stripControls(_ value: String, keepingLineBreaks: Bool) -> String {
        let kept = value.unicodeScalars.filter { scalar in
            if keepingLineBreaks, scalar == "\n" || scalar == "\t" { return true }
            return !CharacterSet.controlCharacters.contains(scalar)
        }
        return String(String.UnicodeScalarView(kept))
    }

    private static func lotSize(_ value: Double) -> Double {
        let size = min(abs(finite(value)), maximumLots)
        return size > 0 && size < minimumLots ? minimumLots : size
    }

    private static func finite(_ value: Double) -> Double {
        value.isFinite ? value : 0
    }

    private static func metric(_ value: Double) -> Double {
        min(max(finite(value), -metricLimit), metricLimit)
    }

    /// A money amount forced into Dojix's stored range (NaN becomes 0). Also used for
    /// amounts typed by hand (commission, swap), so a backup Dojix writes always restores.
    static func money(_ value: Decimal) -> Decimal {
        if value.isNaN { return 0 }
        return min(max(value, -moneyLimit), moneyLimit)
    }

    private static func clean(_ value: String, maxLength: Int) -> String {
        let scalars = value.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        return String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespaces).prefix(maxLength).description
    }
}
