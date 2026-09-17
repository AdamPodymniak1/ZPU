# Tang Nano 20K toolchain on WSL2 setup

## 1. Install the toolchain (inside WSL2/Ubuntu)

```bash
chmod +x setup_toolchain.sh
./setup_toolchain.sh
source ~/.bashrc
```

This installs everything into `~/oss-cad-suite` and adds it to your `PATH`.
It replaces having to build yosys/nextpnr-himbaechel/apicula/openFPGALoader
from source individually — same tools, prebuilt and version-matched.

## 2. USB passthrough: Windows -> WSL2

This is the step that's specific to WSL2 and easy to miss. WSL2 runs in a
lightweight VM and does **not** see USB devices by default, so
`openFPGALoader` won't find the board until you forward it manually. The
Tang Nano 20K uses an onboard BL616 chip as its USB programmer/debugger —
there's no separate FTDI cable to plug in, it's the board's own USB-C port.

**One-time setup (in an elevated/Administrator PowerShell on Windows):**

```powershell
winget install --interactive --exact dorssel.usbipd-win
```

(or download the installer from https://github.com/dorssel/usbipd-win/releases)

**Every time you plug the board in** (Administrator PowerShell):

```powershell
usbipd list
```

Find the Tang Nano 20K / BL616 entry (it may show as "USB Serial Device",
"BL616", or similar — plug/unplug it to see which BUSID changes). Then:

```powershell
usbipd bind --busid <BUSID>          # one-time per device
usbipd attach --wsl --busid <BUSID>  # each session; add -a to auto-reattach
```

**Verify inside WSL2:**

```bash
lsusb
```

You should see the board listed. If `openFPGALoader` still can't open the
device due to permissions, either run it with `sudo` or make sure the udev
rule installed by `setup_toolchain.sh` took effect (`sudo udevadm control
--reload-rules && sudo udevadm trigger`, then unplug/replug).

If the device disconnects/reconnects (e.g. after flashing to SPI flash,
which resets the board), you'll need to `usbipd attach` again unless you
used `-a`.

### "unable to open ftdi device: -4 (usb_open() failed)"

Two separate things commonly cause this on WSL2, even once the board is
visible in `lsusb`:

1. Linux's built-in `ftdi_sio` driver auto-claims both interfaces of the
   FT2232 JTAG/UART chip as `/dev/ttyUSB0` / `/dev/ttyUSB1`, which blocks
   openFPGALoader from opening the device directly.
2. WSL2 usually has no live udev daemon running (unless you've enabled
   systemd), so the `/dev/bus/usb/*` device node never gets its
   permissions relaxed and stays root-only.

`fix_usb_access.sh` fixes both, by VID:PID (default `0403:6010`, the
FT2232 cable used on Tang Nano boards) so it works regardless of which
bus/device numbers get assigned on a given plug-in:

```bash
./fix_usb_access.sh              # uses default 0403:6010
./fix_usb_access.sh 0403 6014    # or pass a different VID PID
```

**`make flash` / `make flash-flash` already run this automatically before
programming**, so in normal use this issue should simply not come up —
you shouldn't need to run the script or think about udev/systemd at all.
It's driven by the `CABLE_VID`/`CABLE_PID` Makefile variables if your
board's cable ever enumerates under a different id:

```bash
make CABLE_VID=0403 CABLE_PID=6014 flash
```

If you want this fixed at the OS level instead (so it also works outside
`make`, e.g. `openFPGALoader --detect` on its own), `setup_toolchain.sh`
installs a matching udev rule — but that only takes effect if a udev
daemon is actually running, which on WSL2 requires enabling systemd:
add `systemd=true` under `[boot]` in `/etc/wsl.conf`, then run
`wsl --shutdown` from PowerShell and reopen your terminal. This is
optional — the Makefile's automatic fallback works either way.

## 3. Build and flash a project

Project layout:

```
src/top.v          <- design (included: a blinky example)
src/top_tb.v        <- testbench (included)
tangnano20k.cst      <- pin constraints (included, matches top.v)
Makefile
```

```bash
make               # synth -> PnR -> pack, produces build/top.fs
make flash          # program to SRAM (volatile - lost on power-off/reset)
make flash-flash     # program to onboard SPI flash (persistent)
make sim TB=top_tb   # simulate with icarus verilog, produces build/top_tb.vcd
make clean
```

For your own project: put your Verilog in `src/`, name the testbench
`<something>_tb.v`, update `tangnano20k.cst` for whatever pins you use, and
either rename your top module `top` or run `make TOP=my_module_name`.

## Notes

- `gowin_pack -d GW2A-18C` — this is the *family* string, not the full part
  number; `nextpnr-himbaechel --device GW2AR-LV18QN88C8/I7` is the full part.
- SRAM programming (`make flash`) is fast and good for iterating; it's wiped
  on power loss. Use `make flash-flash` once you want it to persist, but note
  it's slower and has a limited (though large) number of write cycles.
- If `openFPGALoader --detect` doesn't find the board at all, double check
  the USB passthrough step above before assuming a toolchain problem.
