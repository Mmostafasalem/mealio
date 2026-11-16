/// A deliberately local-only build for a free Apple Personal Team.
/// Production and ordinary Debug builds retain their original capabilities.
enum BuildCapabilities {
    #if MEALIO_LOCAL_PHONE_TEST && !DEBUG
    #error("MEALIO_LOCAL_PHONE_TEST must never be used for a Release build.")
    #endif

    static var supportsAppleServices: Bool {
        #if MEALIO_LOCAL_PHONE_TEST
        false
        #else
        true
        #endif
    }
}
