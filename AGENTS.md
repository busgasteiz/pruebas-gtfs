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
├── download_data.sh                # Descarga GTFS estático y feed RT
├── GTFS_Data/                      # Datos GTFS estáticos (generados por download_data.sh)
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
├── GTFS_Data.zip                   # ZIP descargado (no editar manualmente)
├── tripUpdates.pb                  # Feed RT binario (generado por download_data.sh)
└── TripUpdatesReader/
    ├── main.swift                  # Programa principal (único fichero fuente)
    ├── tripUpdatesReader           # Binario compilado (generado por make build)
    └── inspect.py                  # Utilidad de depuración del wire format protobuf
```

---

## Comandos rápidos

Todos se ejecutan desde `pruebas-gtfs`:

| Comando         | Acción                                             |
|-----------------|----------------------------------------------------|
| `make`          | Muestra la ayuda (acción predeterminada)           |
| `make download` | Descarga `GTFS_Data/` y `tripUpdates.pb`           |
| `make run`      | Interpreta `main.swift` con Swift (sin compilar)   |
| `make build`    | Compila `main.swift` → binario `tripUpdatesReader` |
| `make run-bin`  | Compila si hace falta y ejecuta el binario         |
| `make refresh`  | `download` + `run`                                 |
| `make clean`    | Elimina el binario compilado                       |

---

## Fuentes de datos

| Recurso                     | URL                                                                                 |
|-----------------------------|-------------------------------------------------------------------------------------|
| GTFS estático               | `https://www.vitoria-gasteiz.org/we001/http/vgTransit/google_transit.zip`           |
| Feed RT — trip updates      | `https://www.vitoria-gasteiz.org/we001/http/vgTransit/realTime/tripUpdates.pb`      |
| Feed RT — vehicle positions | `https://www.vitoria-gasteiz.org/we001/http/vgTransit/realTime/vehiclePositions.pb` |

El feed RT se actualiza con frecuencia (cada ~30 s). El GTFS estático cambia
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

## ⚠️ Particularidades del feed (no estándar)

El feed de Tuvisa **no sigue el campo estándar de GTFS-RT** para `TripUpdate`:

| Campo protobuf | Estándar GTFS-RT            | **Este feed**               |
|----------------|-----------------------------|-----------------------------|
| field 2        | `VehicleDescriptor`         | `StopTimeUpdate` (repetido) |
| field 3        | `StopTimeUpdate` (repetido) | `VehicleDescriptor`         |

Esto está corregido en `parseTripUpdate` con un comentario explicativo.

Además, `StopTimeEvent` sólo incluye `delay` (field 1); el campo `time`
(field 2, timestamp absoluto) **no se emite**; la hora predicha se calcula
como `scheduled_time + delay`.

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

## Utilidad de depuración (`inspect.py`)

`python3 TripUpdatesReader/inspect.py` imprime la estructura completa de las
dos primeras `FeedEntity` del fichero `tripUpdates.pb` en formato jerárquico,
mostrando número de campo, wire type y valor (varint como signed/unsigned,
strings UTF-8, sub-mensajes recursivos). Útil para verificar el mapeo de
campos ante cambios en el feed.

---

## Zona horaria

Toda la lógica de tiempo usa `Europe/Madrid` (configurada en `agency.txt`).
En verano (abril) corresponde a **CEST = UTC+2**.

