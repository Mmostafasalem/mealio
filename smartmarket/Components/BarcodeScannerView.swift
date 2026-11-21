import SwiftUI
import VisionKit
import AVFoundation
import Vision

/// A scanned retail barcode and what the camera said it was.
struct ScannedBarcode: Equatable {
    let payload: String
    let symbology: GTIN.Symbology
}

/// The barcode scanner sheet: camera with highlighting and guidance, an honest
/// message when camera access is off (with a way to Settings), and Cancel.
struct BarcodeScannerSheet: View {
    let onScan: (ScannedBarcode) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var access = BarcodeScannerView.cameraAccess

    var body: some View {
        NavigationStack {
            Group {
                switch access {
                case .authorized:
                    if BarcodeScannerView.isReady {
                        BarcodeScannerView { code in
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            onScan(code)
                            dismiss()
                        }
                        .ignoresSafeArea(edges: .bottom)
                        .overlay(alignment: .bottom) { hint }
                        .accessibilityLabel("Camera viewfinder")
                        .accessibilityHint("Point the camera at the barcode on the package")
                    } else {
                        message(title: "The scanner isn't available right now",
                                detail: "The camera may be in use by another app. Close this and try again, or search for the food instead.",
                                showSettings: false)
                    }
                case .notDetermined:
                    ProgressView("Asking for camera access…")
                        .task {
                            _ = await AVCaptureDevice.requestAccess(for: .video)
                            access = BarcodeScannerView.cameraAccess
                        }
                case .denied, .restricted:
                    message(title: "Camera access is off",
                            detail: "Nourlo uses the camera only to read barcodes on food packages. Turn on Camera for Nourlo in Settings to scan, or search for the food instead.",
                            showSettings: access == .denied)
                @unknown default:
                    message(title: "The scanner isn't available", detail: "Search for the food instead.", showSettings: false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.surfaceGrouped)
            .navigationTitle("Scan barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("scanner.cancel")
                }
            }
            // Coming back from Settings with access granted.
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                access = BarcodeScannerView.cameraAccess
            }
        }
    }

    private var hint: some View {
        Text("Hold the barcode inside the frame")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.black.opacity(0.6), in: Capsule())
            .padding(.bottom, 32)
            .accessibilityHidden(true)
    }

    private func message(title: String, detail: String, showSettings: Bool) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "camera.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.labelSecondary)
                .accessibilityHidden(true)
            Text(title).font(.headline).multilineTextAlignment(.center)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center)
            if showSettings, let url = URL(string: UIApplication.openSettingsURLString) {
                // Not bordered-prominent: its tint turns almost white in dark mode.
                Button { openURL(url) } label: {
                    Text("Open Settings")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.onAccent)
                        .padding(.horizontal, Spacing.xl)
                        .frame(minHeight: 44)
                        .background(Color.dullPink, in: Capsule())
                        .contentShape(Capsule())
                }
                    .buttonStyle(ScalePressStyle())
                    .accessibilityIdentifier("scanner.openSettings")
            }
        }
        .padding(Spacing.xl)
        .accessibilityElement(children: .contain)
    }
}

/// VisionKit's live scanner, reading retail barcodes only. Reports the first
/// valid code once, then stops.
struct BarcodeScannerView: UIViewControllerRepresentable {
    let onScan: (ScannedBarcode) -> Void

    /// The device has a camera and chip that can run the live scanner.
    static var isSupported: Bool { DataScannerViewController.isSupported }
    /// Supported, and camera access granted and not restricted.
    static var isReady: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }
    static var cameraAccess: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .video) }

    /// Whether the logger shows its "Scan barcode" button. Shown while access is
    /// undecided or denied (the sheet asks, or explains); hidden when the device
    /// can't scan or the camera is restricted.
    static var shouldOffer: Bool {
        NourloTips.shouldOfferScan(isSupported: isSupported, cameraRestricted: cameraAccess == .restricted)
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        guard !controller.isScanning, !context.coordinator.didFinish else { return }
        try? controller.startScanning()
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (ScannedBarcode) -> Void
        var didFinish = false

        init(onScan: @escaping (ScannedBarcode) -> Void) { self.onScan = onScan }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            take(addedItems, from: dataScanner)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            take([item], from: dataScanner)
        }

        private func take(_ items: [RecognizedItem], from scanner: DataScannerViewController) {
            guard !didFinish else { return }
            for item in items {
                guard case .barcode(let barcode) = item, let payload = barcode.payloadStringValue else { continue }
                let symbology: GTIN.Symbology = switch barcode.observation.symbology {
                case .upce: .upce
                case .ean8: .ean8
                default: .unknown
                }
                // Skip misreads; keep scanning until a valid code comes in.
                guard GTIN.normalize(payload, symbology: symbology) != nil else { continue }
                didFinish = true
                scanner.stopScanning()
                onScan(ScannedBarcode(payload: payload, symbology: symbology))
                return
            }
        }
    }
}
