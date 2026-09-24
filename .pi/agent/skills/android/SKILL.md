---
name: android
description: Use when any task involves the connected Android phone, adb, or mobile-device control (input injection, settings, screenshots, rotation). Load this skill whenever the trigger matches; the rules below are binding for that task.
---

# Android

Load this skill whenever the trigger matches; the rules below are binding for that task.

## Drive it autonomously

DRIVE CONNECTED ANDROID autonomously (`adb shell input`, `settings put`, `am start`) — don't ask the user to tap/switch.

## Device + tooling facts

**Android + adb:** `android-tools` + `android-udev`; `tinoy` in `adbusers` (re-login to apply). Phone = Samsung Galaxy S24 (SM-S928W, Android 16, 1440×3120, serial R5CX12805ZR, USB 5-1); SwiftKey (`com.touchtype.swiftkey`) default IME. Screenshot: `adb exec-out screencap -p > shot.png`. Landscape: `settings put system accelerometer_rotation 0` + `user_rotation 1` (restore 0/1).
