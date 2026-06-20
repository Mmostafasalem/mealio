import Foundation

/// Lightweight debug logger. No-ops in release builds, so nothing is written
/// to the device console in production. Use instead of `print`.
nonisolated func appLog(_ items: Any..., file: String = #fileID) {
    #if DEBUG
    let name = (file as NSString).lastPathComponent
    print("[\(name)]", items.map { "\($0)" }.joined(separator: " "))
    #endif
}
