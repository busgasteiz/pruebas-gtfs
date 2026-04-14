# ──────────────────────────────────────────────────────────────────────────────
# Makefile — Datos GTFS Vitoria-Gasteiz (Tuvisa)
# Uso: make <target>   (ejecutar desde ~/Downloads)
# ──────────────────────────────────────────────────────────────────────────────

SWIFT_SRC       = TripUpdatesReader/main.swift
BINARY          = TripUpdatesReader/tripUpdatesReader
NEARBY_SRC      = TripUpdatesReader/nearby_buses.swift
NEARBY_BIN      = TripUpdatesReader/nearby_buses
DOWNLOAD_SH     = ./download_data.sh

.PHONY: all download run build run-bin refresh clean help nearby build-nearby run-nearby

## Muestra la ayuda (acción predeterminada)
.DEFAULT_GOAL := help

## Descarga datos + lee el resultado
all: download run

## Descarga GTFS estático (GTFS_Data/) y tiempo real (tripUpdates.pb)
download:
	@$(DOWNLOAD_SH)

## Interpreta el lector Swift sin compilar (más lento, sin dependencias extra)
run:
	@swift $(SWIFT_SRC)

## Compila el lector Swift en un binario nativo
build: $(BINARY)

$(BINARY): $(SWIFT_SRC)
	@echo "🔨 Compilando $(SWIFT_SRC) …"
	@swiftc $(SWIFT_SRC) -O -o $(BINARY)
	@echo "   ✔ Binario: $(BINARY)"

## Compila si hace falta y ejecuta el binario (mucho más rápido que 'run')
run-bin: $(BINARY)
	@$(BINARY)

## Descarga datos frescos y los lee de inmediato
refresh: download run

## Elimina el binario compilado
clean:
	@rm -f $(BINARY) $(NEARBY_BIN)
	@echo "🗑  Binarios eliminados"

## Interpreta nearby_buses.swift (paradas cercanas + próximas llegadas)
nearby:
	@swift $(NEARBY_SRC)

## Compila nearby_buses.swift en binario nativo
build-nearby: $(NEARBY_BIN)

$(NEARBY_BIN): $(NEARBY_SRC)
	@echo "🔨 Compilando $(NEARBY_SRC) …"
	@swiftc $(NEARBY_SRC) -O -o $(NEARBY_BIN)
	@echo "   ✔ Binario: $(NEARBY_BIN)"

## Compila si hace falta y ejecuta nearby_buses (mucho más rápido que 'nearby')
run-nearby: $(NEARBY_BIN)
	@$(NEARBY_BIN)

## Muestra esta ayuda
help:
	@echo ""
	@echo "Targets disponibles:"
	@echo "  make download      Descarga GTFS estático y tripUpdates.pb"
	@echo "  make run           Lee tripUpdates.pb con el intérprete Swift"
	@echo "  make build         Compila el lector Swift en un binario nativo"
	@echo "  make run-bin       Compila si es necesario y ejecuta el binario"
	@echo "  make refresh       download + run  (datos frescos + lectura)"
	@echo "  make all           download + run  (igual que refresh)"
	@echo "  make nearby        Muestra paradas cercanas y próximas llegadas (sin compilar)"
	@echo "  make build-nearby  Compila nearby_buses.swift en binario nativo"
	@echo "  make run-nearby    Compila si hace falta y ejecuta nearby_buses"
	@echo "  make clean         Elimina los binarios compilados"
	@echo ""

