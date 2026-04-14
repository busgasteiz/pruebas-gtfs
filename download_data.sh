#!/bin/zsh
# download_data.sh
# Descarga los datos GTFS estáticos y en tiempo real de Vitoria-Gasteiz:
#   · Tuvisa (autobuses urbanos)
#   · Euskotren Tranvía Vitoria-Gasteiz (EuskoTran)

set -euo pipefail

# ── Rutas base (relativas al directorio del propio script) ────────────────────
DIR="$(cd "$(dirname "$0")" && pwd)"
GTFS_ZIP="$DIR/GTFS_Data.zip"
GTFS_DIR="$DIR/GTFS_Data"
PB_FILE="$DIR/tripUpdates.pb"
VP_FILE="$DIR/vehiclePositions.pb"
EUSKOTREN_ZIP="$DIR/Euskotren_Data.zip"
EUSKOTREN_DIR="$DIR/Euskotren_Data"
EUSKOTREN_TU_FILE="$DIR/euskotrenTripUpdates.pb"

# ── 1. GTFS estático ──────────────────────────────────────────────────────────
echo "📥 Descargando GTFS estático (google_transit.zip) …"
curl -L --progress-bar \
    "https://www.vitoria-gasteiz.org/we001/http/vgTransit/google_transit.zip" \
    -o "$GTFS_ZIP"
echo "   ✔ Guardado en: $GTFS_ZIP"

# ── 2. Limpiar y recrear el directorio GTFS_Data ─────────────────────────────
echo "🗑  Limpiando directorio GTFS_Data …"
if [ -d "$GTFS_DIR" ]; then
    rm -rf "$GTFS_DIR"
fi
mkdir -p "$GTFS_DIR"

echo "📦 Descomprimiendo en $GTFS_DIR …"
unzip -q "$GTFS_ZIP" -d "$GTFS_DIR"
echo "   ✔ $(ls "$GTFS_DIR" | wc -l | tr -d ' ') archivos extraídos"

# ── 3. Datos en tiempo real ───────────────────────────────────────────────────
echo "📡 Descargando tripUpdates.pb (tiempo real) …"
curl -L --progress-bar \
    "https://www.vitoria-gasteiz.org/we001/http/vgTransit/realTime/tripUpdates.pb" \
    -o "$PB_FILE"
echo "   ✔ Guardado en: $PB_FILE ($(wc -c <"$PB_FILE" | tr -d ' ') bytes)"

# ── 4. Posiciones de vehículos ────────────────────────────────────────────────
echo "📡 Descargando vehiclePositions.pb (tiempo real) …"
curl -L --progress-bar \
    "https://www.vitoria-gasteiz.org/we001/http/vgTransit/realTime/vehiclePositions.pb" \
    -o "$VP_FILE"
echo "   ✔ Guardado en: $VP_FILE ($(wc -c <"$VP_FILE" | tr -d ' ') bytes)"

# ── 5. Euskotren GTFS estático ────────────────────────────────────────────────
echo "📥 Descargando GTFS estático Euskotren (gtfs_euskotren.zip) …"
curl -L --progress-bar \
    "https://opendata.euskadi.eus/transport/moveuskadi/euskotren/gtfs_euskotren.zip" \
    -o "$EUSKOTREN_ZIP"
echo "   ✔ Guardado en: $EUSKOTREN_ZIP"

# ── 6. Limpiar y recrear Euskotren_Data ──────────────────────────────────────
echo "🗑  Limpiando directorio Euskotren_Data …"
if [ -d "$EUSKOTREN_DIR" ]; then
    rm -rf "$EUSKOTREN_DIR"
fi
mkdir -p "$EUSKOTREN_DIR"

echo "📦 Descomprimiendo en $EUSKOTREN_DIR …"
unzip -q "$EUSKOTREN_ZIP" -d "$EUSKOTREN_DIR"
echo "   ✔ $(ls "$EUSKOTREN_DIR" | wc -l | tr -d ' ') archivos extraídos"

# ── 7. Actualizaciones RT Euskotren ──────────────────────────────────────────
echo "📡 Descargando gtfsrt_euskotren_trip_updates.pb (tiempo real) …"
curl -L --progress-bar \
    "https://opendata.euskadi.eus/transport/moveuskadi/euskotren/gtfsrt_euskotren_trip_updates.pb" \
    -o "$EUSKOTREN_TU_FILE"
echo "   ✔ Guardado en: $EUSKOTREN_TU_FILE ($(wc -c <"$EUSKOTREN_TU_FILE" | tr -d ' ') bytes)"

# ── Resumen ───────────────────────────────────────────────────────────────────
echo ""
echo "✅ Descarga completada — $(date '+%Y-%m-%d %H:%M:%S')"
echo "   GTFS estático Tuvisa     → $GTFS_DIR"
echo "   Actualizaciones RT Tuv.  → $PB_FILE"
echo "   Posiciones vehículos     → $VP_FILE"
echo "   GTFS estático Euskotren  → $EUSKOTREN_DIR"
echo "   Actualizaciones RT Eus.  → $EUSKOTREN_TU_FILE"
