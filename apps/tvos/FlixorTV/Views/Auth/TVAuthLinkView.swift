import SwiftUI
import CoreImage.CIFilterBuiltins
import FlixorKit

struct TVAuthLinkView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionManager

    @Binding var isPresented: Bool
    @EnvironmentObject private var appState: AppState

    @State private var pin: PlexPinInitResponse?
    @State private var clientId: String = UUID().uuidString
    @State private var isLoading = false
    @State private var error: String?
    @State private var pollTask: Task<Void, Never>?
    @State private var startedAt = Date()
    @State private var secondsRemaining: Int = 300 // default TTL fallback

    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 28) {
                Text("Sign in to Plex")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(.white)

                if let code = pin?.code.uppercased() {
                    HStack(spacing: 14) {
                        ForEach(Array(code), id: \.self) { ch in
                            Text(String(ch))
                                .font(.system(size: 48, weight: .heavy, design: .monospaced))
                                .foregroundStyle(.black)
                                .frame(width: 64, height: 64)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                        }
                    }
                    .padding(.top, 12)

                    Text("Go to plex.tv/link on your phone or scan the QR")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.75))

                    if let qr = qrImage(for: "https://www.plex.tv/link?code=\(code)") {
                        Image(uiImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 220, height: 220)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.2), lineWidth: 1))
                            .padding(.top, 8)
                    }

                    Text("Code expires in \(secondsRemaining)s")
                        .foregroundStyle(.white.opacity(0.6))
                        .font(.callout)
                }

                if isLoading { ProgressView().tint(.white).scaleEffect(1.3) }
                if let error { Text(error).foregroundStyle(.orange) }

                HStack(spacing: 16) {
                    Button("Refresh Code") { Task { await begin() } }
                        .buttonStyle(.bordered)
                    Button("Cancel") { cancelAndDismiss() }
                        .buttonStyle(.bordered)
                }
                .padding(.top, 8)
            }
            .padding(.top, 40)
        }
        .onAppear { Task { await begin() } }
        .onDisappear { pollTask?.cancel() }
    }

    private func begin() async {
        isLoading = true
        error = nil
        pollTask?.cancel()
        do {
            let p = try await api.authPlexPinInit(clientId: clientId)
            await MainActor.run {
                self.pin = p
                self.startedAt = Date()
                self.secondsRemaining = 300
            }
            startTimersAndPolling()
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
        isLoading = false
    }

    private func startTimersAndPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            // countdown timer & polling loop
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                secondsRemaining = max(0, secondsRemaining - 1)

                if secondsRemaining % 2 == 0, let pin = pin {
                    do {
                        let status = try await api.authPlexPinStatus(id: String(pin.id), clientId: pin.clientId)
                        if status.authenticated == true {
                            await session.restoreSession()
                            appState.completeAuth()
                            cancelAndDismiss()
                            break
                        }
                    } catch {
                        // keep polling quietly
                    }
                }

                if secondsRemaining == 0 { break }
            }
        }
    }

    private func cancelAndDismiss() { pollTask?.cancel(); isPresented = false }

    private func qrImage(for string: String) -> UIImage? {
        filter.message = Data(string.utf8)
        if let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) {
            if let cg = context.createCGImage(output, from: output.extent) {
                return UIImage(cgImage: cg)
            }
        }
        return nil
    }
}
