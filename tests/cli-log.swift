// SPDX-License-Identifier: LGPL-2.1-or-later
// Checks how Cuvee.app runs the CLI and keeps its log, against a fake `cuvee` in a throwaway home folder:
//   swiftc -parse-as-library launcher/Library.swift tests/cli-log.swift -o /tmp/cli-log-test
//   CFFIXED_USER_HOME="$(mktemp -d)" /tmp/cli-log-test
import Foundation

@main
struct CLILogTests {
    static func main() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // never against the real home: this test replaces runtime/cuvee and fills the log
        precondition(home != String(cString: getpwuid(getuid()).pointee.pw_dir), "run with CFFIXED_USER_HOME set to a throwaway folder")
        try FileManager.default.createDirectory(at: cli.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
            case "$1" in
              fail) echo "cuvee: bottle 'X' is running: quit its programs first" >&2; exit 1 ;;
              slow) for i in 1 2 3 4 5 6; do echo "slow $i"; sleep 0.5; done ;;
              ok)   echo fine ;;
            esac
            """.write(to: cli, atomically: true, encoding: .utf8)
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); checks += 1
        }
        func run(_ arg: String) -> (wait: () -> (Int32, String?), Void) {
            let done = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var result: (Int32, String?) = (-1, nil)
            try! CLI.run([arg]) { status, reason in result = (status, reason); done.signal() }
            return ({ done.wait(); return result }, ())
        }
        func log() -> String { (try? String(contentsOf: logFile, encoding: .utf8)) ?? "" }

        // a failure carries the CLI's own words
        let failed = run("fail").wait()
        check(failed.0 == 1, "exit code of a failed command")
        check(failed.1 == "bottle 'X' is running: quit its programs first", "reason of a failed command")
        check(run("ok").wait().1 == nil, "no reason for a command that worked")

        // two commands writing at once: the long one must not write over the short one
        let slow = run("slow")
        Thread.sleep(forTimeInterval: 0.8)
        _ = run("ok").wait()
        _ = slow.wait()
        check(log().components(separatedBy: "fine").count == 3, "the short command's output survives the long one")
        check((1...6).allSatisfy { log().contains("slow \($0)") }, "the long command's output is whole")

        // past 20 MB the log is emptied in place: a command still running goes on in the new log, not in the old one
        let long = run("slow")
        Thread.sleep(forTimeInterval: 0.8)
        let filler = try FileHandle(forWritingTo: logFile)
        try filler.seekToEnd()
        try filler.write(contentsOf: Data(repeating: 0x2e, count: CLI.maxLogBytes + 1))
        try filler.close()
        _ = run("ok").wait()
        _ = long.wait()
        let old = logFile.deletingLastPathComponent().appending(path: "Cuvee.old.log")
        let oldSize = (try FileManager.default.attributesOfItem(atPath: old.path))[.size] as? Int ?? 0
        let newSize = (try FileManager.default.attributesOfItem(atPath: logFile.path))[.size] as? Int ?? 0
        check(oldSize > CLI.maxLogBytes, "the old log holds what was there")
        check(newSize < 1024, "the live log restarts small (\(newSize) bytes)")
        check(log().contains("slow 6") && log().contains("fine"), "running and new commands both write the new log")
        print("PASS: \(checks) CLI log checks")
    }
}
