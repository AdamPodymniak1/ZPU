# ---------------------------------------------------------------------------
# Makefile for Tang Nano 20K (Gowin GW2AR-18C) Verilog projects
#
# Layout expected:
#   ./src/*.v              -- your Verilog sources (design)
#   ./src/*_tb.v           -- testbenches (optional, for `make sim`)
#   ./tangnano20k.cst      -- pin constraints file
#
# Usage:
#   make TOP=top                # synth + PnR + pack -> build/top.fs
#   make sim TB=my_tb            # simulate testbench with icarus verilog
#   make flash                   # program SRAM (volatile, lost on power-off)
#   make flash-flash              # program onboard SPI flash (persistent)
#   make clean
# ---------------------------------------------------------------------------

TOP        ?= top
BOARD      ?= tangnano20k
DEVICE     ?= GW2AR-LV18QN88C8/I7
FAMILY     ?= GW2A-18C
CST        ?= tangnano20k.cst

CABLE_VID  ?= 0403
CABLE_PID  ?= 6010

SRC_DIR    := src
BUILD_DIR  := build

SRC        := $(wildcard $(SRC_DIR)/*.v)
# exclude testbenches (files ending in _tb.v) from synthesis sources
SYNTH_SRC  := $(filter-out %_tb.v,$(SRC))

JSON       := $(BUILD_DIR)/$(TOP).json
PNR_JSON   := $(BUILD_DIR)/$(TOP)_pnr.json
FS         := $(BUILD_DIR)/$(TOP).fs

.PHONY: all synth pnr pack flash flash-flash fix-usb sim clean

all: $(FS)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# --- Synthesis ---------------------------------------------------------
synth: $(JSON)

$(JSON): $(SYNTH_SRC) | $(BUILD_DIR)
	yosys -p "read_verilog $(SYNTH_SRC); synth_gowin -top $(TOP) -json $(JSON)"

# --- Place & Route ------------------------------------------------------
pnr: $(PNR_JSON)

$(PNR_JSON): $(JSON) $(CST) | $(BUILD_DIR)
	nextpnr-himbaechel \
		--json $(JSON) \
		--write $(PNR_JSON) \
		--device $(DEVICE) \
		--vopt family=$(FAMILY) \
		--vopt cst=$(CST)

# --- Bitstream packing ---------------------------------------------------
pack: $(FS)

$(FS): $(PNR_JSON) | $(BUILD_DIR)
	gowin_pack -d $(FAMILY) -o $(FS) $(PNR_JSON)

# --- Programming ----------------------------------------------------------
fix-usb:
	@./fix_usb_access.sh $(CABLE_VID) $(CABLE_PID)

# SRAM: fast, volatile, lost on power cycle. Good for iterating.
flash: $(FS) fix-usb
	openFPGALoader -b $(BOARD) $(FS)

# Onboard SPI flash: persists across power cycles.
flash-flash: $(FS) fix-usb
	openFPGALoader -b $(BOARD) -f $(FS)

# --- Simulation -------------------------------------------------------
# make sim TB=my_tb   -> compiles src/my_tb.v + design sources, runs it,
# produces build/<TB>.vcd for gtkwave.
TB ?= $(TOP)_tb
sim: | $(BUILD_DIR)
	iverilog -o $(BUILD_DIR)/$(TB).vvp $(SRC_DIR)/$(TB).v $(SYNTH_SRC)
	cd $(BUILD_DIR) && vvp $(TB).vvp
	@echo "If your testbench has \$$dumpfile/\$$dumpvars, open the .vcd with:"
	@echo "  gtkwave $(BUILD_DIR)/*.vcd"

clean:
	rm -rf $(BUILD_DIR)
