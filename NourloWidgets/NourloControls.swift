import AppIntents
import SwiftUI
import WidgetKit

// Control Center, Lock Screen and Action button controls (iOS 18 and later).

@available(iOS 18.0, *)
struct LogFoodControl: ControlWidget {
    static let kind = "com.mostafa.mealio.control.log-food"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenNourloIntent(screen: .logFood)) {
                Label("Log food", systemImage: "fork.knife.circle")
            }
        }
        .displayName("Log food")
        .description("Opens Nourlo's food logger.")
    }
}

@available(iOS 18.0, *)
struct ScanBarcodeControl: ControlWidget {
    static let kind = "com.mostafa.mealio.control.scan"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenNourloIntent(screen: .scan)) {
                Label("Scan barcode", systemImage: "barcode.viewfinder")
            }
        }
        .displayName("Scan barcode")
        .description("Opens Nourlo's barcode scanner to log a food.")
    }
}
