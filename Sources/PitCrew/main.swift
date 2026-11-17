import AppKit

// Menu-bar-only app (no Dock icon) that hosts the floating Pit Crew panel.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
