#!/bin/zsh
# download_data.sh
# Descarga los datos GTFS estáticos y en tiempo real de Vitoria-Gasteiz (Tuvisa)

set -euo pipefail

# ── Rutas base (relativas al directorio del propio script) ────────────────────
DIR="$(cd "$(dirname "$0")" && pwd)"
GTFS_ZIP="$DIR/GTFS_Data.zip"
GTFS_DIR="$DIR/GTFS_Data"
PB_FILE="$DIR/tripUpdates.pb"

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
echo "   ✔ Guardado en: $PB_FILE ($(wc -c < "$PB_FILE" | tr -d ' ') bytes)"

# ── Resumen ───────────────────────────────────────────────────────────────────
echo ""
echo "✅ Descarga completada — $(date '+%Y-%m-%d %H:%M:%S')"
echo "   GTFS estático  → $GTFS_DIR"
echo "   Tiempo real    → $PB_FILE"

