// Prints the CGWindowID of the first on-screen, layer-0 window owned by the
// given process, for use with `screencapture -l`. Avoids AppleScript (and its
// Automation permission) entirely.
//
// Run: swift Tests/screenshots/window-id.swift <pid>
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2, let pid = Int32(CommandLine.arguments[1]) else {
    FileHandle.standardError.write(Data("usage: window-id.swift <pid>\n".utf8))
    exit(2)
}

let windows = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
) as? [[String: Any]] ?? []

for window in windows {
    guard let owner = window[kCGWindowOwnerPID as String] as? Int32, owner == pid,
          let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
          let number = window[kCGWindowNumber as String] as? Int else { continue }
    print(number)
    exit(0)
}

FileHandle.standardError.write(Data("window-id: no on-screen window for pid \(pid)\n".utf8))
exit(1)
