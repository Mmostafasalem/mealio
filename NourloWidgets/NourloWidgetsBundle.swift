import WidgetKit
import SwiftUI

// The widget extension: home-screen and lock-screen widgets, the workout
// Live Activity, and the Control Center buttons. Feature code lives in the
// other files in this folder; shared data types are in ../Shared.

@main
struct NourloWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CaloriesWidget()
        MealsWidget()
        WorkoutLiveActivity()
        if #available(iOS 18.0, *) {
            LogFoodControl()
            ScanBarcodeControl()
        }
    }
}
