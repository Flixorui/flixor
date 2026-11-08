//
//  ToastView.swift
//  FlixorMac
//
//  Toast notification component
//

import SwiftUI

struct ToastView: View {
    let message: String
    let type: ToastType
    var duration: TimeInterval = 3.0
    @Binding var isShowing: Bool

    enum ToastType {
        case success
        case error
        case info

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.circle.fill"
            case .info: return "info.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .success: return .green
            case .error: return .red
            case .info: return .blue
            }
        }
    }

    var body: some View {
        HStack(spacing: DS.Space.s12) {
            Image(systemName: type.icon)
                .font(.title3)
                .foregroundStyle(type.color)

            Text(message)
                .font(.body)
                .foregroundStyle(.white)

            Spacer()

            Button(action: {
                isShowing = false
            }) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color.black.opacity(0.9))
        .cornerRadius(DS.Radius.r12)
        .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
        .transition(.move(edge: .top).combined(with: .opacity))
        .onAppear {
            if duration > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                    withAnimation {
                        isShowing = false
                    }
                }
            }
        }
    }
}

// MARK: - Toast Manager

class ToastManager: ObservableObject {
    static let shared = ToastManager()

    @Published var currentToast: Toast?

    struct Toast: Identifiable {
        let id = UUID()
        let message: String
        let type: ToastView.ToastType
        let duration: TimeInterval
    }

    func show(_ message: String, type: ToastView.ToastType = .info, duration: TimeInterval = 3.0) {
        withAnimation {
            currentToast = Toast(message: message, type: type, duration: duration)
        }
    }

    func dismiss() {
        withAnimation {
            currentToast = nil
        }
    }
}

// MARK: - Toast Modifier

struct ToastModifier: ViewModifier {
    @StateObject private var toastManager = ToastManager.shared

    func body(content: Content) -> some View {
        ZStack {
            content

            if let toast = toastManager.currentToast {
                VStack {
                    ToastView(
                        message: toast.message,
                        type: toast.type,
                        duration: toast.duration,
                        isShowing: Binding(
                            get: { toastManager.currentToast != nil },
                            set: { if !$0 { toastManager.dismiss() } }
                        )
                    )
                    .padding()

                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(999)
            }
        }
    }
}

extension View {
    func toast() -> some View {
        modifier(ToastModifier())
    }
}

#if DEBUG && canImport(PreviewsMacros)
#Preview {
    VStack(spacing: DS.Space.s20) {
        ToastView(
            message: "Successfully added to My List",
            type: .success,
            duration: 0,
            isShowing: .constant(true)
        )

        ToastView(
            message: "Failed to load content",
            type: .error,
            duration: 0,
            isShowing: .constant(true)
        )

        ToastView(
            message: "New episode available",
            type: .info,
            duration: 0,
            isShowing: .constant(true)
        )
    }
    .frame(width: 400)
    .padding()
    .background(Color.gray.opacity(0.2))
}
#endif
