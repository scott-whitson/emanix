# Hardware notes

Recorded for reinstall-on-same-hardware (scenario B). Update whenever the laptop changes.

## Identity
- **Vendor / model:** HP HP Laptop 15-ef2xxx
- **BIOS / firmware version:** F.34
- **Verified on kernel:** 6.19.11-arch1-1

## Key components (lspci / lsusb relevant lines)
- **GPU:** 03:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Lucienne (rev c2)
- **Wifi/Ethernet:** 01:00.0 Network controller: Realtek Semiconductor Co., Ltd. RTL8822CE 802.11ac PCIe Wireless Network Adapter
- **Audio:** 03:00.1 Audio device: Advanced Micro Devices, Inc. [AMD/ATI] Renoir/Cezanne HDMI/DP Audio Controller, 03:00.6 Audio device: Advanced Micro Devices, Inc. [AMD] Ryzen HD Audio Controller

## Quirks / gotchas
- (none discovered yet)

## Firmware updates
- `fwupdmgr refresh && fwupdmgr update` is the usual command if updates are available.
- Check before a reinstall so you're on a known-good BIOS.
