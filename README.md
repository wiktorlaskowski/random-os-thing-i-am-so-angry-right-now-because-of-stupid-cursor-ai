# PMOMS

PMOMS is a tiny BIOS-bootable 64-bit hobby operating system image designed to
start in VirtualBox and immediately present a modern VESA framebuffer GUI.

## Features

- **Bootable in VirtualBox** as a raw 1.44 MiB floppy image (`build/pmoms.img`).
- **x86-64 long mode kernel**: the boot path enables A20, PAE paging, and IA-32e
  long mode before entering the PMOMS kernel.
- **VESA linear framebuffer GUI**: the BIOS stage requests a 32-bit VESA mode
  and passes the linear framebuffer to the 64-bit renderer.
- **Modern desktop mock UI**: PMOMS draws a gradient wallpaper, top status bar,
  glass-like side panel, main app window, colorful cards, dock, app icons, and
  PMOMS branding.
- **Modern-technology groundwork**: the boot code is structured around long mode,
  identity-mapped high framebuffer access, CPUID-compatible x86-64 execution,
  and GUI tiles reserved for ACPI, PCIe, USB, networking, and future drivers.

## Build

```sh
make image
```

The generated boot image is written to:

```text
build/pmoms.img
```

## Run in VirtualBox

1. Create a new VM with type **Other/Unknown (64-bit)**.
2. Open **Settings → Storage**.
3. Add a **Floppy Controller** if one is not present.
4. Attach `build/pmoms.img` as the floppy disk.
5. Boot the VM.

PMOMS should switch to a 32-bit VESA graphics mode and render the GUI directly
from the 64-bit kernel.

## Repository layout

```text
Makefile              Build rules for the PMOMS boot image
src/boot/pmoms.asm    Boot sector, VESA setup, long-mode entry, GUI renderer
```
