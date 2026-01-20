//
//  EndpointSelectView.swift
//  FlixorMac
//
//  Endpoint selection screen during onboarding
//

import SwiftUI
import FlixorKit

struct EndpointSelectView: View {
    let server: PlexServerResource
    let onBack: () -> Void
    let onConnected: () -> Void

    @State private var testingURI: String?
    @State private var testResults: [String: TestResult] = [:]
    @State private var protocolFilter: ProtocolFilter = .all
    @State private var customEndpoint: String = ""
    @State private var testingCustom = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    enum TestResult {
        case testing
        case success(Int) // latency in ms
        case failed
    }

    private enum ProtocolFilter: String, CaseIterable, Identifiable {
        case all
        case https
        case http

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: return "All"
            case .https: return "HTTPS"
            case .http: return "HTTP"
            }
        }
    }

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            // Animated gradient background
            AnimatedGradientBackground()

            VStack(spacing: 0) {
                // Header with back button
                HStack {
                    Button {
                        onBack()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.horizontal, 60)
                .padding(.top, 30)

                // Title
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connect to \(server.name)")
                        .font(.system(size: 32, weight: .heavy))
                        .foregroundColor(.white)

                    Text("Select an endpoint to use for this server")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 60)
                .padding(.top, 20)
                .padding(.bottom, 24)

                // Content
                ScrollView {
                    VStack(spacing: 16) {
                        // Protocol filter
                        if !server.connections.isEmpty {
                            protocolPicker
                        }

                        // Endpoints list
                        endpointsList

                        // Custom endpoint section
                        customEndpointSection

                        // Status message
                        if let status = statusMessage {
                            statusMessageView(status)
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.bottom, 40)
                }

                Spacer()
            }
        }
    }

    private var protocolPicker: some View {
        HStack {
            Text("Protocol:")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.5))

            Picker("", selection: $protocolFilter) {
                ForEach(ProtocolFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            Spacer()

            // Test all button
            Button {
                Task { await testAllEndpoints() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "speedometer")
                        .font(.system(size: 12))
                    Text("Test All")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
            .disabled(testingURI != nil)
        }
        .padding(.bottom, 8)
    }

    private var filteredConnections: [PlexConnectionResource] {
        switch protocolFilter {
        case .all:
            return server.connections
        case .https:
            return server.connections.filter { $0.protocol.lowercased() == "https" }
        case .http:
            return server.connections.filter { $0.protocol.lowercased() == "http" }
        }
    }

    private var endpointsList: some View {
        VStack(spacing: 0) {
            if filteredConnections.isEmpty {
                if server.connections.isEmpty {
                    Text("No endpoints available for this server")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.vertical, 20)
                } else {
                    Text("No endpoints match the selected filter")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.vertical, 20)
                }
            } else {
                ForEach(filteredConnections) { connection in
                    EndpointRow(
                        connection: connection,
                        testResult: testResults[connection.uri],
                        isTesting: testingURI == connection.uri,
                        onTest: { Task { await testEndpoint(connection) } },
                        onUse: { Task { await useEndpoint(connection.uri) } }
                    )

                    if connection.id != filteredConnections.last?.id {
                        Divider()
                            .background(Color.white.opacity(0.08))
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var customEndpointSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom Endpoint")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))

            HStack(spacing: 12) {
                TextField("https://your-server.example.com:32400", text: $customEndpoint)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )

                Button("Test") {
                    Task { await testCustomEndpoint() }
                }
                .buttonStyle(.bordered)
                .disabled(customEndpoint.isEmpty || testingCustom)

                Button("Use") {
                    Task { await useEndpoint(customEndpoint) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(customEndpoint.isEmpty || testingCustom)
            }

            Text("Enter a custom endpoint URL if the listed ones don't work")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.top, 16)
    }

    private func statusMessageView(_ message: String) -> some View {
        HStack(spacing: 8) {
            if testingURI != nil || testingCustom {
                ProgressView()
                    .scaleEffect(0.7)
            } else if message.contains("Connected") || message.contains("reachable") {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else if message.contains("failed") || message.contains("Error") {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            } else {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
            }

            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
        )
        .padding(.top, 8)
    }

    // MARK: - Actions

    @MainActor
    private func testEndpoint(_ connection: PlexConnectionResource) async {
        guard testingURI == nil else { return }
        testingURI = connection.uri
        testResults[connection.uri] = .testing
        statusMessage = "Testing \(connection.uri)..."

        let start = CFAbsoluteTimeGetCurrent()

        do {
            // Test using a simple HEAD request
            var request = URLRequest(url: URL(string: connection.uri)!)
            request.httpMethod = "HEAD"
            request.setValue(server.accessToken, forHTTPHeaderField: "X-Plex-Token")
            request.timeoutInterval = 10

            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...399).contains(httpResponse.statusCode) else {
                throw NSError(domain: "EndpointTest", code: -1, userInfo: [NSLocalizedDescriptionKey: "Endpoint unreachable"])
            }

            let latency = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            testResults[connection.uri] = .success(latency)
            statusMessage = "Endpoint reachable (\(latency)ms latency)"
        } catch {
            testResults[connection.uri] = .failed
            statusMessage = "Endpoint test failed"
        }

        testingURI = nil
    }

    @MainActor
    private func testAllEndpoints() async {
        for connection in filteredConnections {
            await testEndpoint(connection)
        }
    }

    @MainActor
    private func testCustomEndpoint() async {
        guard !customEndpoint.isEmpty else { return }
        testingCustom = true
        statusMessage = "Testing custom endpoint..."

        let start = CFAbsoluteTimeGetCurrent()

        do {
            var request = URLRequest(url: URL(string: customEndpoint)!)
            request.httpMethod = "HEAD"
            request.setValue(server.accessToken, forHTTPHeaderField: "X-Plex-Token")
            request.timeoutInterval = 10

            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...399).contains(httpResponse.statusCode) else {
                throw NSError(domain: "EndpointTest", code: -1, userInfo: [NSLocalizedDescriptionKey: "Endpoint unreachable"])
            }

            let latency = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            statusMessage = "Custom endpoint reachable (\(latency)ms latency)"
        } catch {
            statusMessage = "Custom endpoint test failed"
        }

        testingCustom = false
    }

    @MainActor
    private func useEndpoint(_ uri: String) async {
        guard testingURI == nil && !testingCustom else { return }
        testingURI = uri
        statusMessage = "Connecting to endpoint..."
        errorMessage = nil

        do {
            // Connect to the server with this endpoint via FlixorCore
            _ = try await FlixorCore.shared.connectToPlexServerWithUri(server, uri: uri)

            statusMessage = "Connected successfully!"
            print("✅ [EndpointSelect] Connected to \(server.name) via \(uri)")

            // Small delay to show success message
            try? await Task.sleep(nanoseconds: 500_000_000)

            onConnected()
        } catch {
            print("❌ [EndpointSelect] Connection failed: \(error)")
            statusMessage = "Connection failed: \(error.localizedDescription)"
        }

        testingURI = nil
    }
}

// MARK: - Endpoint Row

private struct EndpointRow: View {
    let connection: PlexConnectionResource
    let testResult: EndpointSelectView.TestResult?
    let isTesting: Bool
    let onTest: () -> Void
    let onUse: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Connection info
            VStack(alignment: .leading, spacing: 6) {
                // Badges
                HStack(spacing: 6) {
                    if connection.local {
                        badge("Local", color: .orange)
                    }
                    if connection.relay {
                        badge("Relay", color: .gray)
                    }
                    if connection.IPv6 {
                        badge("IPv6", color: .purple)
                    }

                    // Test result
                    if let result = testResult {
                        switch result {
                        case .testing:
                            ProgressView()
                                .scaleEffect(0.5)
                        case .success(let ms):
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 12))
                                Text("\(ms)ms")
                                    .font(.system(size: 10))
                                    .foregroundColor(.green)
                            }
                        case .failed:
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                                .font(.system(size: 12))
                        }
                    }
                }

                // URI
                Text(connection.uri)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.9))
                    .textSelection(.enabled)
            }

            Spacer()

            // Actions
            HStack(spacing: 8) {
                Button("Test") {
                    onTest()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isTesting)

                Button("Use") {
                    onUse()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isTesting)
            }
        }
        .padding(14)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .cornerRadius(4)
    }
}

// MARK: - Animated Gradient Background

private struct AnimatedGradientBackground: View {
    @State private var animateGradient = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "#1a1a2e"),
                    Color(hex: "#16213e"),
                    Color(hex: "#0f0f23")
                ],
                startPoint: animateGradient ? .topLeading : .bottomTrailing,
                endPoint: animateGradient ? .bottomTrailing : .topLeading
            )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.purple.opacity(0.3), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .offset(x: animateGradient ? 150 : -150, y: animateGradient ? -100 : 100)
                .blur(radius: 60)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.blue.opacity(0.2), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 150
                    )
                )
                .frame(width: 300, height: 300)
                .offset(x: animateGradient ? -100 : 100, y: animateGradient ? 150 : -150)
                .blur(radius: 50)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }
        }
    }
}

#if DEBUG
#Preview {
    EndpointSelectView(
        server: PlexServerResource(
            id: "test",
            name: "Test Server",
            owned: true,
            accessToken: "token",
            publicAddress: nil,
            presence: true,
            connections: []
        ),
        onBack: {},
        onConnected: {}
    )
    .frame(width: 900, height: 700)
}
#endif
