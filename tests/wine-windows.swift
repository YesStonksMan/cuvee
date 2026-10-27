// SPDX-License-Identifier: LGPL-2.1-or-later
// Lists the windows of Wine processes: pid owner window-id [title] x y width height onscreen layer.
// Wine processes are found by executable path: the loader itself, or the per-program link Wine makes for the Dock.
import CoreGraphics
import Darwin

func isWine(_ pid: pid_t) -> Bool {
  var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
  guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return false }
  let path = String(cString: buf)
  return path.hasSuffix("/wine") || path.contains("/winetemp-")
}

let l = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as! [[String: Any]]
for w in l where isWine(w["kCGWindowOwnerPID"] as! pid_t) {
  let b = w["kCGWindowBounds"] as! [String: Any]
  print(w["kCGWindowOwnerPID"]!, w["kCGWindowOwnerName"]!, w["kCGWindowNumber"]!, "[\(w["kCGWindowName"] ?? "")]", b["X"]!, b["Y"]!, b["Width"]!, b["Height"]!, w["kCGWindowIsOnscreen"] ?? 0, w["kCGWindowLayer"]!)
}
