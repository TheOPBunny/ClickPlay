import Foundation

// Debug logging compiles out of release builds; error logging stays active for user-visible failures.
func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    NSLog("%@", message())
    #endif
}

func errorLog(_ message: @autoclosure () -> String) {
    NSLog("%@", message())
}
