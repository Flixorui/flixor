import SwiftUI

struct ServerConnectionView: View {
    let server: PlexServer
    @Binding var isPresented: Bool
    var onEndpointSelected: (() -> Void)?

    @State private var connections: [PlexConnection] = []
    @State private var isLoading = false
    @State private var testingURI: String?
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var protocolFilter: ProtocolFilter = .all
    @State private var customEndpoint: String = ""
    @State private var testingCustom = false

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
        VStack(alignment: .leading, spacing: 16) {
            header

        if isLoading {
            loadingState
        } else if let errorMessage {
            messageRow(text: errorMessage, style: .error)
        } else {
            if !connections.isEmpty {
                protocolPicker
            }
            connectionList

            // Custom endpoint section
            customEndpointSection
        }

            if let statusMessage { messageRow(text: statusMessage, style: .success) }

            HStack {
                Spacer()
                Button("Close") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560, height: 480)
        .onAppear { Task { await loadConnections() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Connections for \(server.name)")
                .font(.headline)
            Text("Select the endpoint that works best from this Mac. The current backend choice will be highlighted.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Discovering endpoints…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var protocolPicker: some View {
        Picker("Protocol Filter", selection: $protocolFilter) {
            ForEach(ProtocolFilter.allCases) { filter in
                Text(filter.label).tag(filter)
            }
        }
        .pickerStyle(.segmented)
    }

    private var filteredConnections: [PlexConnection] {
        switch protocolFilter {
        case .all:
            return connections
        case .https:
            return connections.filter { normalizedProtocol(for: $0) == "https" }
        case .http:
            return connections.filter { normalizedProtocol(for: $0) == "http" }
        }
    }

    @ViewBuilder
    private var connectionList: some View {
        if filteredConnections.isEmpty {
            if connections.isEmpty {
                messageRow(text: "No endpoints were reported by the backend.", style: .info)
            } else {
                messageRow(text: "No endpoints match the selected filter.", style: .info)
            }
        } else {
            List(filteredConnections) { connection in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(connection.uri)
                            .font(.callout)
                            .textSelection(.enabled)
                        Spacer()
                        if connection.isPreferred == true { badge("Preferred", tint: .green) }
                        if connection.isCurrent == true { badge("Current", tint: .blue) }
                        if connection.local == true { badge("Local", tint: .orange) }
                        if connection.relay == true { badge("Relay", tint: .gray) }
                        if connection.IPv6 == true { badge("IPv6", tint: .purple) }
                    }

                    HStack(spacing: 12) {
                        Button("Test") { Task { await testConnection(connection) } }
                            .disabled(testingURI != nil)

                        Button("Use This") { Task { await select(connection) } }
                            .disabled(connection.isCurrent == true && connection.isPreferred == true || testingURI != nil)

                        if testingURI == connection.uri {
                            ProgressView().scaleEffect(0.6)
                        }

                        Spacer()
                    }
                }
                .padding(.vertical, 4)
            }
            .listStyle(.inset)
        }
    }

    private func normalizedProtocol(for connection: PlexConnection) -> String? {
        if let proto = connection.protocolName?.lowercased() { return proto }
        if let url = URL(string: connection.uri), let scheme = url.scheme?.lowercased() {
            return scheme
        }
        return nil
    }

    // MARK: - Custom Endpoint Section

    private var customEndpointSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Custom Endpoint")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("https://your-server.example.com:32400", text: $customEndpoint)
                    .textFieldStyle(.roundedBorder)

                Button("Test") { Task { await testCustomEndpoint() } }
                    .disabled(customEndpoint.isEmpty || testingURI != nil || testingCustom)

                Button("Use") { Task { await useCustomEndpoint() } }
                    .disabled(customEndpoint.isEmpty || testingURI != nil || testingCustom)

                if testingCustom {
                    ProgressView().scaleEffect(0.6)
                }
            }

            Text("Enter a custom endpoint URL if the listed ones don't work")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 8)
    }

    // MARK: - Load/test/select

    @MainActor
    private func loadConnections() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        statusMessage = nil
        testingURI = nil

        do {
            let response = try await APIClient.shared.getPlexConnections(serverId: server.id)
            connections = response.connections.sorted { $0.uri < $1.uri }
        } catch {
            errorMessage = "Unable to load connections."
            print("❌ [Settings] Failed to fetch connections for \(server.id): \(error)")
        }

        isLoading = false
    }

    @MainActor
    private func testConnection(_ connection: PlexConnection) async {
        guard testingURI == nil else { return }
        testingURI = connection.uri
        errorMessage = nil
        statusMessage = "Testing \(connection.uri)…"

        let start = CFAbsoluteTimeGetCurrent()
        defer { testingURI = nil }

        do {
            _ = try await APIClient.shared.setPlexServerEndpoint(serverId: server.id, uri: connection.uri, test: true)
            let latency = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            statusMessage = "Endpoint reachable (\(latency) ms latency)."
        } catch {
            errorMessage = "Endpoint \(connection.uri) is unreachable."
            statusMessage = nil
            print("❌ [Settings] Endpoint test failed: \(error)")
        }
    }

    @MainActor
    private func select(_ connection: PlexConnection) async {
        guard testingURI == nil else { return }
        testingURI = connection.uri
        errorMessage = nil
        statusMessage = "Setting preferred endpoint…"

        do {
            _ = try await APIClient.shared.setPlexServerEndpoint(serverId: server.id, uri: connection.uri, test: true)
            statusMessage = "Preferred endpoint saved."
            onEndpointSelected?()
            await loadConnections()
        } catch {
            errorMessage = "Unable to save preferred endpoint."
            statusMessage = nil
        }

        testingURI = nil
    }

    @MainActor
    private func testCustomEndpoint() async {
        guard !customEndpoint.isEmpty, testingURI == nil, !testingCustom else { return }
        testingCustom = true
        errorMessage = nil
        statusMessage = "Testing custom endpoint…"

        let start = CFAbsoluteTimeGetCurrent()

        do {
            _ = try await APIClient.shared.setPlexServerEndpoint(serverId: server.id, uri: customEndpoint, test: true)
            let latency = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            statusMessage = "Custom endpoint reachable (\(latency) ms latency)."
        } catch {
            errorMessage = "Custom endpoint is unreachable."
            statusMessage = nil
            print("❌ [Settings] Custom endpoint test failed: \(error)")
        }

        testingCustom = false
    }

    @MainActor
    private func useCustomEndpoint() async {
        guard !customEndpoint.isEmpty, testingURI == nil, !testingCustom else { return }
        testingCustom = true
        errorMessage = nil
        statusMessage = "Setting custom endpoint…"

        do {
            _ = try await APIClient.shared.setPlexServerEndpoint(serverId: server.id, uri: customEndpoint, test: true)
            statusMessage = "Custom endpoint saved."
            onEndpointSelected?()
            await loadConnections()
        } catch {
            errorMessage = "Unable to save custom endpoint."
            statusMessage = nil
        }

        testingCustom = false
    }

    // MARK: - Helpers

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.2))
            .foregroundStyle(tint)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private enum MessageStyle { case error, success, info }

    private func messageRow(text: String, style: MessageStyle) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon(for: style))
            Text(text)
        }
        .font(.footnote)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background(for: style))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func icon(for style: MessageStyle) -> String {
        switch style {
        case .error: return "exclamationmark.triangle.fill"
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func background(for style: MessageStyle) -> Color {
        switch style {
        case .error: return Color.red.opacity(0.12)
        case .success: return Color.green.opacity(0.12)
        case .info: return Color.gray.opacity(0.12)
        }
    }
}
