import Foundation
import SwiftUI
import FlixorKit

final class AppState: ObservableObject {
    enum Phase { case unauthenticated, linking, authenticated }

    @Published var phase: Phase = .unauthenticated
    @Published var selectedTab: MainTVView.Tab = .home
    @Published var backendHealthy: Bool = false

    func startLinking() { phase = .linking }
    func completeAuth() { phase = .authenticated; selectedTab = .home }
}

