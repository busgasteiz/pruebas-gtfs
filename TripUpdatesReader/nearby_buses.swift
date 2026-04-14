import Foundation

// ============================================================
// MARK: - Configuración por defecto
// ============================================================

let DEFAULT_LAT:    Double = 42.855107
let DEFAULT_LON:    Double = -2.666295
let DEFAULT_RADIUS: Double = 500.0        // metros
let DEFAULT_WINDOW: Int    = 30           // minutos vista

let MADRID_TZ = TimeZone(identifier: "Europe/Madrid")!

// ============================================================
// MARK: - ProtoReader (wire format Protocol Buffers)
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
// MARK: - Estructuras GTFS estático
// ============================================================

struct StopInfo {
    let id: String; let name: String; let lat: Double; let lon: Double
}
struct TripInfo {
    let id: String; let routeId: String; let headsign: String; let serviceId: String
}
struct RouteInfo {
    let id: String; let shortName: String; let longName: String; let color: String
}
/// Entrada del índice stop_id → lista de horarios
struct StopTimeEntry {
    let tripId: String
    let stopSequence: Int
    let arrivalSecs: Int    // segundos desde medianoche; puede ser > 86400 para servicios nocturnos
}

// ============================================================
// MARK: - Estructuras RT
// ============================================================

struct TripDelayInfo {
    var generalDelay: Int32 = 0
    var stopDelays:   [String: Int32] = [:]   // stopId → retraso de llegada (s)
    var vehicleLabel: String = ""
}

// ============================================================
// MARK: - Resultado intermedio
// ============================================================

struct UpcomingArrival {
    let stopId: String
    let stopName: String
    let distanceMeters: Double
    let routeShortName: String
    let routeLongName:  String
    let routeColor:     String
    let headsign:       String
    let scheduledTime:  Date
    let predictedTime:  Date
    let delaySecs:      Int32
    let vehicleLabel:   String
    let isRealTime:     Bool
}

// ============================================================
// MARK: - Parser CSV mínimo (respeta comillas dobles)
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

// ============================================================
// MARK: - Cargador GTFS estático
// ============================================================

struct GTFSData {
    var stops:          [String: StopInfo]        = [:]
    var trips:          [String: TripInfo]        = [:]
    var routes:         [String: RouteInfo]       = [:]
    /// stop_id → lista de horarios
    var stopArrivals:   [String: [StopTimeEntry]] = [:]
    /// service_id activo en una fecha dada (yyyyMMdd)
    var activeDates:    [String: Set<String>]     = [:]   // date → Set<service_id>
}

func loadGTFS(folder: String) -> GTFSData {
    var g = GTFSData()

    func idx(_ h: [String], _ n: String) -> Int? { h.firstIndex(of: n) }
    func get(_ r: [String], _ i: Int?) -> String {
        guard let i = i, i < r.count else { return "" }; return r[i]
    }
    func parseSecs(_ s: String) -> Int {
        let p = s.split(separator: ":").compactMap { Int($0) }
        guard p.count == 3 else { return -1 }
        return p[0] * 3600 + p[1] * 60 + p[2]
    }

    // routes.txt
    if let raw = try? String(contentsOfFile: "\(folder)/routes.txt", encoding: .utf8) {
        var lines = raw.components(separatedBy: "\n")
        let h = splitCSV(lines.removeFirst())
        let iId = idx(h,"route_id"),  iSn = idx(h,"route_short_name")
        let iLn = idx(h,"route_long_name"), iCo = idx(h,"route_color")
        for ln in lines {
            let t = ln.trimmingCharacters(in: .whitespacesAndNewlines); guard !t.isEmpty else { continue }
            let r = splitCSV(t); let id = get(r,iId); guard !id.isEmpty else { continue }
            g.routes[id] = RouteInfo(id: id, shortName: get(r,iSn), longName: get(r,iLn), color: get(r,iCo))
        }
    }

    // trips.txt
    if let raw = try? String(contentsOfFile: "\(folder)/trips.txt", encoding: .utf8) {
        var lines = raw.components(separatedBy: "\n")
        let h = splitCSV(lines.removeFirst())
        let iId = idx(h,"trip_id"), iRt = idx(h,"route_id")
        let iHs = idx(h,"trip_headsign"), iSv = idx(h,"service_id")
        for ln in lines {
            let t = ln.trimmingCharacters(in: .whitespacesAndNewlines); guard !t.isEmpty else { continue }
            let r = splitCSV(t); let id = get(r,iId); guard !id.isEmpty else { continue }
            g.trips[id] = TripInfo(id: id, routeId: get(r,iRt),
                                   headsign: get(r,iHs), serviceId: get(r,iSv))
        }
    }

    // stops.txt
    if let raw = try? String(contentsOfFile: "\(folder)/stops.txt", encoding: .utf8) {
        var lines = raw.components(separatedBy: "\n")
        let h = splitCSV(lines.removeFirst())
        let iId = idx(h,"stop_id"), iNm = idx(h,"stop_name")
        let iLat = idx(h,"stop_lat"), iLon = idx(h,"stop_lon")
        for ln in lines {
            let t = ln.trimmingCharacters(in: .whitespacesAndNewlines); guard !t.isEmpty else { continue }
            let r = splitCSV(t); let id = get(r,iId); guard !id.isEmpty else { continue }
            g.stops[id] = StopInfo(id: id, name: get(r,iNm),
                                   lat: Double(get(r,iLat)) ?? 0.0,
                                   lon: Double(get(r,iLon)) ?? 0.0)
        }
    }

    // calendar_dates.txt  →  date (yyyyMMdd) → Set<service_id>
    if let raw = try? String(contentsOfFile: "\(folder)/calendar_dates.txt", encoding: .utf8) {
        var lines = raw.components(separatedBy: "\n")
        let h = splitCSV(lines.removeFirst())
        let iSv = idx(h,"service_id"), iDt = idx(h,"date"), iEx = idx(h,"exception_type")
        for ln in lines {
            let t = ln.trimmingCharacters(in: .whitespacesAndNewlines); guard !t.isEmpty else { continue }
            let r = splitCSV(t)
            let svcId = get(r,iSv); let date = get(r,iDt); let ex = get(r,iEx)
            guard !svcId.isEmpty, !date.isEmpty, ex == "1" else { continue }   // 1=added
            g.activeDates[date, default: []].insert(svcId)
        }
    }

    // stop_times.txt — índice por stop_id para consulta inversa
    if let raw = try? String(contentsOfFile: "\(folder)/stop_times.txt", encoding: .utf8) {
        var lines = raw.components(separatedBy: "\n")
        let h = splitCSV(lines.removeFirst())
        let iTr = idx(h,"trip_id"), iSt = idx(h,"stop_id")
        let iAr = idx(h,"arrival_time"), iDp = idx(h,"departure_time"), iSq = idx(h,"stop_sequence")
        for ln in lines {
            let t = ln.trimmingCharacters(in: .whitespacesAndNewlines); guard !t.isEmpty else { continue }
            let r = splitCSV(t)
            let tid = get(r,iTr); let sid = get(r,iSt)
            guard !tid.isEmpty, !sid.isEmpty else { continue }
            var secs = parseSecs(get(r,iAr))
            if secs < 0 { secs = parseSecs(get(r,iDp)) }   // fallback a departure_time
            guard secs >= 0 else { continue }
            let entry = StopTimeEntry(tripId: tid, stopSequence: Int(get(r,iSq)) ?? 0, arrivalSecs: secs)
            g.stopArrivals[sid, default: []].append(entry)
        }
    }

    return g
}

// ============================================================
// MARK: - Cargador TripUpdates RT (protobuf)
// ============================================================

private func pStr(_ d: Data) -> String { String(data: d, encoding: .utf8) ?? "" }

func loadTripDelays(pbPath: String) -> [String: TripDelayInfo] {
    guard let rawData = FileManager.default.contents(atPath: pbPath) else { return [:] }
    var delays: [String: TripDelayInfo] = [:]
    var r = ProtoReader(data: rawData)
    while r.hasMore {
        guard let t = r.readTag() else { break }
        switch t.field {
        case 1: _ = r.readLengthDelimited()                              // FeedHeader — ignorar
        case 2: if let d = r.readLengthDelimited() { parseTUEntity(d, into: &delays) }
        default: r.skip(wire: t.wire)
        }
    }
    return delays
}

private func parseTUEntity(_ data: Data, into delays: inout [String: TripDelayInfo]) {
    var r = ProtoReader(data: data)
    var tuData: Data? = nil
    var deleted = false
    while r.hasMore {
        guard let t = r.readTag() else { break }
        switch t.field {
        case 1: _ = r.readLengthDelimited()                              // entity id
        case 2: if let v = r.readVarint() { deleted = v != 0 }          // is_deleted
        case 3: tuData = r.readLengthDelimited()                         // TripUpdate
        default: r.skip(wire: t.wire)
        }
    }
    guard !deleted, let tuD = tuData else { return }

    var tu = ProtoReader(data: tuD)
    var tripId = ""
    var info = TripDelayInfo()
    while tu.hasMore {
        guard let t = tu.readTag() else { break }
        switch t.field {
        case 1:   // TripDescriptor — leer trip_id
            if let d = tu.readLengthDelimited() {
                var td = ProtoReader(data: d)
                while td.hasMore {
                    guard let tt = td.readTag() else { break }
                    switch tt.field {
                    case 1: if let s = td.readLengthDelimited() { tripId = pStr(s) }
                    default: td.skip(wire: tt.wire)
                    }
                }
            }
        case 2:   // StopTimeUpdate (campo no estándar: field 2 en lugar de 3)
            if let d = tu.readLengthDelimited() {
                var stu = ProtoReader(data: d)
                var stopId = ""; var arrDelay: Int32 = 0
                while stu.hasMore {
                    guard let tt = stu.readTag() else { break }
                    switch tt.field {
                    case 1: _ = stu.readVarint()                         // stop_sequence
                    case 2:                                              // arrival StopTimeEvent
                        if let d2 = stu.readLengthDelimited() {
                            var ste = ProtoReader(data: d2)
                            while ste.hasMore {
                                guard let tt2 = ste.readTag() else { break }
                                switch tt2.field {
                                case 1: if let v = ste.readVarint() {
                                    arrDelay = Int32(truncatingIfNeeded: Int64(bitPattern: v))
                                }
                                default: ste.skip(wire: tt2.wire)
                                }
                            }
                        }
                    case 3: _ = stu.readLengthDelimited()               // departure StopTimeEvent — skip
                    case 4: if let s = stu.readLengthDelimited() { stopId = pStr(s) }
                    default: stu.skip(wire: tt.wire)
                    }
                }
                if !stopId.isEmpty { info.stopDelays[stopId] = arrDelay }
            }
        case 3:   // VehicleDescriptor (campo no estándar: field 3 en lugar de 2)
            if let d = tu.readLengthDelimited() {
                var vd = ProtoReader(data: d)
                while vd.hasMore {
                    guard let tt = vd.readTag() else { break }
                    switch tt.field {
                    case 2: if let s = vd.readLengthDelimited() { info.vehicleLabel = pStr(s) }
                    default: vd.skip(wire: tt.wire)
                    }
                }
            }
        case 5:   // TripUpdate.delay — retraso general del viaje
            if let v = tu.readVarint() {
                info.generalDelay = Int32(truncatingIfNeeded: Int64(bitPattern: v))
            }
        default: tu.skip(wire: t.wire)
        }
    }
    if !tripId.isEmpty { delays[tripId] = info }
}

// ============================================================
// MARK: - Utilidades de distancia y tiempo
// ============================================================

/// Distancia en metros entre dos coordenadas geográficas (fórmula de Haversine).
func haversine(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
    let R = 6_371_000.0
    let φ1 = lat1 * .pi / 180, φ2 = lat2 * .pi / 180
    let Δφ = (lat2 - lat1) * .pi / 180, Δλ = (lon2 - lon1) * .pi / 180
    let a = sin(Δφ / 2) * sin(Δφ / 2) + cos(φ1) * cos(φ2) * sin(Δλ / 2) * sin(Δλ / 2)
    return R * 2 * atan2(sqrt(a), sqrt(1 - a))
}

func dateString(_ date: Date) -> String {
    let f = DateFormatter(); f.dateFormat = "yyyyMMdd"; f.timeZone = MADRID_TZ
    return f.string(from: date)
}

/// Convierte (fecha de servicio yyyyMMdd, segundos desde medianoche) a Date.
/// Admite arrivalSecs > 86400 para servicios que cruzan la medianoche.
func scheduledDate(serviceDate: String, secondsFromMidnight: Int) -> Date? {
    let f = DateFormatter(); f.dateFormat = "yyyyMMdd"; f.timeZone = MADRID_TZ
    guard let base = f.date(from: serviceDate) else { return nil }
    return base.addingTimeInterval(TimeInterval(secondsFromMidnight))
}

func formatTime(_ date: Date) -> String {
    let f = DateFormatter(); f.dateFormat = "HH:mm"; f.timeZone = MADRID_TZ
    return f.string(from: date)
}

func minutesUntil(_ date: Date, from now: Date) -> Int {
    return Int((date.timeIntervalSince(now) / 60).rounded())
}

/// Dado un trip, determina la fecha de servicio que hace que su horario caiga
/// en la ventana temporal [windowStart, windowEnd].
/// Prueba primero con hoy y luego con ayer (para servicios nocturnos).
func resolveServiceDate(
    trip: TripInfo,
    arrivalSecs: Int,
    activeServiceIds: Set<String>,
    yesterdayActiveIds: Set<String>,
    today: String,
    yesterday: String,
    windowStart: Date,
    windowEnd: Date
) -> String? {
    // Candidatos en orden de preferencia
    let candidates: [(date: String, validSvcIds: Set<String>)] = [
        (today,     activeServiceIds),
        (yesterday, yesterdayActiveIds),
    ]
    for (date, validIds) in candidates {
        // El service_id debe ser válido para esa fecha
        // Para "UNDEFINED": no está en calendar_dates; lo incluimos sólo si hay coincidencia temporal
        let svcOk = validIds.contains(trip.serviceId) || trip.serviceId == "UNDEFINED"
        guard svcOk else { continue }
        guard let schTime = scheduledDate(serviceDate: date, secondsFromMidnight: arrivalSecs)
        else { continue }
        if schTime >= windowStart && schTime <= windowEnd { return date }
    }
    return nil
}

// ============================================================
// MARK: - Helpers de presentación
// ============================================================

func pad(_ s: String, _ w: Int) -> String {
    s.count >= w ? String(s.prefix(w)) : s + String(repeating: " ", count: w - s.count)
}

func routeEmoji(_ hex: String) -> String {
    switch hex.lowercased() {
    case "ffdd00": return "🟡"
    case "00a54f": return "🟢"
    case "44c7f4": return "🔵"
    case "ed1c24": return "🔴"
    case "ff8000": return "🟠"
    case "8b5cf6": return "🟣"
    case "ffffff": return "⚪"
    default:       return "⬜"
    }
}

func fmtDelay(_ d: Int32) -> String {
    guard d != 0 else { return "puntual" }
    let sign = d > 0 ? "+" : ""
    let a = Swift.abs(Int(d))
    return a < 60 ? "\(sign)\(d)s" : String(format: "%@%dm%02ds", sign, a / 60, a % 60)
}

func ruler(_ n: Int = 72) -> String { String(repeating: "─", count: n) }
func thick(_ n: Int = 72) -> String { String(repeating: "═", count: n) }

// ============================================================
// MARK: - Main
// ============================================================

let args = CommandLine.arguments

let userLat    = args.count > 1 ? Double(args[1]) ?? DEFAULT_LAT    : DEFAULT_LAT
let userLon    = args.count > 2 ? Double(args[2]) ?? DEFAULT_LON    : DEFAULT_LON
let radiusM    = args.count > 3 ? Double(args[3]) ?? DEFAULT_RADIUS : DEFAULT_RADIUS
let windowMins = args.count > 4 ? Int(args[4])    ?? DEFAULT_WINDOW : DEFAULT_WINDOW
let pbPath     = args.count > 5 ? args[5] : "./tripUpdates.pb"
let gtfsFolder = args.count > 6 ? args[6] : "./GTFS_Data"

let now       = Date()
let today     = dateString(now)
let yesterday = dateString(now.addingTimeInterval(-86400))

print(thick())
print("🚌  Próximas llegadas — Tuvisa Vitoria-Gasteiz")
print(thick())
print("📍 Coordenadas : \(userLat), \(userLon)")
print("📐 Radio       : \(Int(radiusM)) m")
print("⏱️  Ventana      : próximos \(windowMins) min")
print("🕐 Hora actual : \(formatTime(now)) (Europe/Madrid · \(today))")
print()

// --- Carga datos ---
print("⏳ Cargando datos GTFS estáticos …")
let gtfs = loadGTFS(folder: gtfsFolder)
let totalSchedules = gtfs.stopArrivals.values.reduce(0) { $0 + $1.count }
print("   ✔ \(gtfs.routes.count) rutas · \(gtfs.trips.count) viajes · \(gtfs.stops.count) paradas · \(totalSchedules) horarios")

print("⏳ Cargando feed RT (tripUpdates.pb) …")
let tripDelays = loadTripDelays(pbPath: pbPath)
print("   ✔ \(tripDelays.count) actualizaciones en tiempo real")
print()

// Servicios activos hoy y ayer (para servicios nocturnos)
let activeServiceIds:   Set<String> = gtfs.activeDates[today]     ?? []
let yesterdayActiveIds: Set<String> = gtfs.activeDates[yesterday] ?? []

// --- Paradas cercanas, ordenadas por distancia ---
let nearbyStops: [(id: String, distance: Double)] = gtfs.stops.values
    .compactMap { s -> (id: String, distance: Double)? in
        let d = haversine(lat1: userLat, lon1: userLon, lat2: s.lat, lon2: s.lon)
        return d <= radiusM ? (id: s.id, distance: d) : nil
    }
    .sorted { $0.distance < $1.distance }

guard !nearbyStops.isEmpty else {
    print("⚠️  No se encontraron paradas en un radio de \(Int(radiusM)) m."); exit(0)
}
print("🔍 \(nearbyStops.count) paradas en un radio de \(Int(radiusM)) m\n")

// Ventana temporal: de 1 min antes de ahora hasta windowMins en el futuro
let windowStart = now.addingTimeInterval(-60)
let windowEnd   = now.addingTimeInterval(TimeInterval(windowMins * 60))

var grandTotal = 0

for (stopId, distance) in nearbyStops {
    guard let stop    = gtfs.stops[stopId]        else { continue }
    guard let entries = gtfs.stopArrivals[stopId] else { continue }

    var arrivals: [UpcomingArrival] = []

    for entry in entries {
        guard let trip = gtfs.trips[entry.tripId] else { continue }

        // Determina fecha de servicio (hoy o ayer) en la que este horario cae en la ventana
        guard let serviceDate = resolveServiceDate(
            trip:               trip,
            arrivalSecs:        entry.arrivalSecs,
            activeServiceIds:   activeServiceIds,
            yesterdayActiveIds: yesterdayActiveIds,
            today:              today,
            yesterday:          yesterday,
            windowStart:        windowStart,
            windowEnd:          windowEnd
        ) else { continue }

        guard let schTime = scheduledDate(serviceDate: serviceDate,
                                         secondsFromMidnight: entry.arrivalSecs)
        else { continue }

        // Retraso RT: específico de la parada → general del viaje → 0 (sólo horario)
        let delayInfo = tripDelays[entry.tripId]
        let delay: Int32
        let isRT: Bool
        if let d = delayInfo?.stopDelays[stopId] {
            delay = d; isRT = true
        } else if let g = delayInfo?.generalDelay {
            delay = g; isRT = true
        } else {
            delay = 0; isRT = false
        }

        let predTime = schTime.addingTimeInterval(TimeInterval(delay))
        guard predTime >= windowStart && predTime <= windowEnd else { continue }

        let route = gtfs.routes[trip.routeId]
        arrivals.append(UpcomingArrival(
            stopId:         stopId,
            stopName:       stop.name,
            distanceMeters: distance,
            routeShortName: route?.shortName ?? trip.routeId,
            routeLongName:  route?.longName  ?? "",
            routeColor:     route?.color     ?? "",
            headsign:       trip.headsign,
            scheduledTime:  schTime,
            predictedTime:  predTime,
            delaySecs:      delay,
            vehicleLabel:   delayInfo?.vehicleLabel ?? "",
            isRealTime:     isRT
        ))
    }

    guard !arrivals.isEmpty else { continue }
    arrivals.sort { $0.predictedTime < $1.predictedTime }
    grandTotal += arrivals.count

    // ---- Cabecera de parada ----
    let distStr = "\(Int(distance.rounded())) m"
    let header = " 📍 \(stop.name)  [\(stopId)]  — \(distStr) "
    let fillLen = max(0, 72 - header.count)
    print("┌─\(header)" + String(repeating: "─", count: fillLen))
    print("│")

    for a in arrivals {
        let mins = minutesUntil(a.predictedTime, from: now)
        let minsStr: String
        switch mins {
        case ..<1:  minsStr = "llegando"
        case 1:     minsStr = "1 min"
        default:    minsStr = "\(mins) min"
        }

        let rtTag  = a.isRealTime ? "📡" : "📅"
        let icon   = routeEmoji(a.routeColor)
        let delay  = fmtDelay(a.delaySecs)
        let veh    = a.vehicleLabel.isEmpty ? "" : "  🚍 \(a.vehicleLabel)"

        let lineLabel = pad(a.routeShortName, 3)
        let dest      = pad(a.headsign, 26)
        print("│  \(pad(minsStr, 8))  \(icon) L\(lineLabel)  \(dest)  \(formatTime(a.predictedTime))  \(rtTag) \(pad(delay, 9))\(veh)")

        // Línea extra con hora programada si hay retraso RT
        if a.isRealTime && a.delaySecs != 0 {
            print("│           ↳ programado: \(formatTime(a.scheduledTime))")
        }
    }

    print("│")
    print("└" + ruler(71))
    print()
}

print(thick())
if grandTotal == 0 {
    print("ℹ️  No hay llegadas previstas en los próximos \(windowMins) minutos.")
} else {
    print("✅  \(grandTotal) llegada(s) en \(nearbyStops.count) parada(s) cercana(s).")
}
print(thick())

