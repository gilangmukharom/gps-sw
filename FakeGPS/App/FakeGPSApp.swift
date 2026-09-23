import SwiftUI

@main
@MainActor
struct FakeGPSApp: App {
    private let environment: AppEnvironment
    @StateObject private var trackingViewModel: TrackingViewModel

    init() {
        let environment = AppEnvironment()
        self.environment = environment
        _trackingViewModel = StateObject(
            wrappedValue: TrackingViewModel(locationProvider: environment.locationProvider)
        )
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                TrackingView(viewModel: trackingViewModel)
                #if DEBUG
                    .fakeGPSDebugMenu(provider: environment.switchableLocation)
                #endif
            }
        }
    }
}
