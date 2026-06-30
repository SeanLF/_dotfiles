#!/usr/bin/env swift
//
// kbbl — control the MacBook keyboard backlight from the CLI.
//
//   kbbl up   [steps]   brighten (default 1 step)
//   kbbl down [steps]   dim
//   kbbl toggle         on/off (unreliable on some models -- prefer up/down)
//
// WHY THIS APPROACH (the short version of a long investigation):
//   On Apple Silicon / macOS 26+ the built-in keyboard backlight is owned
//   exclusively by SkyLight/WindowServer. The CoreBrightness private API
//   (KeyboardBrightnessClient.setBrightness:forKeyboard:), which every
//   known tool uses (KBPulse, mac-brightnessctl), is ACCEPTED by
//   corebrightnessd but never reaches the panel for an unentitled binary;
//   it's decorative. The Control Center slider works only because it carries
//   Apple-private entitlements (SkyLight.displaycontrol) that AMFI won't let
//   a self-signed binary hold.
//
//   The one path that needs no entitlement and no driver: post an
//   NSSystemDefined "aux key" HID event for NX_KEYTYPE_ILLUMINATION_UP/DOWN
//   (21/22). It enters the trusted input path exactly like the old F5/F6
//   illumination keys, so SkyLight drives the backlight. We become the
//   keyboard instead of asking the daemon.
//
// Caveat: the app that triggers this (Terminal, Automator/Shortcuts runner)
// may need Accessibility permission to post HID events.
//
import Cocoa

// NX_KEYTYPE_* from IOKit/hidsystem/ev_keymap.h
let ILLUMINATION_UP = 21, ILLUMINATION_DOWN = 22, ILLUMINATION_TOGGLE = 23

func postAux(_ key: Int, down: Bool) {
    let state = down ? 0xa : 0xb   // key-state nibble; the flags rawValue is this value << 8
    let flags = NSEvent.ModifierFlags(rawValue: UInt(state << 8))
    let data1 = (key << 16) | (state << 8)
    guard let event = NSEvent.otherEvent(
        with: .systemDefined, location: .zero, modifierFlags: flags,
        timestamp: 0, windowNumber: 0, context: nil,
        subtype: 8 /* NX_SUBTYPE_AUX_CONTROL_BUTTONS */, data1: data1, data2: -1
    ), let cgEvent = event.cgEvent else {
        die("kbbl: failed to build HID event\n")
    }
    cgEvent.post(tap: .cghidEventTap)
}

// A brief key-down hold is required: macOS debounces a zero-duration synthetic
// press away (a lone down/up does nothing), so without this `kbbl up 1` is a no-op.
let holdMicros: UInt32 = 60_000
// Pause between presses when ramping multiple steps in one invocation.
let stepGapMicros: UInt32 = 60_000

func press(_ key: Int) {
    postAux(key, down: true)
    usleep(holdMicros)
    postAux(key, down: false)
}

func die(_ msg: String) -> Never {
    FileHandle.standardError.write(Data(msg.utf8)); exit(2)
}

let args = CommandLine.arguments
guard args.count >= 2 else { die("usage: kbbl up|down|toggle [steps]\n") }

let key: Int
switch args[1] {
case "up":     key = ILLUMINATION_UP
case "down":   key = ILLUMINATION_DOWN
case "toggle": key = ILLUMINATION_TOGGLE
default:       die("kbbl: unknown command '\(args[1])'\n")
}

let steps: Int
if args.count > 2 {
    guard let n = Int(args[2]), n >= 1 else { die("kbbl: invalid steps '\(args[2])'\n") }
    steps = n
} else {
    steps = 1
}

for i in 0..<steps {
    press(key)
    if i + 1 < steps { usleep(stepGapMicros) }
}
