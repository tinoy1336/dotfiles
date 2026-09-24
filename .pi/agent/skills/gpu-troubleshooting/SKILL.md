---
name: gpu-troubleshooting
description: Use when diagnosing GPU hangs/freezes/soft-lockups, dGPU runtime-wake issues, NVIDIA (nvidia-powerd, GSP) or amdgpu (TTM) problems, or hybrid-GPU Vulkan/EGL enumeration side effects. Load this skill whenever the trigger matches; the rules below are binding for that task.
---

# GPU troubleshooting

Load this skill whenever the trigger matches; the rules below are binding for that task.

## nvidia-powerd

**nvidia-powerd = D-STATE DEADLOCK TRIGGER:** ASUS platform-profile switch → Performance makes asusd start nvidia-powerd.service (unit itself disabled; supergfxd GONE — not installed). powerd opens /dev/nvidiactl → dGPU runtime resume → RmInitAdapter/kgspInitRm (GSP boot) hangs holding rmapi rw-semaphore write lock → rm_acpi_nvpcf_notify (kacpi_notify, Dynamic Boost), nvidia-smi, powerd all block D-state forever (kill -9 useless); shutdown SIGTERM times out → forced poweroff. Driver nvidia 610.57.04 open module, RTX 4060 Max-Q (10de:28a0), GPU 0000:c4:00.0. ASUS SBIOS NVPCF interface defective: NVRM PlatformRequestHandler NV_ERR_INVALID_DATA asserts every boot. **FIX APPLIED: `systemctl mask nvidia-powerd.service`** (symlink → /dev/null; reversible `systemctl unmask`; cost = no Dynamic Boost, already broken). If the hang ever recurs AFTER masking, the trigger is not powerd — re-investigate who opened /dev/nvidia*.

## amdgpu TTM

**amdgpu TTM NULL-deref → full freeze after hibernate resume:** kernel `BUG: NULL pointer dereference` in `ttm_lru_bulk_move_del` during a VRAM buffer move corrupts the TTM LRU spinlock → every GPU consumer spins forever (104 soft-lockups). Trigger = AGS gjs normal GPU work ~14 min after S4 wake. NOT NVIDIA/thermal/OOM. Known-class amdgpu TTM LRU race, watch upstream. Full trace: /home/tinoy/context.md.

## Hybrid GPUs + dGPU wake

**Hybrid GPUs + dGPU wake:** AMD iGPU (display) + RTX 4060 Max-Q dGPU (runtime-suspended; `/sys/bus/pci/devices/0000:c4:00.0/power/runtime_status`, fine-grained D3). Waker = **Vulkan ICD enumeration** (GTK 4.16+ defaults to Vulkan on Wayland; Chromium/Electron enumerate too). EGL is NOT the waker. Fix = `VK_ICD_FILENAMES=radeon_icd.json` (+ Mesa EGL pin) in the ags-shell unit + `hl.env()` in hyprland.lua (session-wide; `hyprctl reload` applies live). The shell unit ALSO sets `GSK_RENDERER=gl`: under the Vulkan renderer, gtk4paintablesink's paintable comes up 0x0 after a player window close+reopen → video never binds → decoded frames pile up ~100MB/s → OOM. GL keeps the sink healthy. Launcher's prime-run button clears the pins (`env -u VK_ICD_FILENAMES -u __EGL_VENDOR_LIBRARY_FILENAMES prime-run <cmd>`) — required for the NVIDIA ICD.
