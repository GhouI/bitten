// Units and measurements: a value with a unit, converted through each
// dimension's base unit (metres, kilograms, seconds, kelvin, ...). The
// coefficients are Foundation's (a mile is 1609.34 metres). Plain Swift
// classes here (there is no NSUnit to bridge to).

open class UnitConverter: @unchecked Sendable {
  public init() {}
  open func baseUnitValue(fromValue value: Double) -> Double { return value }
  open func value(fromBaseUnitValue baseUnitValue: Double) -> Double { return baseUnitValue }
}

public final class UnitConverterLinear: UnitConverter, @unchecked Sendable {
  public let coefficient: Double
  public let constant: Double
  public init(coefficient: Double, constant: Double = 0) {
    self.coefficient = coefficient
    self.constant = constant
  }
  public override func baseUnitValue(fromValue value: Double) -> Double { return value * coefficient + constant }
  public override func value(fromBaseUnitValue baseUnitValue: Double) -> Double {
    return (baseUnitValue - constant) / coefficient
  }
}

open class Unit: Hashable, @unchecked Sendable {
  public let symbol: String
  public required init(symbol: String) { self.symbol = symbol }
  public static func == (a: Unit, b: Unit) -> Bool { return type(of: a) == type(of: b) && a.isEqual(b) }
  open func isEqual(_ other: Unit) -> Bool { return symbol == other.symbol }
  open func hash(into hasher: inout Hasher) { hasher.combine(symbol) }
}

open class Dimension: Unit, @unchecked Sendable {
  public let converter: UnitConverter
  public required init(symbol: String, converter: UnitConverter) {
    self.converter = converter
    super.init(symbol: symbol)
  }
  public required init(symbol: String) {
    self.converter = UnitConverterLinear(coefficient: 1)
    super.init(symbol: symbol)
  }
  /// The unit everything in this dimension converts through.
  open class func baseUnit() -> Self { fatalError("\(self) has no base unit") }
  open override func isEqual(_ other: Unit) -> Bool {
    guard let d = other as? Dimension, symbol == d.symbol else { return false }
    if let a = converter as? UnitConverterLinear, let b = d.converter as? UnitConverterLinear {
      return a.coefficient == b.coefficient && a.constant == b.constant
    }
    return converter === d.converter
  }
}

/// A unit of a dimension made from a symbol and a coefficient to its base.
private func linear<U: Dimension>(_ symbol: String, _ coefficient: Double, _ constant: Double = 0) -> U {
  return U(symbol: symbol, converter: UnitConverterLinear(coefficient: coefficient, constant: constant))
}

public final class UnitLength: Dimension, @unchecked Sendable {
  public override class func baseUnit() -> Self { return meters as! Self }
  public static let megameters: UnitLength = linear("Mm", 1e6)
  public static let kilometers: UnitLength = linear("km", 1000)
  public static let hectometers: UnitLength = linear("hm", 100)
  public static let decameters: UnitLength = linear("dam", 10)
  public static let meters: UnitLength = linear("m", 1)
  public static let decimeters: UnitLength = linear("dm", 0.1)
  public static let centimeters: UnitLength = linear("cm", 0.01)
  public static let millimeters: UnitLength = linear("mm", 0.001)
  public static let micrometers: UnitLength = linear("µm", 1e-6)
  public static let nanometers: UnitLength = linear("nm", 1e-9)
  public static let picometers: UnitLength = linear("pm", 1e-12)
  public static let inches: UnitLength = linear("in", 0.0254)
  public static let feet: UnitLength = linear("ft", 0.3048)
  public static let yards: UnitLength = linear("yd", 0.9144)
  public static let miles: UnitLength = linear("mi", 1609.34)
  public static let scandinavianMiles: UnitLength = linear("smi", 10000)
  public static let lightyears: UnitLength = linear("ly", 9.461e15)
  public static let nauticalMiles: UnitLength = linear("NM", 1852)
  public static let fathoms: UnitLength = linear("ftm", 1.8288)
  public static let furlongs: UnitLength = linear("fur", 201.168)
  public static let astronomicalUnits: UnitLength = linear("ua", 1.496e11)
  public static let parsecs: UnitLength = linear("pc", 3.086e16)
}

public final class UnitMass: Dimension, @unchecked Sendable {
  public override class func baseUnit() -> Self { return kilograms as! Self }
  public static let kilograms: UnitMass = linear("kg", 1)
  public static let grams: UnitMass = linear("g", 0.001)
  public static let decigrams: UnitMass = linear("dg", 0.0001)
  public static let centigrams: UnitMass = linear("cg", 0.00001)
  public static let milligrams: UnitMass = linear("mg", 0.000001)
  public static let micrograms: UnitMass = linear("µg", 1e-9)
  public static let nanograms: UnitMass = linear("ng", 1e-12)
  public static let picograms: UnitMass = linear("pg", 1e-15)
  public static let ounces: UnitMass = linear("oz", 0.0283495)
  public static let pounds: UnitMass = linear("lb", 0.453592)
  public static let stones: UnitMass = linear("st", 0.157473)
  public static let metricTons: UnitMass = linear("t", 1000)
  public static let shortTons: UnitMass = linear("ton", 907.185)
  public static let carats: UnitMass = linear("ct", 0.0002)
  public static let ouncesTroy: UnitMass = linear("oz t", 0.03110348)
  public static let slugs: UnitMass = linear("slug", 14.5939)
}

public final class UnitDuration: Dimension, @unchecked Sendable {
  public override class func baseUnit() -> Self { return seconds as! Self }
  public static let hours: UnitDuration = linear("hr", 3600)
  public static let minutes: UnitDuration = linear("min", 60)
  public static let seconds: UnitDuration = linear("s", 1)
  public static let milliseconds: UnitDuration = linear("ms", 0.001)
  public static let microseconds: UnitDuration = linear("µs", 0.000001)
  public static let nanoseconds: UnitDuration = linear("ns", 1e-9)
  public static let picoseconds: UnitDuration = linear("ps", 1e-12)
}

public final class UnitTemperature: Dimension, @unchecked Sendable {
  public override class func baseUnit() -> Self { return kelvin as! Self }
  public static let kelvin: UnitTemperature = linear("K", 1)
  public static let celsius: UnitTemperature = linear("°C", 1, 273.15)
  public static let fahrenheit: UnitTemperature = linear("°F", 0.55555555555556, 255.37222222222427)
}

public final class UnitSpeed: Dimension, @unchecked Sendable {
  public override class func baseUnit() -> Self { return metersPerSecond as! Self }
  public static let metersPerSecond: UnitSpeed = linear("m/s", 1)
  public static let kilometersPerHour: UnitSpeed = linear("km/h", 0.277778)
  public static let milesPerHour: UnitSpeed = linear("mph", 0.44704)
  public static let knots: UnitSpeed = linear("kn", 0.514444)
}

public final class UnitVolume: Dimension, @unchecked Sendable {
  public override class func baseUnit() -> Self { return liters as! Self }
  public static let liters: UnitVolume = linear("L", 1)
  public static let milliliters: UnitVolume = linear("mL", 0.001)
  public static let centiliters: UnitVolume = linear("cL", 0.01)
  public static let deciliters: UnitVolume = linear("dL", 0.1)
  public static let kiloliters: UnitVolume = linear("kL", 1000)
  public static let cubicMeters: UnitVolume = linear("m³", 1000)
  public static let cubicCentimeters: UnitVolume = linear("cm³", 0.001)
  public static let cubicInches: UnitVolume = linear("in³", 0.0163871)
  public static let cubicFeet: UnitVolume = linear("ft³", 28.3168)
  public static let gallons: UnitVolume = linear("gal", 3.78541)
  public static let quarts: UnitVolume = linear("qt", 0.946353)
  public static let pints: UnitVolume = linear("pt", 0.473176)
  public static let cups: UnitVolume = linear("cup", 0.24)
  public static let fluidOunces: UnitVolume = linear("fl oz", 0.0295735)
  public static let tablespoons: UnitVolume = linear("tbsp", 0.0147868)
  public static let teaspoons: UnitVolume = linear("tsp", 0.00492892)
}

public final class UnitArea: Dimension, @unchecked Sendable {
  public override class func baseUnit() -> Self { return squareMeters as! Self }
  public static let squareMeters: UnitArea = linear("m²", 1)
  public static let squareKilometers: UnitArea = linear("km²", 1e6)
  public static let squareCentimeters: UnitArea = linear("cm²", 0.0001)
  public static let squareMillimeters: UnitArea = linear("mm²", 0.000001)
  public static let squareInches: UnitArea = linear("in²", 0.00064516)
  public static let squareFeet: UnitArea = linear("ft²", 0.092903)
  public static let squareYards: UnitArea = linear("yd²", 0.836127)
  public static let squareMiles: UnitArea = linear("mi²", 2.59e6)
  public static let acres: UnitArea = linear("ac", 4046.86)
  public static let hectares: UnitArea = linear("ha", 10000)
}

public final class UnitAngle: Dimension, @unchecked Sendable {
  public override class func baseUnit() -> Self { return degrees as! Self }
  public static let degrees: UnitAngle = linear("°", 1)
  public static let arcMinutes: UnitAngle = linear("ʹ", 0.016667)
  public static let arcSeconds: UnitAngle = linear("ʺ", 0.00027778)
  public static let radians: UnitAngle = linear("rad", 57.2958)
  public static let gradians: UnitAngle = linear("grad", 0.9)
  public static let revolutions: UnitAngle = linear("rev", 360)
}

public final class UnitInformationStorage: Dimension, @unchecked Sendable {
  public override class func baseUnit() -> Self { return bits as! Self }
  public static let bits: UnitInformationStorage = linear("bit", 1)
  public static let nibbles: UnitInformationStorage = linear("nibble", 4)
  public static let bytes: UnitInformationStorage = linear("B", 8)
  public static let kilobytes: UnitInformationStorage = linear("kB", 8e3)
  public static let megabytes: UnitInformationStorage = linear("MB", 8e6)
  public static let gigabytes: UnitInformationStorage = linear("GB", 8e9)
  public static let terabytes: UnitInformationStorage = linear("TB", 8e12)
  public static let kibibytes: UnitInformationStorage = linear("KiB", 8 * 1024)
  public static let mebibytes: UnitInformationStorage = linear("MiB", 8 * 1_048_576)
  public static let gibibytes: UnitInformationStorage = linear("GiB", 8 * 1_073_741_824)
  public static let kilobits: UnitInformationStorage = linear("kb", 1e3)
  public static let megabits: UnitInformationStorage = linear("Mb", 1e6)
  public static let gigabits: UnitInformationStorage = linear("Gb", 1e9)
}

public final class UnitEnergy: Dimension, @unchecked Sendable {
  public override class func baseUnit() -> Self { return joules as! Self }
  public static let kilojoules: UnitEnergy = linear("kJ", 1000)
  public static let joules: UnitEnergy = linear("J", 1)
  public static let kilocalories: UnitEnergy = linear("kCal", 4184)
  public static let calories: UnitEnergy = linear("cal", 4.184)
  public static let kilowattHours: UnitEnergy = linear("kWh", 3_600_000)
}

public final class UnitPressure: Dimension, @unchecked Sendable {
  public override class func baseUnit() -> Self { return newtonsPerMetersSquared as! Self }
  public static let newtonsPerMetersSquared: UnitPressure = linear("N/m²", 1)
  public static let gigapascals: UnitPressure = linear("GPa", 1e9)
  public static let megapascals: UnitPressure = linear("MPa", 1e6)
  public static let kilopascals: UnitPressure = linear("kPa", 1000)
  public static let hectopascals: UnitPressure = linear("hPa", 100)
  public static let inchesOfMercury: UnitPressure = linear("inHg", 3386.39)
  public static let bars: UnitPressure = linear("bar", 100_000)
  public static let millibars: UnitPressure = linear("mbar", 100)
  public static let millimetersOfMercury: UnitPressure = linear("mmHg", 133.322)
  public static let poundsForcePerSquareInch: UnitPressure = linear("psi", 6894.76)
}

public final class UnitFrequency: Dimension, @unchecked Sendable {
  public override class func baseUnit() -> Self { return hertz as! Self }
  public static let terahertz: UnitFrequency = linear("THz", 1e12)
  public static let gigahertz: UnitFrequency = linear("GHz", 1e9)
  public static let megahertz: UnitFrequency = linear("MHz", 1e6)
  public static let kilohertz: UnitFrequency = linear("kHz", 1e3)
  public static let hertz: UnitFrequency = linear("Hz", 1)
  public static let millihertz: UnitFrequency = linear("mHz", 1e-3)
}

public final class UnitPower: Dimension, @unchecked Sendable {
  public override class func baseUnit() -> Self { return watts as! Self }
  public static let gigawatts: UnitPower = linear("GW", 1e9)
  public static let megawatts: UnitPower = linear("MW", 1e6)
  public static let kilowatts: UnitPower = linear("kW", 1000)
  public static let watts: UnitPower = linear("W", 1)
  public static let milliwatts: UnitPower = linear("mW", 0.001)
  public static let horsepower: UnitPower = linear("hp", 745.7)
}

public struct Measurement<UnitType: Unit>: CustomStringConvertible, CustomDebugStringConvertible {
  public let unit: UnitType
  public var value: Double
  public init(value: Double, unit: UnitType) {
    self.value = value
    self.unit = unit
  }
  public var description: String { return "\(value) \(unit.symbol)" }
  public var debugDescription: String { return description }
}

extension Measurement where UnitType: Dimension {
  public func converted(to otherUnit: UnitType) -> Measurement<UnitType> {
    if unit.isEqual(otherUnit) { return Measurement(value: value, unit: otherUnit) }
    let base = unit.converter.baseUnitValue(fromValue: value)
    return Measurement(value: otherUnit.converter.value(fromBaseUnitValue: base), unit: otherUnit)
  }
  public mutating func convert(to otherUnit: UnitType) { self = converted(to: otherUnit) }
  internal var _baseValue: Double { return unit.converter.baseUnitValue(fromValue: value) }

  public static func + (a: Measurement, b: Measurement) -> Measurement {
    if a.unit.isEqual(b.unit) { return Measurement(value: a.value + b.value, unit: a.unit) }
    let base = UnitType.baseUnit()
    return Measurement(value: a._baseValue + b._baseValue, unit: base)
  }
  public static func - (a: Measurement, b: Measurement) -> Measurement {
    if a.unit.isEqual(b.unit) { return Measurement(value: a.value - b.value, unit: a.unit) }
    let base = UnitType.baseUnit()
    return Measurement(value: a._baseValue - b._baseValue, unit: base)
  }
}

extension Measurement {
  public static func * (m: Measurement, k: Double) -> Measurement { return Measurement(value: m.value * k, unit: m.unit) }
  public static func * (k: Double, m: Measurement) -> Measurement { return Measurement(value: m.value * k, unit: m.unit) }
  public static func / (m: Measurement, k: Double) -> Measurement { return Measurement(value: m.value / k, unit: m.unit) }
}

extension Measurement: Equatable {
  public static func == (a: Measurement, b: Measurement) -> Bool {
    if a.unit.isEqual(b.unit) { return a.value == b.value }
    if let da = a.unit as? Dimension, let db = b.unit as? Dimension, type(of: da) == type(of: db) {
      return da.converter.baseUnitValue(fromValue: a.value) == db.converter.baseUnitValue(fromValue: b.value)
    }
    return false
  }
}

extension Measurement: Comparable where UnitType: Dimension {
  public static func < (a: Measurement, b: Measurement) -> Bool {
    if a.unit.isEqual(b.unit) { return a.value < b.value }
    return a._baseValue < b._baseValue
  }
}

extension Measurement: Hashable {
  public func hash(into hasher: inout Hasher) {
    if let d = unit as? Dimension { hasher.combine(d.converter.baseUnitValue(fromValue: value)) } else { hasher.combine(value) }
  }
}

extension Measurement: Sendable where UnitType: Sendable {}

extension Measurement: Codable {
  private enum CodingKeys: String, CodingKey { case value, unit }
  private enum UnitKeys: String, CodingKey { case symbol, converter }
  private enum LinearKeys: String, CodingKey { case coefficient, constant }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let value = try c.decode(Double.self, forKey: .value)
    let u = try c.nestedContainer(keyedBy: UnitKeys.self, forKey: .unit)
    let symbol = try u.decode(String.self, forKey: .symbol)
    if let dim = UnitType.self as? Dimension.Type {
      let l = try u.nestedContainer(keyedBy: LinearKeys.self, forKey: .converter)
      let conv = UnitConverterLinear(coefficient: try l.decode(Double.self, forKey: .coefficient),
                                     constant: try l.decode(Double.self, forKey: .constant))
      self.init(value: value, unit: dim.init(symbol: symbol, converter: conv) as! UnitType)
    } else {
      self.init(value: value, unit: UnitType(symbol: symbol))
    }
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(value, forKey: .value)
    var u = c.nestedContainer(keyedBy: UnitKeys.self, forKey: .unit)
    try u.encode(unit.symbol, forKey: .symbol)
    if let d = unit as? Dimension, let l = d.converter as? UnitConverterLinear {
      var lc = u.nestedContainer(keyedBy: LinearKeys.self, forKey: .converter)
      try lc.encode(l.coefficient, forKey: .coefficient)
      try lc.encode(l.constant, forKey: .constant)
    }
  }
}
