import SwiftUI
import MapKit

struct StoreMapView: View {

    @State private var vm = StoreMapViewModel()
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack(alignment: .bottomTrailing) {

            // MARK: Map
            Map(position: $vm.cameraPosition, interactionModes: .all) {
                // User location dot
                UserAnnotation()

                // Store pins
                ForEach(vm.visibleStores) { store in
                    Annotation(store.chain, coordinate: CLLocationCoordinate2D(
                        latitude: store.latitude, longitude: store.longitude)) {
                        Button { vm.selectStore(store) } label: { StorePinView(
                            store: store,
                            dealCount: vm.dealCount(for: store),
                            isSelected: vm.selectedStore?.id == store.id
                        ).frame(minWidth: 44, minHeight: 44) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(store.name), \(store.address)")
                        .accessibilityHint("Shows catalog estimates for this chain. Branch stock is not verified.")
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls { }                     // suppress default controls — we add our own
            .ignoresSafeArea()
            .onAppear { vm.load(appState: appState) }
            .onChange(of: appState.activeDeals) { _, _ in vm.refreshDeals(appState: appState) }

            // MARK: Overlay controls (bottom-right, above tab bar)
            VStack(spacing: Spacing.md) {
                // Re-centre on user location
                Button {
                    vm.centreOnUser()
                } label: {
                    Image(systemName: "location.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.onAccent)
                        .frame(width: 46, height: 46)
                        .background(Color.coral)
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
                .accessibilityLabel("Centre map on my location")

                // Nearby / All toggle (disabled when no location fix yet)
                Button {
                    vm.showNearbyOnly.toggle()
                    vm.refreshDeals(appState: appState)
                } label: {
                    Image(systemName: vm.showNearbyOnly ? "location.circle.fill" : "globe")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(vm.showNearbyOnly ? Color.onAccent : Color.labelPrimary)
                        .frame(width: 46, height: 46)
                        .background(vm.showNearbyOnly ? Color.coral : Color.surfaceSecondary)
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
                .disabled(LocationService.shared.userLocation == nil)
                .opacity(LocationService.shared.userLocation == nil ? 0.5 : 1)
                .accessibilityLabel(LocationService.shared.userLocation == nil
                    ? "Location required for nearby stores"
                    : (vm.showNearbyOnly ? "Showing nearby stores only" : "Showing all stores"))
                .accessibilityHint("Requires your location. Filters actual Maps branches within eight kilometres.")
            }
            .padding(.trailing, Spacing.lg)
            .padding(.bottom, 100)   // clears tab bar (≈ 83pt) + safe area

            // MARK: Store detail sheet
        }
        .overlay(alignment: .top) {
            if vm.isLoadingStores {
                HStack { ProgressView(); Text("Finding stores…").font(.subheadline) }
                    .padding(Spacing.lg)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card))
                    .padding(Spacing.lg)
            } else if let message = vm.storeLookupMessage {
                VStack(spacing: Spacing.sm) {
                    Label(message, systemImage: "mappin.slash.circle")
                        .font(.subheadline)
                    Button("Retry") { vm.loadRealStores() }
                        .frame(minHeight: 44)
                }
                .padding(Spacing.lg)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card))
                .padding(Spacing.lg)
            }
        }
        .sheet(item: $vm.selectedStore) { store in
            StoreDetailSheet(store: store, vm: vm)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Store pin

private struct StorePinView: View {
    let store: Store
    let dealCount: Int
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 2) {
                Text(store.chainIcon)
                    .font(.title2)
                    .frame(width: isSelected ? 48 : 40, height: isSelected ? 48 : 40)
                    .background(isSelected ? Color.coral : Color.paper)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 2)

                Image(systemName: "triangle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(isSelected ? Color.coral : Color.paper)
                    .rotationEffect(.degrees(180))
                    .offset(y: -2)
            }

            if dealCount > 0 {
                Text("\(dealCount)")
                    .font(.caption2.bold())
                    .foregroundStyle(Color.onAccent)
                    .padding(4)
                    .background(Color.coral)
                    .clipShape(Circle())
                    .offset(x: 4, y: -4)
            }
        }
        .animation(.spring(duration: 0.2), value: isSelected)
    }
}
