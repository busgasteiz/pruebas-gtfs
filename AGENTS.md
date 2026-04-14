# AGENTS.md — Lector GTFS-RT Vitoria-Gasteiz (Tuvisa)

Guía para agentes de IA que trabajen en este proyecto.

---

## Descripción general

Herramienta de línea de comandos que descarga y decodifica los feeds de
**transporte público en tiempo real** de Tuvisa (Vitoria-Gasteiz) y los
combina con los horarios estáticos GTFS para mostrar, por cada viaje activo,
el nombre de cada parada, su hora programada y la hora predicha según el
retraso actual.

---

## Estructura del proyecto

```
pruebas-gtfs
├── Makefile                        # Punto de entrada principal (make help)
├── download_data.sh                # Descarga GTFS estático y feeds RT de Tuvisa y Euskotren
├── GTFS_Data/                      # Datos GTFS estáticos Tuvisa (generados por download_data.sh)
│   ├── agency.txt
│   ├── routes.txt
│   ├── trips.txt
│   ├── stops.txt
│   ├── stop_times.txt
│   ├── calendar_dates.txt
│   ├── fare_attributes.txt
│   ├── fare_rules.txt
│   ├── feed_info.txt
│   ├── shapes.txt
│   ├── translations.txt
│   └── attributions.txt
├── Euskotren_Data/                 # Datos GTFS estáticos Euskotren (generados por download_data.sh)
│   ├── agency.txt
│   ├── routes.txt                  # Contiene todas las líneas; filtrar a agency_id=EUS_TrGa para el tranvía
│   ├── trips.txt
│   ├── stops.txt                   # Incluye StopPlace (location_type=1) y Quays (location_type=0)
│   ├── stop_times.txt
│   ├── calendar.txt                # Horario semanal (a diferencia de Tuvisa, que usa calendar_dates.txt)
│   ├── calendar_dates.txt          # Excepciones al calendar.txt
│   └── …
├── GTFS_Data.zip                   # ZIP Tuvisa descargado (no editar manualmente)
├── Euskotren_Data.zip              # ZIP Euskotren descargado (no editar manualmente)
├── tripUpdates.pb                  # Feed RT binario Tuvisa (generado por download_data.sh)
├── vehiclePositions.pb             # Feed RT de posiciones GPS Tuvisa (generado por download_data.sh)
├── euskotrenTripUpdates.pb         # Feed RT binario Euskotren (generado por download_data.sh)
└── TripUpdatesReader/
    ├── main.swift                  # Programa principal (único fichero fuente)
    ├── nearby_buses.swift          # Paradas cercanas + próximas llegadas
    ├── tripUpdatesReader           # Binario compilado (generado por make build)
    ├── inspect.py                  # Utilidad de depuración: muestra primeras entidades de tripUpdates.pb
    ├── inspect_tu.py               # Utilidad de depuración: extrae trip_ids y stop_ids de tripUpdates.pb
    └── inspect_vp.py               # Utilidad de depuración: vehiclePositions.pb
```

---

## Comandos rápidos

Todos se ejecutan desde `pruebas-gtfs`:

| Comando         | Acción                                             |
|-----------------|----------------------------------------------------|
| `make`          | Muestra la ayuda (acción predeterminada)           |
| `make download`      | Descarga `GTFS_Data/` y `tripUpdates.pb`           |
| `make run`           | Interpreta `main.swift` con Swift (sin compilar)   |
| `make build`         | Compila `main.swift` → binario `tripUpdatesReader` |
| `make run-bin`       | Compila si hace falta y ejecuta el binario         |
| `make nearby`        | Paradas cercanas + próximas llegadas (sin compilar)|
| `make build-nearby`  | Compila `nearby_buses.swift` → binario             |
| `make run-nearby`    | Compila si hace falta y ejecuta `nearby_buses`     |
| `make refresh`       | `download` + `run`                                 |
| `make clean`         | Elimina los binarios compilados                    |

---

## Fuentes de datos

### Tuvisa — autobuses urbanos de Vitoria-Gasteiz

| Recurso                     | URL                                                                                 |
|-----------------------------|-------------------------------------------------------------------------------------|
| GTFS estático               | `https://www.vitoria-gasteiz.org/we001/http/vgTransit/google_transit.zip`           |
| Feed RT — trip updates      | `https://www.vitoria-gasteiz.org/we001/http/vgTransit/realTime/tripUpdates.pb`      |
| Feed RT — vehicle positions | `https://www.vitoria-gasteiz.org/we001/http/vgTransit/realTime/vehiclePositions.pb` |

### Euskotren — tranvía EuskoTran de Vitoria-Gasteiz

| Recurso                     | URL                                                                                              |
|-----------------------------|--------------------------------------------------------------------------------------------------|
| GTFS estático               | `https://opendata.euskadi.eus/transport/moveuskadi/euskotren/gtfs_euskotren.zip`                  |
| Feed RT — trip updates      | `https://opendata.euskadi.eus/transport/moveuskadi/euskotren/gtfsrt_euskotren_trip_updates.pb`    |

El GTFS de Euskotren incluye toda la red (tren, metro, tram), por lo que se filtra al operador
`EUS_TrGa` (líneas TG1, TG2 y 41 del tranvía de Vitoria-Gasteiz). El feed RT de Euskotren
sigue el estándar GTFS-RT sin las particularidades no estándar de Tuvisa.

Los feeds RT se actualizan con frecuencia (cada ~30 s). Los ZIPs estáticos cambian
con menor frecuencia (cambios de servicio estacionales).

---

## Arquitectura de `main.swift`

El fichero está organizado en secciones `MARK`:

### 1 · ProtoReader

Decodificador de bajo nivel del wire format de Protocol Buffers (sin
dependencias externas). Implementa lectura de varint, campos
length-delimited, salto de campos desconocidos y detección de desbordamiento
(`length <= UInt64(Int.max)` antes de convertir a `Int`).

### 2 · Estructuras GTFS-RT

`FeedMessage → FeedHeader + [FeedEntity]`
`FeedEntity  → TripUpdate`
`TripUpdate  → TripDescriptor + VehicleDescriptor + [StopTimeUpdate]`
`StopTimeUpdate → StopTimeEvent (arrival/departure)`

### 3 · Parsers protobuf

Una función `parseXxx(_ data: Data) -> Xxx` por cada mensaje.

### 4 · Datos GTFS estáticos

Cuatro structs (`RouteInfo`, `GTFSTripInfo`, `StopInfo`, `StopSchedule`) y
un `GTFSData` que agrupa cuatro diccionarios indexados por clave primaria.

### 5 · Cargador CSV / GTFS

`loadGTFS(folder:)` lee los cuatro ficheros relevantes con un parser CSV
mínimo que respeta comillas dobles.

### 6 · Utilidades de tiempo

Las horas GTFS se expresan como segundos desde medianoche en la zona horaria
`Europe/Madrid`. La hora predicha = `hora_programada + retraso_RT`.

### 7 · Main

Carga secuencial: GTFS estático → feed RT → impresión enriquecida por entidad.

---

## Arquitectura de `nearby_buses.swift`

Programa independiente (sin SPM, sin dependencias externas) que muestra las
paradas cercanas a unas coordenadas y los autobuses previstos en los próximos
minutos.

### Uso

```bash
swift TripUpdatesReader/nearby_buses.swift [lat] [lon] [radio_m] [ventana_min] [pb_path] [gtfs_folder]
# Valores predeterminados: 42.855107  -2.666295  500  30  ./tripUpdates.pb  ./GTFS_Data
```

O con los targets del Makefile:

```bash
make nearby        # sin compilar (más lento, cómodo para pruebas rápidas)
make run-nearby    # compilado   (recomendado en uso habitual)
```

### Flujo de datos

1. **Carga GTFS**: routes, trips (con `service_id`), stops, `calendar_dates`,
   `stop_times` indexado por `stop_id`.
2. **Índice `activeDates`**: `date (yyyyMMdd) → Set<service_id>` construido
   desde `calendar_dates.txt` (sólo `exception_type=1`).
3. **Carga TripUpdates RT**: construye `[tripId: TripDelayInfo]` con retraso
   por parada y etiqueta del vehículo.
4. **Filtrado geográfico**: distancia Haversine; paradas dentro del radio
   ordenadas de menor a mayor distancia.
5. **Resolución de fecha de servicio** (`resolveServiceDate`): para cada
   horario de parada, prueba primero con la fecha de hoy y después con ayer
   (para servicios nocturnos con `arrivalSecs > 86400`). Valida que el
   `service_id` esté activo en esa fecha según `activeDates`.
6. **Aplicación del retraso**: `predictedTime = scheduledTime + delay`,
   donde el delay se busca por `stopId` y, si no existe, por viaje.
7. **Presentación**: paradas en orden de distancia; dentro de cada parada,
   llegadas en orden cronológico.

### Particularidad del trip_id en Tuvisa

La mayoría de los viajes usan el formato `L{ruta}S{var}_{num}-{svctype}`
(ej.: `L10S1_055-LAB`), que coincide **directamente** con el `trip_id` del
feed RT. No se necesita ningún mapeo adicional.

Los 53 viajes con `service_id=UNDEFINED` usan el formato
`{ruta}_{dir}_{var}_{fecha}T{hora}_{hash}` y **no aparecen** en los feeds RT;
se incluyen si su horario cae en la ventana temporal.

---

## ⚠️ Particularidades del feed (no estándar)

### `TripUpdate` — campo `TripUpdate`

El feed de Tuvisa **no sigue el campo estándar de GTFS-RT** para `TripUpdate`:

| Campo protobuf | Estándar GTFS-RT            | **Este feed**               |
|----------------|-----------------------------|-----------------------------|
| field 2        | `VehicleDescriptor`         | `StopTimeUpdate` (repetido) |
| field 3        | `StopTimeUpdate` (repetido) | `VehicleDescriptor`         |

Esto está corregido en `parseTripUpdate` con un comentario explicativo.

Además, `StopTimeEvent` sólo incluye `delay` (field 1); el campo `time`
(field 2, timestamp absoluto) **no se emite**; la hora predicha se calcula
como `scheduled_time + delay`.

### `VehiclePosition` — feed `vehiclePositions.pb`

El feed contiene **~67 entidades** (vehículos en circulación en el momento
de la descarga). Los campos dentro del sub-mensaje `VehiclePosition`
(field 4 de `FeedEntity`) también están **desplazados** respecto al estándar:

| Campo protobuf | Estándar GTFS-RT       | **Este feed**            |
|----------------|------------------------|--------------------------|
| field 2        | `VehicleDescriptor`    | `Position` (GPS)         |
| field 3        | `Position`             | `current_stop_sequence`  |
| field 5        | `stop_id`              | `timestamp`              |
| field 6        | `current_status`       | _(no emitido)_           |
| field 7        | `timestamp`            | `stop_id`                |
| field 8        | `congestion_level`     | `VehicleDescriptor`      |

#### Campos del sub-mensaje `TripDescriptor` (field 1 — igual al estándar)

| Campo   | Contenido                                  | Ejemplo            |
|---------|--------------------------------------------|--------------------|
| field 1 | `trip_id`                                  | `'L1S2_026-LAB'`   |
| field 4 | `schedule_relationship` (0 = SCHEDULED)    | `0`                |
| field 5 | `route_id` (número de línea)               | `'1'`, `'10'`, `'B'` |

#### Campos del sub-mensaje `Position` (field 2 en este feed, estándar field 3)

| Campo   | Tipo     | Contenido                        | Ejemplo      |
|---------|----------|----------------------------------|--------------|
| field 1 | float32  | Latitud                          | `42.857887`  |
| field 2 | float32  | Longitud                         | `-2.681148`  |
| field 4 | double64 | Odómetro en metros (opcional)    | `254218960`  |
| field 5 | float32  | Velocidad en m/s (opcional)      | `8.33` (~30 km/h) |

> El campo `bearing` (field 3, estándar) **no se emite** en este feed.

#### Campos del sub-mensaje `VehicleDescriptor` (field 8 en este feed, estándar field 2)

| Campo   | Contenido                        | Ejemplo          |
|---------|----------------------------------|------------------|
| field 1 | ID interno del vehículo          | `'v-025e81ab'`   |
| field 2 | Número de flota visible al viajero | `'138'`, `'53'` |

#### Valores de `current_status` (field 4 en este feed, estándar field 6)

| Valor | Significado   |
|-------|---------------|
| `0`   | `INCOMING_AT` |
| `2`   | `IN_TRANSIT_TO` |

---

## Convenciones de código

- **Un único fichero Swift** (`main.swift`): sin SPM, sin dependencias externas.
- Todas las conversiones `UInt64 → Int` / `UInt64 → UInt32` usan
  `truncatingIfNeeded` o están protegidas con un `guard` previo.
- El operador `??` sobre el resultado de `Int(...)` o `Double(...)` necesita
  espacio explícito (`Int(x) ?? 0`, no `Int(x)??0`) para evitar que Swift 6
  lo interprete como doble opcional.
- Las rutas por defecto están hardcodeadas a `./`; se pueden
  sobreescribir pasando argumentos posicionales:
  `swift main.swift <ruta_pb> <ruta_gtfs_folder>`

---

## Utilidades de depuración

### `inspect.py`

`python3 TripUpdatesReader/inspect.py` imprime la estructura completa de las
dos primeras `FeedEntity` del fichero `tripUpdates.pb` en formato jerárquico,
mostrando número de campo, wire type y valor (varint como signed/unsigned,
strings UTF-8, sub-mensajes recursivos). Útil para verificar el mapeo de
campos ante cambios en el feed.

> ⚠️ La ruta del fichero está hardcodeada; editar la línea `data = open(...)` si es necesario.

### `inspect_tu.py`

`python3 TripUpdatesReader/inspect_tu.py` extrae los `trip_id` y `stop_id` de las primeras entidades
del fichero `tripUpdates.pb`, útil para verificar qué viajes y paradas lleva el feed en ese momento.

> ⚠️ La ruta del fichero está hardcodeada relativa al script; apunta a `../tripUpdates.pb`.

### `inspect_vp.py`

`python3 TripUpdatesReader/inspect_vp.py [N]` imprime las primeras **N**
`FeedEntity` (por defecto 3) del fichero `vehiclePositions.pb`, en el mismo
formato jerárquico. Al final indica el total de entidades en el feed.

```bash
# Ver las 5 primeras entidades
python3 TripUpdatesReader/inspect_vp.py 5

# Ver todas las entidades
python3 TripUpdatesReader/inspect_vp.py 67
```

La ruta del fichero se resuelve automáticamente como `../vehiclePositions.pb`
relativo al script, sin necesidad de edición manual.
