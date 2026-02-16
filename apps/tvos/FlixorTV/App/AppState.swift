import Foundation
import SwiftUI
import FlixorKit

final class AppState: ObservableObject {
    enum Phase { case unauthenticated, linking, authenticated }

    @Published var phase: Phase = .unauthenticated
    @Published var selectedDestination: MainTVDestination = .home

    func startLinking() { phase = .linking }
    func completeAuth() { phase = .authenticated; selectedDestination = .home }
}
