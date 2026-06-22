import Foundation

public func healthPercent(rawMax: Int?, design: Int?) -> Int? {
    guard let m = rawMax, let d = design, d > 0 else { return nil }
    return min(100, m * 100 / d)
}

public func humanize(_ hmm: String) -> String {
    let parts = hmm.split(separator: ":")
    let h = parts.count > 0 ? Int(parts[0]) ?? 0 : 0
    let m = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
    if h > 0 && m > 0 { return "\(h) hr \(m) min" }
    if h > 0 { return "\(h) hr" }
    return "\(m) min"
}

public func celsius(fromCentiC c: Int) -> Int { c / 100 }
public func fahrenheit(fromCentiC c: Int) -> Int { (c / 100) * 9 / 5 + 32 }

/// Magnitude (mA) of InstantAmperage. Discharge is a large unsigned value
/// (two's complement of a negative); >= 11 digits means negative.
public func dischargeMagnitude(instantAmperageRaw raw: String) -> Int? {
    let s = raw.trimmingCharacters(in: .whitespaces)
    if s.count >= 11, let u = UInt64(s) {
        let mag = UInt64(18446744073709551615) - u + 1   // 2^64 - u
        return Int(mag)
    }
    return Int(s)
}

/// Stop-gap ETA (minutes) right after unplug, before macOS has its own estimate:
/// measured-draw projection capped by a nominal ~12 W. nil if no estimate.
public func etaStopgapMinutes(rawCurrent: Int, voltageMV: Int?, instantAmperageRaw: String?) -> Int? {
    var nominal: Int? = nil
    if let v = voltageMV, v > 0 { nominal = rawCurrent * 60 / (12_000_000 / v) }  // ~12 W cap
    var measured: Int? = nil
    if let raw = instantAmperageRaw, let mag = dischargeMagnitude(instantAmperageRaw: raw), mag > 0 {
        measured = rawCurrent * 60 / mag
    }
    switch (measured, nominal) {
    case let (m?, n?): return min(m, n)
    case let (m?, nil): return m
    case let (nil, n?): return n
    default: return nil
    }
}
