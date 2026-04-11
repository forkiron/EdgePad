// main.swift — app entry point.
//
// EdgePad runs as a menu-bar-only NSApplication (LSUIElement in
// Info.plist). AppDelegate wires everything together; this file exists
// purely to bootstrap the NSApp instance.

import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
