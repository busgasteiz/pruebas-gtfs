import Foundation

// ============================================================
// MARK: - Lector de formato Protocol Buffers (wire format)
// ============================================================

struct ProtoReader {
    let data: Data
    var position: Int = 0
    init(data: Data) { self.data = data }

    mutating func readVarint() -> UInt64? {
        var result: UInt64 = 0; var shift: UInt64 = 0
        while position < data.count {
            let byte = data[position]; position += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7; if shift >= 64 { return nil }
        }
        return nil
    }

    mutating func readLengthDelimited() -> Data? {
        guard let length = readVarint() else { return nil }
        guard length <= UInt64(Int.max) else { return nil }
        let len = Int(length)
        guard position + len <= data.count else { return nil }
        let result = Data(data[position..<(position + len)])
        position += len; return result
    }

    mutating func readTag() -> (field: Int, wire: Int)? {
        guard let tag = readVarint() else { return nil }
        return (Int(truncatingIfNeeded: tag >> 3), Int(truncatingIfNeeded: tag & 0x7))
    }

    mutating func skip(wire: Int) {
        switch wire {
        case 0: _ = readVarint()
        case 1: position = min(position + 8, data.count)
        case 2: _ = readLengthDelimited()
        case 5: position = min(position + 4, data.count)
        default: position = data.count
        }
    }
    var hasMore: Bool { position < data.count }
}

// ============================================================
// MARK: - Estructuras GTFS-RT
// ============================================================

struct FeedMessage   { var header: FeedHeader?; var entities: [FeedEntity] = [] }
struct FeedHeader    { var version = ""; var incrementality = 0; var timestamp: UInt64 = 0 }
struct FeedEntity    { var id = ""; var isDeleted = false; var tripUpdate: TripUpdate? }

struct TripUpdate {
    var trip: TripDescriptor?; var vehicle: VehicleDescriptor?
    var stopTimeUpdates: [StopTimeUpdate] = []; var timestamp: UInt64 = 0; var delay: Int32 = 0
}
struct TripDescriptor {
    var tripId = ""; var startTime = ""; var startDate = ""
    var scheduleRelationship = 0; var routeId = ""; var directionId: UInt32 = 0
}
struct VehicleDescriptor { var id = ""; var label = ""; var licensePlate = "" }
struct StopTimeUpdate {
    var stopSequence: UInt32 = 0; var arrival: StopTimeEvent?
    var departure: StopTimeEvent?; var stopId = ""; var scheduleRelationship = 0
}
struct StopTimeEvent { var delay: Int32 = 0; var time: Int64 = 0; var uncertainty: Int32 = 0 }

// ============================================================
// MARK: - Parsers protobuf
// ============================================================

func str(_ d: Data) -> String { String(data: d, encoding: .utf8) ?? "?" }

func parseFeedMessage(_ data: Data) -> FeedMessage {
    var r = ProtoReader(data: data); var m = FeedMessage()
    while r.hasMore { guard let t = r.readTag() else { break }
        switch t.field {
        case 1: if let d = r.readLengthDelimited() { m.header = parseFeedHeader(d) }
        case 2: if let d = r.readLengthDelimited() { m.entities.append(parseFeedEntity(d)) }
        default: r.skip(wire: t.wire) } }
    return m
}
func parseFeedHeader(_ data: Data) -> FeedHeader {
    var r = ProtoReader(data: data); var h = FeedHeader()
    while r.hasMore { guard let t = r.readTag() else { break }
        switch t.field {
        case 1: if let d = r.readLengthDelimited() { h.version = str(d) }
        case 2: if let v = r.readVarint() { h.incrementality = Int(truncatingIfNeeded: v) }
        case 3: if let v = r.readVarint() { h.timestamp = v }
        default: r.skip(wire: t.wire) } }
    return h
}
func parseFeedEntity(_ data: Data) -> FeedEntity {
    var r = ProtoReader(data: data); var e = FeedEntity()
    while r.hasMore { guard let t = r.readTag() else { break }
        switch t.field {
        case 1: if let d = r.readLengthDelimited() { e.id = str(d) }
        case 2: if let v = r.readVarint() { e.isDeleted = v != 0 }
        case 3: if let d = r.readLengthDelimited() { e.tripUpdate = parseTripUpdate(d) }
        default: r.skip(wire: t.wire) } }
    return e
}
func parseTripUpdate(_ data: Data) -> TripUpdate {
    var r = ProtoReader(data: data); var tu = TripUpdate()
    while r.hasMore { guard let t = r.readTag() else { break }
        switch t.field {
        case 1: if let d = r.readLengthDelimited() { tu.trip = parseTripDescriptor(d) }
        case 2: if let d = r.readLengthDelimited() { tu.stopTimeUpdates.append(parseStopTimeUpdate(d)) }
        case 3: if let d = r.readLengthDelimited() { tu.vehicle = parseVehicleDescriptor(d) }
        case 4: if let v = r.readVarint() { tu.timestamp = v }
        case 5: if let v = r.readVarint() { tu.delay = Int32(truncatingIfNeeded: Int64(bitPattern: v)) }
        default: r.skip(wire: t.wire) } }
    return tu
}
func parseTripDescriptor(_ data: Data) -> TripDescriptor {
    var r = ProtoReader(data: data); var td = TripDescriptor()
    while r.hasMore { guard let t = r.readTag() else { break }
        switch t.field {
        case 1: if let d = r.readLengthDelimited() { td.tripId = str(d) }
        case 2: if let d = r.readLengthDelimited() { td.startTime = str(d) }
        case 3: if let d = r.readLengthDelimited() { td.startDate = str(d) }
        case 4: if let v = r.readVarint() { td.scheduleRelationship = Int(truncatingIfNeeded: v) }
        case 5: if let d = r.readLengthDelimited() { td.routeId = str(d) }
        case 6: if let v = r.readVarint() { td.directionId = UInt32(truncatingIfNeeded: v) }
        default: r.skip(wire: t.wire) } }
    return td
}
func parseVehicleDescriptor(_ data: Data) -> VehicleDescriptor {
    var r = ProtoReader(data: data); var vd = VehicleDescriptor()
    while r.hasMore { guard let t = r.readTag() else { break }
        switch t.field {
        case 1: if let d = r.readLengthDelimited() { vd.id = str(d) }
        case 2: if let d = r.readLengthDelimited() { vd.label = str(d) }
        case 3: if let d = r.readLengthDelimited() { vd.licensePlate = str(d) }
        default: r.skip(wire: t.wire) } }
    return vd
}
func parseStopTimeUpdate(_ data: Data) -> StopTimeUpdate {
    var r = ProtoReader(data: data); var stu = StopTimeUpdate()
    while r.hasMore { guard let t = r.readTag() else { break }
        switch t.field {
        case 1: if let v = r.readVarint() { stu.stopSequence = UInt32(truncatingIfNeeded: v) }
        case 2: if let d = r.readLengthDelimited() { stu.arrival = parseStopTimeEvent(d) }
        case 3: if let d = r.readLengthDelimited() { stu.departure = parseStopTimeEvent(d) }
        case 4: if let d = r.readLengthDelimited() { stu.stopId = str(d) }
        case 5: if let v = r.readVarint() { stu.scheduleRelationship = Int(truncatingIfNeeded: v) }
        default: r.skip(wire: t.wire) } }
    return stu
}
func parseStopTimeEvent(_ data: Data) -> StopTimeEvent {
    var r = ProtoReader(data: data); var ste = StopTimeEvent()
    while r.hasMore { guard let t = r.readTag() else { break }
        switch t.field {
        case 1: if let v = r.readVarint() { ste.delay = Int32(truncatingIfNeeded: Int64(bitPattern: v)) }
        case 2: if let v = r.readVarint() { ste.time = Int64(bitPattern: v) }
        case 3: if let v = r.readVarint() { ste.uncertainty = Int32(truncatingIfNeeded: Int64(bitPattern: v)) }
        default: r.skip(wire: t.wire) } }
    return ste
}

// ============================================================
// MARK: - Datos GTFS estáticos
// ============================================================

struct RouteInfo {
    let shortName: String; let longName: String
    let color: String; let desc: String
}
struct GTFSTripInfo {
    let routeId: String; let headsign: String; let directionId: Int
}
struct StopInfo {
    let name: String; let lat: Double; let lon: Double
}
struct StopSchedule {
    let arrivalSecs: Int; let departureSecs: Int
}
struct GTFSData {
    var routes:    [String: RouteInfo]           = [:]
    var trips:     [String: GTFSTripInfo]        = [:]
    var stops:     [String: StopInfo]            = [:]
    var stopTimes: [String: [Int: StopSchedule]] = [:]
}

// ============================================================
// MARK: - Cargador CSV / GTFS
// ============================================================

func splitCSV(_ line: String) -> [String] {
    var fields: [String] = []; var current = ""; var inQ = false
    for c in line {
        if c == "\"" { inQ.toggle() }
        else if c == "," && !inQ { fields.append(current); current = "" }
        else { current.append(c) }
    }
    fields.append(current); return fields
}

func loadGTFS(folder: String) -> GTFSData {
    var g = GTFSData()

    func idx(_ headers: [String], _ name: String) -> Int? { headers.firstIndex(of: name) }
    func get(_ row: [String], _ i: Int?) -> String {
        guard let i = i, i < row.count else { return "" }; return row[i]
    }
    func parseSecs(_ s: String) -> Int {
        let p = s.split(separator: ":").compactMap { Int($0) }
        guard p.count == 3 else { return 0 }; return p[0]*3600 + p[1]*60 + p[2]
    }

    // routes.txt
    if let raw = try? String(contentsOfFile: "\(folder)/routes.txt", encoding: .utf8) {
        var lines = raw.components(separatedBy: "\n")
        let h = splitCSV(lines.removeFirst())
        let iId = idx(h,"route_id"); let iSn = idx(h,"route_short_name")
        let iLn = idx(h,"route_long_name"); let iCo = idx(h,"route_color"); let iDs = idx(h,"route_desc")
        for ln in lines { let t = ln.trimmingCharacters(in:.whitespacesAndNewlines); guard !t.isEmpty else{continue}
            let r = splitCSV(t); let id = get(r,iId)
            g.routes[id] = RouteInfo(shortName:get(r,iSn), longName:get(r,iLn), color:get(r,iCo), desc:get(r,iDs)) }
    }

    // trips.txt
    if let raw = try? String(contentsOfFile: "\(folder)/trips.txt", encoding: .utf8) {
        var lines = raw.components(separatedBy: "\n")
        let h = splitCSV(lines.removeFirst())
        let iId = idx(h,"trip_id"); let iRt = idx(h,"route_id")
        let iHs = idx(h,"trip_headsign"); let iDr = idx(h,"direction_id")
        for ln in lines { let t = ln.trimmingCharacters(in:.whitespacesAndNewlines); guard !t.isEmpty else{continue}
            let r = splitCSV(t); let id = get(r,iId)
            g.trips[id] = GTFSTripInfo(routeId: get(r,iRt), headsign: get(r,iHs), directionId: Int(get(r,iDr)) ?? 0) }
    }

    // stops.txt
    if let raw = try? String(contentsOfFile: "\(folder)/stops.txt", encoding: .utf8) {
        var lines = raw.components(separatedBy: "\n")
        let h = splitCSV(lines.removeFirst())
        let iId = idx(h,"stop_id"); let iNm = idx(h,"stop_name")
        let iLat = idx(h,"stop_lat"); let iLon = idx(h,"stop_lon")
        for ln in lines { let t = ln.trimmingCharacters(in:.whitespacesAndNewlines); guard !t.isEmpty else{continue}
            let r = splitCSV(t); let id = get(r,iId)
            g.stops[id] = StopInfo(name: get(r,iNm), lat: Double(get(r,iLat)) ?? 0.0, lon: Double(get(r,iLon)) ?? 0.0) }
    }

    // stop_times.txt
    if let raw = try? String(contentsOfFile: "\(folder)/stop_times.txt", encoding: .utf8) {
        var lines = raw.components(separatedBy: "\n")
        let h = splitCSV(lines.removeFirst())
        let iTr = idx(h,"trip_id"); let iSq = idx(h,"stop_sequence")
        let iAr = idx(h,"arrival_time"); let iDp = idx(h,"departure_time")
        for ln in lines { let t = ln.trimmingCharacters(in:.whitespacesAndNewlines); guard !t.isEmpty else{continue}
            let r = splitCSV(t)
            let tid = get(r,iTr); let seq = Int(get(r,iSq)) ?? 0
            if g.stopTimes[tid] == nil { g.stopTimes[tid] = [:] }
            g.stopTimes[tid]![seq] = StopSchedule(arrivalSecs:parseSecs(get(r,iAr)), departureSecs:parseSecs(get(r,iDp))) }
    }

    return g
}

// ============================================================
// MARK: - Utilidades de tiempo
// ============================================================

let madridTZ = TimeZone(identifier: "Europe/Madrid")!

func toDate(startDate: String, secondsFromMidnight: Int, delaySecs: Int32 = 0) -> Date? {
    let fmt = DateFormatter(); fmt.dateFormat = "yyyyMMdd"; fmt.timeZone = madridTZ
    guard let base = fmt.date(from: startDate) else { return nil }
    return base.addingTimeInterval(TimeInterval(secondsFromMidnight) + TimeInterval(delaySecs))
}

func formatTime(_ date: Date) -> String {
    let fmt = DateFormatter(); fmt.dateFormat = "HH:mm:ss"; fmt.timeZone = madridTZ
    return fmt.string(from: date)
}

func formatTS(_ ts: UInt64) -> String {
    guard ts > 0 else { return "—" }
    let fmt = DateFormatter(); fmt.dateStyle = .medium; fmt.timeStyle = .medium
    fmt.locale = Locale(identifier: "es_ES"); fmt.timeZone = madridTZ
    return fmt.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
}

// ============================================================
// MARK: - Helpers de presentación
// ============================================================

func col(_ s: String, _ w: Int) -> String {
    s.count >= w ? String(s.prefix(w)) : s + String(repeating: " ", count: w - s.count)
}
func fmtDelay(_ d: Int32) -> String {
    if d == 0 { return "  a tiempo" }
    let sign = d > 0 ? "+" : ""; let a = Swift.abs(Int(d))
    return String(format: "%@%ds (%dm%02ds)", sign, d, a/60, a%60)
}
func colorBlock(_ hex: String) -> String {
    switch hex.lowercased() {
    case "ffdd00": return "🟡"; case "00a54f": return "🟢"
    case "44c7f4": return "🔵"; case "ed1c24": return "🔴"
    case "ff8000": return "🟠"; case "ffffff": return "⚪"
    default:       return "⬜"
    }
}
let schedNames = ["PROGRAMADO","OMITIDO","SIN DATOS","NO PROGRAMADO"]
func schedName(_ v: Int) -> String { v < schedNames.count ? schedNames[v] : "\(v)" }
let incNames = ["DATASET_COMPLETO","DIFERENCIAL"]
func incName(_ v: Int) -> String { v < incNames.count ? incNames[v] : "\(v)" }
func line(_ c: Character = "─", _ n: Int = 70) -> String { String(repeating: c, count: n) }

// ============================================================
// MARK: - Main
// ============================================================

let pbPath     = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./tripUpdates.pb"
let gtfsFolder = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "./GTFS_Data"

guard let rawData = FileManager.default.contents(atPath: pbPath) else {
    fputs("❌ No se pudo leer: \(pbPath)\n", stderr); exit(1)
}

print("⏳ Cargando datos GTFS estáticos desde \(gtfsFolder) …")
let gtfs = loadGTFS(folder: gtfsFolder)
let totalSchedules = gtfs.stopTimes.values.reduce(0) { $0 + $1.count }
print("   ✔ \(gtfs.routes.count) rutas · \(gtfs.trips.count) viajes · \(gtfs.stops.count) paradas · \(totalSchedules) horarios programados\n")

let feed = parseFeedMessage(rawData)

print(line("═"))
print("📄 Archivo  : \(pbPath)")
print("📦 Tamaño   : \(rawData.count) bytes")
print("🔍 Formato  : GTFS-RT (Protocol Buffers) — TripUpdates Feed")
print(line("═"))

if let h = feed.header {
    print("\n📋 ENCABEZADO DEL FEED")
    print("   Versión GTFS-RT : \(h.version)")
    print("   Timestamp       : \(formatTS(h.timestamp))")
    print("   Incrementalidad : \(incName(h.incrementality))")
}

let entities = feed.entities
print("\n\(line())")
print("🚌 ACTUALIZACIONES DE VIAJE — \(entities.count) entidades")
print(line())

for (idx, entity) in entities.enumerated() {
    guard let tu = entity.tripUpdate else { continue }
    let trip = tu.trip ?? TripDescriptor()

    // Enriquecimiento GTFS
    let routeInfo = gtfs.routes[trip.routeId]
    let tripInfo  = gtfs.trips[trip.tripId]
    let icon      = routeInfo.map { colorBlock($0.color) } ?? "🚌"
    let routeName = routeInfo.map { "\($0.shortName) — \($0.longName)" } ?? "Ruta \(trip.routeId)"
    let headsign  = tripInfo?.headsign ?? "—"
    let vehicle   = tu.vehicle.map { ($0.id + $0.label).trimmingCharacters(in: .whitespaces) } ?? "—"

    print("\n[\(String(format: "%3d", idx+1))] \(icon) \(routeName)\(entity.isDeleted ? "  ⚠️ ELIMINADA" : "")")
    print("       Destino   : \(headsign)")
    print("       Trip ID   : \(trip.tripId)")
    if !trip.startTime.isEmpty {
        print("       Horario   : salida \(trip.startTime)  |  fecha \(trip.startDate)")
    }
    print("       Vehículo  : \(vehicle)")
    if tu.timestamp > 0 { print("       Actualiz. : \(formatTS(tu.timestamp))") }
    if tu.delay != 0    { print("       Retraso Σ : \(fmtDelay(tu.delay))") }

    let stops = tu.stopTimeUpdates
    guard !stops.isEmpty else { print("  (sin paradas)"); continue }

    // Cabecera tabla
    let w = (seq:4, id:6, name:28, prog:10, pred:10, delay:18)
    print("  \(col("Seq",w.seq)) \(col("StopID",w.id)) \(col("Nombre parada",w.name)) \(col("Program.",w.prog)) \(col("Predicha",w.pred)) Retraso llegada")
    print("  \(line("-", w.seq+w.id+w.name+w.prog+w.pred+w.delay+6))")

    for stu in stops {
        let seq    = stu.stopSequence > 0 ? "\(stu.stopSequence)" : "—"
        let sid    = stu.stopId.isEmpty   ? "—" : stu.stopId
        let sname  = gtfs.stops[sid]?.name ?? "—"
        let delay  = stu.arrival?.delay ?? stu.departure?.delay ?? 0
        let schSec = gtfs.stopTimes[trip.tripId]?[Int(stu.stopSequence)]?.arrivalSecs

        var progStr = "—"; var predStr = "—"
        if let secs = schSec,
           let progDate = toDate(startDate: trip.startDate, secondsFromMidnight: secs),
           let predDate = toDate(startDate: trip.startDate, secondsFromMidnight: secs, delaySecs: delay) {
            progStr = formatTime(progDate)
            predStr = formatTime(predDate)
        }

        let relStr = stu.scheduleRelationship != 0 ? " [\(schedName(stu.scheduleRelationship))]" : ""
        print("  \(col(seq,w.seq)) \(col(sid,w.id)) \(col(sname,w.name)) \(col(progStr,w.prog)) \(col(predStr,w.pred)) \(fmtDelay(delay))\(relStr)")
    }
}

print("\n\(line("═"))")
print("✅ Procesadas \(entities.count) actualizaciones de viaje.")
print(line("═"))
