// SPDX-License-Identifier: LGPL-2.1-or-later
import CoreGraphics
let l = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as! [[String: Any]]
for w in l where (w["kCGWindowOwnerName"] as? String ?? "") == "wine" || (w["kCGWindowOwnerName"] as? String ?? "").contains("steam") {
  let b = w["kCGWindowBounds"] as! [String: Any]
  print(w["kCGWindowOwnerPID"]!, w["kCGWindowOwnerName"]!, w["kCGWindowNumber"]!, "[\(w["kCGWindowName"] ?? "")]", b["X"]!, b["Y"]!, b["Width"]!, b["Height"]!, w["kCGWindowIsOnscreen"] ?? 0, w["kCGWindowLayer"]!)
}
