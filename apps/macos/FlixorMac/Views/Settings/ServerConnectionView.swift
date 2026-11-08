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
    @State private var showIPv6: Bool = false
    @State private var customEndpoint: String = ""
    @State private var testingCustom = false

    private enum ProtocolFilter: String, CaseIterable, Identifiable {
        case all, https, http
        var id: String { rawValue }
        var label: String { rawValue == "all" ? "All" : rawValue.uppercased() }
    }

    private enum ConnectionType: String {
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
    }

    private func connectionType(for connection: PlexConnection) -> ConnectionType {
        if connection.local == true { return .local }
        else if connection.relay == true { return .relay }
        else { return .remote }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                Text("Connections for \(server.name)")
                    .font(.flixor(.bodyLarge, weight: .semibold))
                Text("Select the endpoint that works best from this Mac")
                    .font(.flixor(.footnote))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, DS.Space.s16)

            if isLoading {
                loadingState
            } else if let error = errorMessage, connections.isEmpty {
                messageRow(text: error, style: .error)
            } else {
                // Filters
                filtersRow
                    .padding(.bottom, DS.Space.s12)

                // Connection list
                connectionList

                // Custom endpoint
                customEndpointSection
                    .padding(.top, DS.Space.s12)
            }

            // Status message
            if let status = statusMessage {
                messageRow(text: status, style: .success)
                    .padding(.top, DS.Space.s12)
            }
            if let error = errorMessage, !connections.isEmpty {
                messageRow(text: error, style: .error)
                    .padding(.top, DS.Space.s12)
            }

            Spacer(minLength: 16)

            // Close button
            HStack {
                Spacer()
                Button("Close") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DS.Space.s24)
        .frame(width: 520, height: 480)
        .onAppear { Task { await loadConnections() } }
    }

    private var loadingState: some View {
        VStack(spacing: DS.Space.s12) {
            ProgressView()
            Text("Loading endpoints…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filtersRow: some View {
        HStack(spacing: DS.Space.s12) {
            Picker("", selection: $protocolFilter) {
                ForEach(ProtocolFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 160)

            Spacer()

            if connections.contains(where: { $0.IPv6 == true }) {
                Toggle("IPv6", isOn: $showIPv6)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
    }

    private var filteredConnections: [PlexConnection] {
        var filtered = connections

        switch protocolFilter {
        case .all: break
        case .https: filtered = filtered.filter { normalizedProtocol(for: $0) == "https" }
        case .http: filtered = filtered.filter { normalizedProtocol(for: $0) == "http" }
        }

        if !showIPv6 {
            filtered = filtered.filter { $0.IPv6 != true }
        }

        return filtered
    }

    @ViewBuilder
    private var connectionList: some View {
        if filteredConnections.isEmpty {
            messageRow(
                text: connections.isEmpty ? "No endpoints available" : "No endpoints match filters",
                style: .info
            )
        } else {
            ScrollView {
                VStack(spacing: DS.Space.s8) {
                    ForEach(filteredConnections) { connection in
                        connectionCard(connection)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
    }

    private func connectionCard(_ connection: PlexConnection) -> some View {
        let isCurrent = connection.isCurrent == true
        let type = connectionType(for: connection)

        return HStack(spacing: DS.Space.s12) {
            // Type indicator
            Circle()
                .fill(type.color)
                .frame(width: 8, height: 8)

            // URI
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text(connection.uri)
                    .font(.flixor(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: DS.Space.s6) {
                    Text(type.rawValue)
                        .font(.flixor(.micro, weight: .medium))
                        .foregroundStyle(type.color)

                    if isCurrent {
                        Text("Current")
                            .font(.flixor(.micro, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    if connection.IPv6 == true {
                        Text("IPv6")
                            .font(.flixor(.micro, weight: .medium))
                            .foregroundStyle(.purple)
                    }
                }
            }

            Spacer()

            // Actions
            if testingURI == connection.uri {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 50)
            } else {
                HStack(spacing: DS.Space.s6) {
                    Button("Test") {
                        Task { await testConnection(connection) }
                    }
                    .buttonStyle(.plain)
                    .font(.flixor(.caption, weight: .medium))
                    .foregroundStyle(.blue)
                    .disabled(testingURI != nil)

                    if !isCurrent {
                        Button("Use") {
                            Task { await select(connection) }
                        }
                        .buttonStyle(.plain)
                        .font(.flixor(.caption, weight: .medium))
                        .padding(.horizontal, DS.Space.s10)
                        .padding(.vertical, DS.Space.s4)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .cornerRadius(DS.Radius.r4)
                        .disabled(testingURI != nil)
                    }
                }
            }
        }
        .padding(.horizontal, DS.Space.s12)
        .padding(.vertical, DS.Space.s10)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.r8)
                .fill(isCurrent ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.r8)
                        .stroke(isCurrent ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private func normalizedProtocol(for connection: PlexConnection) -> String? {
        if let proto = connection.protocolName?.lowercased() { return proto }
        if let url = URL(string: connection.uri), let scheme = url.scheme?.lowercased() { return scheme }
        return nil
    }

    // MARK: - Custom Endpoint

    private var customEndpointSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s8) {
            Text("Custom Endpoint")
                .font(.flixor(.caption, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: DS.Space.s8) {
                TextField("https://custom-server:32400", text: $customEndpoint)
                    .textFieldStyle(.roundedBorder)
                    .font(.flixor(.caption))

                if testingCustom {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 40)
                } else {
                    Button("Test") {
                        Task { await testCustomEndpoint() }
                    }
                    .disabled(customEndpoint.isEmpty || testingURI != nil)

                    Button("Use") {
                        Task { await useCustomEndpoint() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(customEndpoint.isEmpty || testingURI != nil)
                }
            }
            .controlSize(.small)
        }
    }

    // MARK: - Actions

    @MainActor
    private func loadConnections() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        statusMessage = nil

        do {
            let response = try await APIClient.shared.getPlexConnections(serverId: server.id)
            connections = response.connections.sorted { conn1, conn2 in
                if conn1.isCurrent == true && conn2.isCurrent != true { return true }
                if conn2.isCurrent == true && conn1.isCurrent != true { return false }

                let type1 = connectionType(for: conn1)
                let type2 = connectionType(for: conn2)
                let order: [ConnectionType] = [.local, .remote, .relay]
                let idx1 = order.firstIndex(of: type1) ?? 2
                let idx2 = order.firstIndex(of: type2) ?? 2
                if idx1 != idx2 { return idx1 < idx2 }

                return conn1.uri < conn2.uri
            }
        } catch {
            errorMessage = "Failed to load connections"
        }

        isLoading = false
    }

    @MainActor
    private func testConnection(_ connection: PlexConnection) async {
        guard testingURI == nil else { return }
        testingURI = connection.uri
        errorMessage = nil
        statusMessage = nil

        let start = CFAbsoluteTimeGetCurrent()

        do {
            _ = try await APIClient.shared.setPlexServerEndpoint(serverId: server.id, uri: connection.uri, test: true)
            let latency = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            statusMessage = "Reachable (\(latency)ms)"
        } catch {
            errorMessage = "Connection failed"
        }

        testingURI = nil
    }

    @MainActor
    private func select(_ connection: PlexConnection) async {
        guard testingURI == nil else { return }
        testingURI = connection.uri
        errorMessage = nil
        statusMessage = nil

        do {
            _ = try await APIClient.shared.setPlexServerEndpoint(serverId: server.id, uri: connection.uri, test: true)
            statusMessage = "Endpoint updated"
            onEndpointSelected?()
            await loadConnections()
        } catch {
            errorMessage = "Failed to update endpoint"
        }

        testingURI = nil
    }

    @MainActor
    private func testCustomEndpoint() async {
        guard !customEndpoint.isEmpty, !testingCustom else { return }
        testingCustom = true
        errorMessage = nil
        statusMessage = nil

        let start = CFAbsoluteTimeGetCurrent()

        do {
            _ = try await APIClient.shared.setPlexServerEndpoint(serverId: server.id, uri: customEndpoint, test: true)
            let latency = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            statusMessage = "Reachable (\(latency)ms)"
        } catch {
            errorMessage = "Connection failed"
        }

        testingCustom = false
    }

    @MainActor
    private func useCustomEndpoint() async {
        guard !customEndpoint.isEmpty, !testingCustom else { return }
        testingCustom = true
        errorMessage = nil
        statusMessage = nil

        do {
            _ = try await APIClient.shared.setPlexServerEndpoint(serverId: server.id, uri: customEndpoint, test: true)
            statusMessage = "Endpoint updated"
            onEndpointSelected?()
            await loadConnections()
        } catch {
            errorMessage = "Failed to update endpoint"
        }

        testingCustom = false
    }

    // MARK: - Helpers

    private enum MessageStyle { case error, success, info }

    private func messageRow(text: String, style: MessageStyle) -> some View {
        HStack(spacing: DS.Space.s6) {
            Image(systemName: style == .error ? "exclamationmark.circle.fill" :
                    style == .success ? "checkmark.circle.fill" : "info.circle.fill")
                .font(.flixorIcon(DS.Icon.xs))
            Text(text)
                .font(.flixor(.footnote))
        }
        .foregroundStyle(style == .error ? .red : style == .success ? .green : .secondary)
        .padding(.horizontal, DS.Space.s12)
        .padding(.vertical, DS.Space.s8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.r6)
                .fill(style == .error ? Color.red.opacity(0.1) :
                        style == .success ? Color.green.opacity(0.1) : Color.primary.opacity(0.03))
        )
    }
}
