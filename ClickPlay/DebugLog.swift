import Foundation

// Debug logging compiles out of release builds; error logging stays active for user-visible failures.
func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    NSLog("%@", message())
    #endif
}

func debugLatencyLog(_ message: @autoclosure () -> String, eventTimestamp: TimeInterval? = nil) {
    #if DEBUG
    let now = ProcessInfo.processInfo.systemUptime
    if let eventTimestamp {
        NSLog(
            "[Latency] %@ t=%.3fms event=%.3fms eventAge=%.3fms",
            message(),
            now * 1000,
            eventTimestamp * 1000,
            (now - eventTimestamp) * 1000
        )
    } else {
        NSLog("[Latency] %@ t=%.3fms", message(), now * 1000)
    }
    #endif
}

func errorLog(_ message: @autoclosure () -> String) {
    NSLog("%@", message())
}
