import Foundation

public struct IORegBattery: Equatable {
    public let cycleCount: Int?
    public let designCapacity: Int?
    public let rawMaxCapacity: Int?
    public let rawCurrentCapacity: Int?
    public let voltageMV: Int?
    public let temperatureCentiC: Int?
    public let instantAmperageRaw: String?   // raw digits; overflows Int on discharge
    public let adapterName: String?
    public let adapterWatts: Int?
}

public func parseIORegBattery(_ raw: String) -> IORegBattery {
    func intVal(_ key: String) -> Int? {
        // matches:  "Key" = 123   or   "Key" = -123
        firstMatch(in: raw, pattern: "\"\(key)\"\\s*=\\s*(-?[0-9]+)").flatMap { Int($0) }
    }
    let name = firstMatch(in: raw, pattern: "\"AdapterDetails\"[\\s\\S]*?\"Name\"\\s*=\\s*\"([^\"]*)\"")
        ?? firstMatch(in: raw, pattern: "\"Name\"\\s*=\\s*\"([^\"]*)\"")
    let watts = (firstMatch(in: raw, pattern: "\"Watts\"\\s*=\\s*([0-9]+)")).flatMap { Int($0) }

    return IORegBattery(
        cycleCount: intVal("CycleCount"),
        designCapacity: intVal("DesignCapacity"),
        rawMaxCapacity: intVal("AppleRawMaxCapacity"),
        rawCurrentCapacity: intVal("AppleRawCurrentCapacity"),
        voltageMV: intVal("Voltage"),
        temperatureCentiC: intVal("Temperature"),
        instantAmperageRaw: firstMatch(in: raw, pattern: "\"InstantAmperage\"\\s*=\\s*(-?[0-9]+)"),
        adapterName: name,
        adapterWatts: watts
    )
}
