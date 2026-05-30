import SwiftUI
import MapKit

struct StoreMapView: View {

    @State private var vm = StoreMapViewModel()

    var body: some View {
        Map(position: $vm.cameraPosition) {
            UserAnnotation()

            ForEach(vm.uniqueStores) { store in
                Annotation(
                    store.chain,
                    coordinate: CLLocationCoordinate2D(
                        latitude: store.latitude,
                        longitude: store.longitude
                    )
                ) {
                    StorePinView(
                        store: store,
                        isSelected: vm.selectedStore?.id == store.id,
                        dealCount: vm.deals.filter { $0.store.id == store.id }.count
                    ) {
                        vm.selectStore(store)
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapUserLocationButton()
        }
        .ignoresSafeArea()
        .sheet(item: $vm.selectedStore) { store in
            StoreDetailSheet(store: store, vm: vm)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .overlay(alignment: .top) {
            if vm.isLoadingDeals {
                ProgressView()
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.top, 60)
            }
        }
        .task { await vm.load() }
        .onAppear { LocationService.shared.startUpdating() }
    }
}

// MARK: - StorePinView

struct StorePinView: View {

    let store: Store
    let isSelected: Bool
    let dealCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                // Main pin circle
                ZStack {
                    Circle()
                        .fill(Color(hex: store.chainColor))
                        .frame(width: 40, height: 40)
                        .shadow(color: Color(hex: store.chainColor).opacity(0.4), radius: isSelected ? 8 : 4, y: 2)

                    Text(String(store.chain.prefix(1)))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }

                // Deal count badge
                if dealCount > 0 {
                    Text("\(dealCount)")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.white)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Color.brandPrimary)
                        .clipShape(Circle())
                        .offset(x: 4, y: -4)
                }
            }
            .scaleEffect(isSelected ? 1.3 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

#Preview {
    StoreMapView()
}
