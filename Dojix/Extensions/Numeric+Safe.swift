import Foundation

// MARK: - Trap-free numeric conversions
//
// `Int(someDouble)` crashes the app when the value is NaN, infinite or outside Int's range,
// and `+` crashes on Int overflow. Values in analytics can come from imported files, so
// conversions and sums use these instead.

extension Int {
    /// `value` rounded toward zero, clamped to Int's range; NaN becomes 0.
    init(saturating value: Double) {
        if value.isNaN {
            self = 0
        } else if value >= 9.223_372_036_854_775e18 {
            self = .max
        } else if value <= -9.223_372_036_854_775e18 {
            self = .min
        } else {
            self = Int(value)
        }
    }
}

extension Sequence where Element == Int {
    /// Sum that clamps at Int.max / Int.min instead of crashing on overflow.
    func saturatingSum() -> Int {
        reduce(0) { total, next in
            let (sum, overflow) = total.addingReportingOverflow(next)
            if overflow { return next > 0 ? .max : .min }
            return sum
        }
    }

    /// Average (rounded toward zero), 0 for an empty sequence; never overflows.
    func saturatingAverage() -> Int {
        var count = 0
        var total = 0.0
        for value in self {
            total += Double(value)
            count += 1
        }
        return count == 0 ? 0 : Int(saturating: total / Double(count))
    }
}
