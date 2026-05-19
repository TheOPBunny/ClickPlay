import Cocoa

// AppKit entry point: keep the delegate alive for the lifetime of NSApplicationMain.
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
