---
name: aur-packaging
description: Use when building, installing, or packaging AUR packages — makepkg, PKGBUILD edits, yay builds, -bin package strips. Load this skill whenever the trigger matches; the rules below are binding for that task.
---

# AUR packaging

Load this skill whenever the trigger matches; the rules below are binding for that task.

## Parallel builds

**makepkg.conf parallelized:** `MAKEFLAGS="-j$(nproc)"` (24 threads; expands at source time, bash-sourced) + `COMPRESSXZ=(xz -c -T $(nproc) -z -)` (COMPRESSZST already `-T0`). Applies to ALL makepkg/AUR builds — yay stays serial ACROSS packages (parallel download only); cross-package parallelism needs yayp fork. Some PKGBUILDs hard-override `-j1`.

## Bun binaries + strip

**Bun-compiled binaries break when stripped:** pacman/makepkg strips ELF on install; `bun build --compile` loses its embedded app → bare `bun` runtime. AUR `-bin` packages MUST set `options=(!strip)`.
