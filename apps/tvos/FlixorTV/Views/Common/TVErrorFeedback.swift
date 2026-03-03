import SwiftUI

struct ShakeEffect: GeometryEffect {
    var amplitude: CGFloat = 14
    var shakesPerUnit: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(
                translationX: amplitude * sin(animatableData * .pi * shakesPerUnit),
                y: 0
            )
        )
    }
}

struct TVAnimatedErrorState<Actions: View>: View {
    let systemImage: String
    let title: String
    let message: String
    let accent: Color
    let actions: Actions

    @Environment(\.tvThemePalette) private var theme
    @Environment(\.tvTypography) private var typography

    @State private var pulse = false
    @State private var shakeTrigger: CGFloat = 0

    init(
        systemImage: String = "exclamationmark.triangle.fill",
        title: String,
        message: String,
        accent: Color,
        @ViewBuilder actions: () -> Actions
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.accent = accent
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: systemImage)
                .font(.system(size: 62, weight: .bold))
                .foregroundStyle(accent)

            Text(title)
                .font(typography.title)
                .foregroundStyle(theme.textPrimary)

            Text(message)
                .font(typography.body)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 620)

            actions
                .padding(.top, 8)
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 36)
        .frame(maxWidth: 760)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(theme.surfaceGlass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(accent.opacity(0.4), lineWidth: 1.5)
        )
        .modifier(ShakeEffect(animatableData: shakeTrigger))
        .scaleEffect(pulse ? 1 : 0.985)
        .opacity(pulse ? 1 : 0.92)
        .shadow(color: .black.opacity(0.34), radius: 24, y: 14)
        .onAppear {
            pulse = true
            triggerShake()
        }
        .onChange(of: message) { _ in
            triggerShake()
        }
        .animation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true), value: pulse)
    }

    private func triggerShake() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.42)) {
            shakeTrigger += 1
        }
    }
}

