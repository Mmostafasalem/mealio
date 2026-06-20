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
                ForEach(vm.stores) { store in
                    Annotation(store.chain, coordinate: CLLocationCoordinate2D(
                        latitude: store.latitude, longitude: store.longitude)) {
                        StorePinView(
                            store: store,
                            dealCount: vm.dealCount(for: store),
                            isSelected: vm.selectedStore?.id == store.id
                        )
                        .onTapGesture { vm.selectStore(store) }
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls { }                     // suppress default controls — we add our own
            .ignoresSafeArea()
            .onAppear { vm.load(appState: appState) }
            .onChange(of: appState.activeDeals) { _, _ in vm.refreshDeals(appState: appState) }

            // MARK: Overlay controls (bottom-right, above tab bar)
            VStack(spacing: 12) {
                // Re-centre on user location
                Button {
                    vm.centreOnUser()
                } label: {
                    Image(systemName: "location.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Color.brandPrimary)
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }

                // Nearby / All toggle (disabled when no location fix yet)
                Button {
                    vm.showNearbyOnly.toggle()
                    vm.refreshDeals(appState: appState)
                } label: {
                    Image(systemName: vm.showNearbyOnly ? "location.circle.fill" : "globe")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(vm.showNearbyOnly ? Color.brandAmber : Color.secondary)
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
            }
            .padding(.trailing, 16)
            .padding(.bottom, 100)   // clears tab bar (≈ 83pt) + safe area

            // MARK: Store detail sheet
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
                    .background(isSelected ? Color.brandPrimary : Color.white)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 2)

                Image(systemName: "triangle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(isSelected ? Color.brandPrimary : Color.white)
                    .rotationEffect(.degrees(180))
                    .offset(y: -2)
            }

            if dealCount > 0 {
                Text("\(dealCount)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Color.brandPrimary)
                    .clipShape(Circle())
                    .offset(x: 4, y: -4)
            }
        }
        .animation(.spring(duration: 0.2), value: isSelected)
    }
}
