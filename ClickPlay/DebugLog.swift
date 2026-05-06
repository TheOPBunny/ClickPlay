import Foundation

func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    NSLog("%@", message())
    #endif
}

func errorLog(_ message: @autoclosure () -> String) {
    NSLog("%@", message())
}
