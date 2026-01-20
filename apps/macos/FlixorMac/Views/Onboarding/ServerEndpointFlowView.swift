//
//  ServerEndpointFlowView.swift
//  FlixorMac
//
//  Container view that manages the server → endpoint selection flow during onboarding
//

import SwiftUI
import FlixorKit

enum ServerFlowStep {
    case serverSelect
    case endpointSelect(PlexServerResource)
}

struct ServerEndpointFlowView: View {
    @State private var currentStep: ServerFlowStep = .serverSelect

    var body: some View {
        Group {
            switch currentStep {
            case .serverSelect:
                ServerSelectView { server in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentStep = .endpointSelect(server)
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .leading),
                    removal: .move(edge: .leading)
                ))

            case .endpointSelect(let server):
                EndpointSelectView(
                    server: server,
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentStep = .serverSelect
                        }
                    },
                    onConnected: {
                        // Connection successful - RootView will detect isPlexServerConnected
                        // and transition to OnboardingView
                        print("✅ [ServerEndpointFlow] Connection established, transitioning...")
                    }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .trailing)
                ))
            }
        }
    }
}

#if DEBUG
#Preview {
    ServerEndpointFlowView()
        .frame(width: 900, height: 700)
}
#endif
