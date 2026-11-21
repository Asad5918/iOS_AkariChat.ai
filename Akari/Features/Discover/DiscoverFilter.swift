import SwiftUI
import MapKit
import CoreLocation
import Observation

enum Gender: String, CaseIterable, Identifiable {
    case woman, man, nonBinary
    var id: String { rawValue }
}

extension Gender {
    var title: String {
        switch self {
        case .woman: "Woman"
        case .man: "Man"
        case .nonBinary: "Non-binary"
        }
    }
}

enum GenderFilter: String, CaseIterable, Identifiable {
    case everyone, women, men, nonBinary
    var id: String { rawValue }

    var title: String {
        switch self {
        case .everyone: "Everyone"
        case .women: "Women"
        case .men: "Men"
        case .nonBinary: "Non-binary"
        }
    }

    func allows(_ gender: Gender) -> Bool {
        switch self {
        case .everyone: true
        case .women: gender == .woman
        case .men: gender == .man
        case .nonBinary: gender == .nonBinary
        }
    }
}

/// Filters applied to the Discover deck. No center means "anywhere".
struct DiscoverFilter: Equatable {
    static let ageBounds = 18...80
    static let radiusBounds = 50.0...12000.0

    var minAge = ageBounds.lowerBound
    var maxAge = ageBounds.upperBound
    var gender: GenderFilter = .everyone
    var centerLat: Double?
    var centerLon: Double?
    var radiusKm = 1000.0

    var center: CLLocationCoordinate2D? {
        get {
            guard let centerLat, let centerLon else { return nil }
            return CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
        }
        set {
            centerLat = newValue?.latitude
            centerLon = newValue?.longitude
        }
    }

    var isActive: Bool { self != DiscoverFilter() }

    func distanceKm(to profile: DemoProfile) -> Double? {
        guard let center else { return nil }
        let a = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let b = CLLocation(latitude: profile.latitude, longitude: profile.longitude)
        return a.distance(from: b) / 1000
    }

    func matches(_ profile: DemoProfile) -> Bool {
        guard (minAge...maxAge).contains(profile.age), gender.allows(profile.gender) else { return false }
        if let km = distanceKm(to: profile) { return km <= radiusKm }
        return true
    }
}

/// One-shot "use my location" helper.
@Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    var coordinate: CLLocationCoordinate2D?
    var denied = false
    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func request() {
        denied = false
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: denied = true
        default: manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
            case .denied, .restricted: self.denied = true
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor in self.coordinate = coordinate }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

struct DiscoverFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DiscoverFilter
    @State private var camera: MapCameraPosition = .automatic
    @State private var location = LocationProvider()
    private let onApply: (DiscoverFilter) -> Void

    init(filter: DiscoverFilter, onApply: @escaping (DiscoverFilter) -> Void) {
        _draft = State(initialValue: filter)
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Age: \(draft.minAge)–\(draft.maxAge)") {
                    RangeSlider(low: $draft.minAge, high: $draft.maxAge, bounds: DiscoverFilter.ageBounds)
                        .frame(height: 36)
                }

                Section("Show me") {
                    Picker("Show me", selection: $draft.gender) {
                        ForEach(GenderFilter.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    mapView
                        .frame(height: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .listRowInsets(EdgeInsets())
                    if draft.center != nil {
                        VStack(alignment: .leading) {
                            Text("Within \(Int(draft.radiusKm)) km")
                            Slider(value: $draft.radiusKm, in: DiscoverFilter.radiusBounds, step: 50) { Text("Distance") }
                        }
                    }
                    HStack {
                        Button {
                            location.request()
                        } label: {
                            Label("Use my location", systemImage: "location.fill")
                        }
                        Spacer()
                        if draft.center != nil {
                            Button("Anywhere", role: .destructive) { draft.center = nil; camera = .automatic }
                        }
                    }
                    .buttonStyle(.borderless)
                } header: {
                    Text("Location")
                } footer: {
                    Text(locationFooter)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") { draft = DiscoverFilter(); camera = .automatic }
                        .disabled(!draft.isActive)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply") { onApply(draft); dismiss() }.bold()
                }
            }
            .onChange(of: location.coordinate?.latitude) {
                if let c = location.coordinate { setCenter(c) }
            }
            .onChange(of: draft.radiusKm) { focusCamera() }
            .onAppear { if draft.center != nil { focusCamera() } }
        }
    }

    private var locationFooter: String {
        if location.denied { return "Location access is off. Tap the map to choose a spot instead, or enable it in Settings." }
        return draft.center == nil ? "Tap the map to drop a pin and only see people within a distance." : "Tap the map to move the pin."
    }

    private var mapView: some View {
        MapReader { proxy in
            Map(position: $camera) {
                ForEach(DemoProfile.all) { profile in
                    Annotation(profile.name, coordinate: profile.coordinate) {
                        Text(profile.emoji)
                            .font(.title3)
                            .padding(4)
                            .background(.thinMaterial, in: Circle())
                            .opacity(draft.matches(profile) ? 1 : 0.35)
                    }
                }
                if let center = draft.center {
                    MapCircle(center: center, radius: draft.radiusKm * 1000)
                        .foregroundStyle(.blue.opacity(0.15))
                        .stroke(.blue, lineWidth: 2)
                    Marker("Here", systemImage: "mappin", coordinate: center)
                        .tint(.blue)
                }
            }
            .onTapGesture { point in
                if let coordinate = proxy.convert(point, from: .local) { setCenter(coordinate) }
            }
        }
    }

    private func setCenter(_ coordinate: CLLocationCoordinate2D) {
        draft.center = coordinate
        focusCamera()
    }

    private func focusCamera() {
        guard let center = draft.center else { return }
        let meters = draft.radiusKm * 1000 * 2.6
        withAnimation { camera = .region(MKCoordinateRegion(center: center, latitudinalMeters: meters, longitudinalMeters: meters)) }
    }
}

/// A single bar with two draggable handles (low and high), whole-number steps.
struct RangeSlider: View {
    @Binding var low: Int
    @Binding var high: Int
    let bounds: ClosedRange<Int>
    private let thumb: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            let span = max(geo.size.width - thumb, 1)
            let count = CGFloat(bounds.upperBound - bounds.lowerBound)
            let lowX = CGFloat(low - bounds.lowerBound) / count * span
            let highX = CGFloat(high - bounds.lowerBound) / count * span
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.systemGray4)).frame(height: 4).padding(.horizontal, thumb / 2)
                Capsule().fill(Color.accentColor)
                    .frame(width: max(highX - lowX, 0), height: 4)
                    .offset(x: lowX + thumb / 2)
                handle.offset(x: lowX)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("track")).onChanged { v in
                        let value = bounds.lowerBound + Int((v.location.x - thumb / 2) / span * count + 0.5)
                        low = min(max(value, bounds.lowerBound), high)
                    })
                handle.offset(x: highX)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("track")).onChanged { v in
                        let value = bounds.lowerBound + Int((v.location.x - thumb / 2) / span * count + 0.5)
                        high = max(min(value, bounds.upperBound), low)
                    })
            }
            .coordinateSpace(name: "track")
            .frame(maxHeight: .infinity)
        }
    }

    private var handle: some View {
        Circle().fill(.white).frame(width: thumb, height: thumb)
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
    }
}
