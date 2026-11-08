//
//  EndpointSelectView.swift
//  FlixorMac
//
//  Endpoint selection screen during onboarding - auto-tests and recommends best endpoint
//

import SwiftUI
import FlixorKit

struct EndpointSelectView: View {
    @Environment(\.flixorTheme) private var theme
    let server: PlexServerResource
    let onBack: () -> Void
    let onConnected: () -> Void

    // Auto-test state
    @State private var isAutoTesting = true
    @State private var autoTestProgress: String = String(localized: "Testing connections...")
    @State private var selectedConnection: PlexConnectionResource?
    @State private var selectedConnectionType: ConnectionType?

    // Manual override state
    @State private var showManualOverride = false
    @State private var showIPv6Endpoints = false
    @State private var testingURI: String?
    @State private var testResults: [String: TestResult] = [:]
    @State private var customEndpoint: String = ""
    @State private var testingCustom = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var isConnecting = false

    /// Filtered connections (excluding IPv6 unless toggled)
    private var filteredConnections: [PlexConnectionResource] {
        if showIPv6Endpoints {
            return server.connections
        } else {
            return server.connections.filter { !$0.IPv6 }
        }
    }

    enum TestResult {
        case testing
        case success(Int) // latency in ms
        case failed
    }

    enum ConnectionType: String {
        case local = "Local"
        case remote = "Remote"
        case relay = "Relay"

        var color: Color {
            switch self {
            case .local: return .green
            case .remote: return .blue
            case .relay: return .orange
            }
        }

        var icon: String {
            switch self {
            case .local: return "house.fill"
            case .remote: return "globe"
            case .relay: return "arrow.triangle.swap"
            }
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !theme.pureBlack {
                AnimatedGradientBackground()
            }

            VStack(spacing: 0) {
                // Header with back button
                HStack {
                    Button {
                        onBack()
                    } label: {
                        HStack(spacing: DS.Space.s6) {
                            Image(systemName: "chevron.left")
                                .font(.flixorIcon(DS.Icon.xs, weight: .semibold))
                            Text("Back")
                                .font(.flixor(.body, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, DS.Space.s60)
                .padding(.top, 30)

                // Title
                VStack(alignment: .leading, spacing: DS.Space.s8) {
                    Text("Connect to \(server.name)")
                        .font(.flixor(.display, weight: .heavy))
                        .foregroundColor(.white)

                    Text(isAutoTesting ? "Finding the best connection..." : "Ready to connect")
                        .font(.flixor(.bodyLarge))
                        .foregroundColor(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Space.s60)
                .padding(.top, DS.Space.s20)
                .padding(.bottom, DS.Space.s32)

                // Main content
                if isAutoTesting {
                    autoTestingView
                } else if let connection = selectedConnection, let type = selectedConnectionType {
                    selectedConnectionView(connection: connection, type: type)
                } else {
                    noConnectionView
                }

                Spacer()
            }
        }
        .task {
            await autoTestEndpoints()
        }
    }

    // MARK: - Auto Testing View

    private var autoTestingView: some View {
        VStack(spacing: DS.Space.s24) {
            // Progress indicator
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 4)
                    .frame(width: 80, height: 80)

                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            }

            Text(autoTestProgress)
                .font(.flixor(.body))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Selected Connection View

    private func selectedConnectionView(connection: PlexConnectionResource, type: ConnectionType) -> some View {
        ScrollView {
            VStack(spacing: DS.Space.s24) {
                // Success card
                VStack(spacing: DS.Space.s16) {
                    // Icon and type
                    HStack(spacing: DS.Space.s12) {
                        ZStack {
                            Circle()
                                .fill(type.color.opacity(0.2))
                                .frame(width: 56, height: 56)

                            Image(systemName: type.icon)
                                .font(.flixorIcon(DS.Icon.xl))
                                .foregroundColor(type.color)
                        }

                        VStack(alignment: .leading, spacing: DS.Space.s4) {
                            HStack(spacing: DS.Space.s8) {
                                Text("\(type.localizedRawValue) Connection")
                                    .font(.flixor(.title3, weight: .semibold))
                                    .foregroundColor(.white)

                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }

                            Text("Best available connection found")
                                .font(.flixor(.callout))
                                .foregroundColor(.white.opacity(0.5))
                        }

                        Spacer()
                    }

                    // URI display
                    HStack {
                        Text(connection.uri)
                            .font(.flixor(.callout, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        if let result = testResults[connection.uri], case .success(let ms) = result {
                            Text("\(ms)ms")
                                .font(.flixor(.footnote, weight: .medium))
                                .foregroundColor(.green)
                                .padding(.horizontal, DS.Space.s8)
                                .padding(.vertical, DS.Space.s4)
                                .background(Color.green.opacity(0.15))
                                .cornerRadius(DS.Radius.r6)
                        }
                    }
                    .padding(DS.Space.s12)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(DS.Radius.r8)

                    // Continue button
                    Button {
                        Task { await useEndpoint(connection.uri) }
                    } label: {
                        HStack(spacing: DS.Space.s8) {
                            if isConnecting {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            Text(isConnecting ? "Connecting..." : "Continue")
                                .font(.flixor(.bodyLarge, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Space.s14)
                        .background(theme.accent)
                        .foregroundColor(theme.onAccent)
                        .cornerRadius(DS.Radius.r10)
                    }
                    .buttonStyle(.plain)
                    .disabled(isConnecting)
                }
                .padding(DS.Space.s20)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.r16)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.r16)
                                .stroke(type.color.opacity(0.3), lineWidth: 1)
                        )
                )

                // Manual override section
                manualOverrideSection
            }
            .padding(.horizontal, DS.Space.s60)
            .padding(.bottom, DS.Space.s40)
        }
    }

    // MARK: - No Connection View

    private var noConnectionView: some View {
        VStack(spacing: DS.Space.s24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.flixorIcon(DS.Icon.huge))
                .foregroundColor(.orange)

            VStack(spacing: DS.Space.s8) {
                Text("No Working Connection Found")
                    .font(.flixor(.title3, weight: .semibold))
                    .foregroundColor(.white)

                Text("All endpoints failed to connect. Try a custom endpoint below.")
                    .font(.flixor(.body))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }

            // Custom endpoint for fallback
            customEndpointSection
                .padding(.horizontal, DS.Space.s60)

            Button("Retry Auto-Test") {
                Task { await autoTestEndpoints() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Manual Override Section

    private var manualOverrideSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s12) {
            Button {
                withAnimation(DS.Motion.standard) {
                    showManualOverride.toggle()
                }
            } label: {
                HStack {
                    Text("Choose a different endpoint")
                        .font(.flixor(.body, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))

                    Spacer()

                    Image(systemName: showManualOverride ? "chevron.up" : "chevron.down")
                        .font(.flixorIcon(DS.Icon.xs, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.vertical, DS.Space.s12)
            }
            .buttonStyle(.plain)

            if showManualOverride {
                VStack(spacing: DS.Space.s12) {
                    // Endpoints list
                    endpointsList

                    // Custom endpoint
                    customEndpointSection
                }
            }
        }
    }

    // MARK: - Endpoints List

    private var endpointsList: some View {
        VStack(spacing: DS.Space.s8) {
            // IPv6 toggle if there are IPv6 connections
            if server.connections.contains(where: { $0.IPv6 }) {
                HStack {
                    Spacer()
                    Toggle(isOn: $showIPv6Endpoints) {
                        Text("Show IPv6")
                            .font(.flixor(.footnote))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }
            }

            VStack(spacing: 0) {
                ForEach(filteredConnections) { connection in
                    EndpointRow(
                        connection: connection,
                        testResult: testResults[connection.uri],
                        isSelected: selectedConnection?.uri == connection.uri,
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
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.r12)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.r12)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Custom Endpoint Section

    private var customEndpointSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s10) {
            Text("Custom Endpoint")
                .font(.flixor(.footnote, weight: .medium))
                .foregroundColor(.white.opacity(0.5))

            HStack(spacing: DS.Space.s10) {
                TextField("https://your-server.example.com:32400", text: $customEndpoint)
                    .textFieldStyle(.plain)
                    .font(.flixor(.callout))
                    .foregroundColor(.white)
                    .padding(DS.Space.s10)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(DS.Radius.r8)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.r8)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )

                Button("Test") {
                    Task { await testCustomEndpoint() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(customEndpoint.isEmpty || testingCustom)

                Button("Use") {
                    Task { await useEndpoint(customEndpoint) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(customEndpoint.isEmpty || testingCustom || isConnecting)
            }
        }
    }

    // MARK: - Auto Test Logic

    @MainActor
    private func autoTestEndpoints() async {
        isAutoTesting = true
        selectedConnection = nil
        selectedConnectionType = nil
        testResults = [:]
        autoTestProgress = String(localized: "Testing all connections...")

        // Filter out IPv6 connections for auto-test (prefer IPv4)
        let nonIPv6Connections = server.connections.filter { !$0.IPv6 }

        // Mark all as testing
        for conn in nonIPv6Connections {
            testResults[conn.uri] = .testing
        }

        // Test all connections in parallel
        await withTaskGroup(of: (PlexConnectionResource, TestResult, Int).self) { group in
            for connection in nonIPv6Connections {
                group.addTask {
                    let start = CFAbsoluteTimeGetCurrent()
                    do {
                        var request = URLRequest(url: URL(string: connection.uri)!)
                        request.httpMethod = "HEAD"
                        request.setValue(self.server.accessToken, forHTTPHeaderField: "X-Plex-Token")
                        request.timeoutInterval = 8

                        let (_, response) = try await URLSession.shared.data(for: request)
                        guard let httpResponse = response as? HTTPURLResponse,
                              (200...399).contains(httpResponse.statusCode) else {
                            return (connection, .failed, 0)
                        }

                        let latency = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                        return (connection, .success(latency), latency)
                    } catch {
                        return (connection, .failed, 0)
                    }
                }
            }

            // Collect results
            for await (connection, result, _) in group {
                testResults[connection.uri] = result
            }
        }

        // Find the best working connection (priority: Local → Remote → Relay, then by latency)
        let workingConnections = nonIPv6Connections.filter { conn in
            if case .success = testResults[conn.uri] {
                return true
            }
            return false
        }

        // Sort by type priority, then by latency
        let sortedWorking = workingConnections.sorted { conn1, conn2 in
            let type1 = connectionType(for: conn1)
            let type2 = connectionType(for: conn2)

            // First sort by connection type priority
            let order: [ConnectionType] = [.local, .remote, .relay]
            let idx1 = order.firstIndex(of: type1) ?? 2
            let idx2 = order.firstIndex(of: type2) ?? 2

            if idx1 != idx2 {
                return idx1 < idx2
            }

            // Then sort by latency (lower is better)
            let latency1: Int
            let latency2: Int
            if case .success(let ms) = testResults[conn1.uri] { latency1 = ms } else { latency1 = Int.max }
            if case .success(let ms) = testResults[conn2.uri] { latency2 = ms } else { latency2 = Int.max }
            return latency1 < latency2
        }

        if let bestConnection = sortedWorking.first {
            selectedConnection = bestConnection
            selectedConnectionType = connectionType(for: bestConnection)
        }

        isAutoTesting = false
        if selectedConnection == nil {
            autoTestProgress = String(localized: "No connections available")
        }
    }

    private func connectionType(for connection: PlexConnectionResource) -> ConnectionType {
        if connection.local {
            return .local
        } else if connection.relay {
            return .relay
        } else {
            return .remote
        }
    }

    // MARK: - Manual Test/Use Actions

    @MainActor
    private func testEndpoint(_ connection: PlexConnectionResource) async {
        guard testingURI == nil else { return }
        testingURI = connection.uri
        testResults[connection.uri] = .testing
        statusMessage = String(localized: "Testing \(connection.uri)...")

        let start = CFAbsoluteTimeGetCurrent()

        do {
            var request = URLRequest(url: URL(string: connection.uri)!)
            request.httpMethod = "HEAD"
            request.setValue(server.accessToken, forHTTPHeaderField: "X-Plex-Token")
            request.timeoutInterval = 10

            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...399).contains(httpResponse.statusCode) else {
                throw NSError(domain: "EndpointTest", code: -1)
            }

            let latency = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            testResults[connection.uri] = .success(latency)
            statusMessage = String(localized: "Endpoint reachable (\(String(latency))ms)")
        } catch {
            testResults[connection.uri] = .failed
            statusMessage = String(localized: "Endpoint test failed")
        }

        testingURI = nil
    }

    @MainActor
    private func testCustomEndpoint() async {
        guard !customEndpoint.isEmpty else { return }
        testingCustom = true
        statusMessage = String(localized: "Testing custom endpoint...")

        let start = CFAbsoluteTimeGetCurrent()

        do {
            var request = URLRequest(url: URL(string: customEndpoint)!)
            request.httpMethod = "HEAD"
            request.setValue(server.accessToken, forHTTPHeaderField: "X-Plex-Token")
            request.timeoutInterval = 10

            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...399).contains(httpResponse.statusCode) else {
                throw NSError(domain: "EndpointTest", code: -1)
            }

            let latency = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            statusMessage = String(localized: "Custom endpoint reachable (\(String(latency))ms)")
        } catch {
            statusMessage = String(localized: "Custom endpoint test failed")
        }

        testingCustom = false
    }

    @MainActor
    private func useEndpoint(_ uri: String) async {
        guard !isConnecting else { return }
        isConnecting = true
        statusMessage = String(localized: "Connecting...")

        do {
            _ = try await FlixorCore.shared.connectToPlexServerWithUri(server, uri: uri)
            print("✅ [EndpointSelect] Connected to \(server.name) via \(uri)")

            try? await Task.sleep(nanoseconds: 300_000_000)
            onConnected()
        } catch {
            print("❌ [EndpointSelect] Connection failed: \(error)")
            statusMessage = String(localized: "Connection failed: \(error.localizedDescription)")
            isConnecting = false
        }
    }
}

// MARK: - Endpoint Row

private struct EndpointRow: View {
    let connection: PlexConnectionResource
    let testResult: EndpointSelectView.TestResult?
    let isSelected: Bool
    let isTesting: Bool
    let onTest: () -> Void
    let onUse: () -> Void

    private var connectionType: EndpointSelectView.ConnectionType {
        if connection.local {
            return .local
        } else if connection.relay {
            return .relay
        } else {
            return .remote
        }
    }

    var body: some View {
        HStack(spacing: DS.Space.s12) {
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                // Badges
                HStack(spacing: DS.Space.s6) {
                    badge(connectionType.rawValue, color: connectionType.color)

                    if connection.IPv6 {
                        badge("IPv6", color: .purple)
                    }

                    if isSelected {
                        badge(String(localized: "Selected"), color: .green)
                    }

                    // Test result
                    if let result = testResult {
                        switch result {
                        case .testing:
                            ProgressView()
                                .scaleEffect(0.5)
                        case .success(let ms):
                            HStack(spacing: DS.Space.s4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.flixorIcon(DS.Icon.xs))
                                Text("\(ms)ms")
                                    .font(.flixor(.micro))
                                    .foregroundColor(.green)
                            }
                        case .failed:
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                                .font(.flixorIcon(DS.Icon.xs))
                        }
                    }
                }

                Text(connection.uri)
                    .font(.flixor(.footnote))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            HStack(spacing: DS.Space.s8) {
                Button("Test") { onTest() }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(isTesting)

                Button("Use") { onUse() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .disabled(isTesting)
            }
        }
        .padding(DS.Space.s12)
        .background(isSelected ? Color.white.opacity(0.03) : Color.clear)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.flixor(.micro, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, DS.Space.s6)
            .padding(.vertical, DS.Space.s2)
            .background(color.opacity(0.15))
            .cornerRadius(DS.Radius.r4)
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
