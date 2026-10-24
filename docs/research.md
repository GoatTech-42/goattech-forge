# Ender 3 V3 SE firmware research (Oct 2026)

Groundwork for the GoatTech firmware. Sources linked inline.

## Hardware

- 220 x 220 x 250 mm bed-slinger, Sprite direct drive, CR Touch, 3.2" color
  serial screen (TJC/DWIN family, TJC3224T132_011N) with a knob, not touch.
- Two mainboard revisions exist with different MCUs and flash procedures:
  - CR4NS200320C13 - GD32F303RET6 (flashes like STM32F103, 28 KiB bootloader
    offset, plain .bin from the SD card root)
  - CR4NS200320C14 - STM32F401RET6 (flashes from an /STM32F4_UPDATE/ folder)
- A binary for one revision does not boot on the other. Board label and MCU
  both need confirming before any binary is selected - at least one unit has
  been reported with a C14 label but a GD chip, so neither label nor chip
  brand alone is treated as proof.
- Sources:
  - https://wiki.creality.com/en/3d-printer-accessories/ender-3v3-se-c14-nebula-screen-firmware-upgrade
  - https://github.com/jpcurti/ender3-v3-se-klipper-with-display/issues/148
  - https://github.com/navaismo/Ender-3V3-SE/issues/96

## Stock firmware

- Current official release: V1.1.0 (May 2025) on Creality's download page.
  This is the recovery source - matched to the exact board before use.
- Creality's published GPL source: https://github.com/CrealityOfficial/Ender-3V3-SE
- Download page: https://www.creality.com/pages/download-ender-3-v3-se

## Community firmware landscape

1. navaismo/Ender-3V3-SE - "Community Edition" (GPLv3, ~300 stars).
   Marlin 2.0 based. Split level menu, 6x6 grid, fixed SD print info, CR Touch
   test UI, custom extrusion menu, buzzer mute, statistics, M593 input shaping,
   M900 linear advance. Development ended - the C13 ran out of flash/RAM.
   https://github.com/navaismo/Ender-3V3-SE
2. navaismo/Marlin_bugfix_2.1_E3V3SE - the active successor (GPLv3).
   Marlin bugfix-2.1.x. Branches: c13_sd, c13_octoprint, c14_sd, c14_octoprint.
   FT_MOTION input shaping with runtime M493 shaper config, SD gcode thumbnails,
   one-click print, LCD dimming, M600 fixes, optional power-loss recovery.
   Upstream marks the C14 profile as awaiting printer validation.
   https://github.com/navaismo/Marlin_bugfix_2.1_E3V3SE
3. Klipper - works on this printer and the stock screen can be kept via
   jpcurti's serial-bridge project. Needs an always-on host (Raspberry Pi or
   similar). Not the default route; an option if a host is already available.
   https://github.com/jpcurti/ender3-v3-se-klipper-with-display
   https://github.com/0xD34D/klipper_ender3_v3_se

## Build verification

Both current upstream branches compile cleanly (PlatformIO):
c13_sd (STM32F103RET6_creality) and c14_sd (STM32F401RE_creality).
Compilation is not hardware validation - first runs on a real printer follow
upstream's calibration checklist.

## Display customization

- Screen firmware is built with TJC's editor (tutorials on the TJC wiki);
  community discussion: https://github.com/navaismo/Ender-3V3-SE/discussions/202
- Community skin tooling: https://github.com/capekoviroboti/creality-dwin-lcd-customizer
