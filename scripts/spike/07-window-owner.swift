// Which process owns the visible League client window? (No screen-recording permission needed
// for bounds/PID/owner; window names are only filled in with that permission.)
// Run: swift scripts/spike/07-window-owner.swift
import AppKit
import CoreGraphics

let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
let screen0Height = NSScreen.screens.first?.frame.height ?? 0
for info in list {
    let owner = info[kCGWindowOwnerName as String] as? String ?? "?"
    guard owner.localizedCaseInsensitiveContains("league") || owner.localizedCaseInsensitiveContains("riot")
    else { continue }
    let pid = info[kCGWindowOwnerPID as String] as? Int ?? -1
    let layer = info[kCGWindowLayer as String] as? Int ?? -1
    let name = info[kCGWindowName as String] as? String ?? "<no name>"
    let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
    let app = NSRunningApplication(processIdentifier: pid_t(pid))
    print("pid=\(pid) owner=\(owner) bundle=\(app?.bundleIdentifier ?? "?") layer=\(layer) name=\(name)")
    let cgY = bounds["Y"] ?? 0, height = bounds["Height"] ?? 0
    print("   CG bounds=\(bounds)  AppKit y=\(screen0Height - cgY - height)")
}
