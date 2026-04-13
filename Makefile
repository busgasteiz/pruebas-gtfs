# ──────────────────────────────────────────────────────────────────────────────
# Makefile — Datos GTFS Vitoria-Gasteiz (Tuvisa)
# Uso: make <target>   (ejecutar desde ~/Downloads)
# ──────────────────────────────────────────────────────────────────────────────

SWIFT_SRC    = TripUpdatesReader/main.swift
BINARY       = TripUpdatesReader/tripUpdatesReader
DOWNLOAD_SH  = ./download_data.sh

.PHONY: all download run build run-bin refresh clean help

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
	@rm -f $(BINARY)
	@echo "🗑  Binario eliminado"

## Muestra esta ayuda
help:
	@echo ""
	@echo "Targets disponibles:"
	@echo "  make download   Descarga GTFS estático y tripUpdates.pb"
	@echo "  make run        Lee tripUpdates.pb con el intérprete Swift"
	@echo "  make build      Compila el lector Swift en un binario nativo"
	@echo "  make run-bin    Compila si es necesario y ejecuta el binario"
	@echo "  make refresh    download + run  (datos frescos + lectura)"
	@echo "  make all        download + run  (igual que refresh)"
	@echo "  make clean      Elimina el binario compilado"
	@echo ""

