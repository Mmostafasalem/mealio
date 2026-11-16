import Foundation

enum LocalDataEraser {
    static func clear(defaults: UserDefaults, domain: String) {
        defaults.removePersistentDomain(forName: domain)
    }
}
