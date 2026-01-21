//
//  ProfileAvatarView.swift
//  FlixorMac
//
//  Reusable profile avatar component with image or gradient initials fallback
//

import SwiftUI
import FlixorKit

struct ProfileAvatarView: View {
    let user: PlexHomeUser
    var size: CGFloat = 60

    // Premium gradient color sets for avatar backgrounds
    private let gradientSets: [(Color, Color)] = [
        (Color(hex: "FF6B6B"), Color(hex: "C44569")),  // Coral Rose
        (Color(hex: "4ECDC4"), Color(hex: "2C7873")),  // Teal
        (Color(hex: "A8E6CF"), Color(hex: "56AB91")),  // Mint
        (Color(hex: "DDA0DD"), Color(hex: "9B59B6")),  // Lavender
        (Color(hex: "FFD93D"), Color(hex: "F39C12")),  // Golden
        (Color(hex: "6C5CE7"), Color(hex: "4834D4")),  // Purple
        (Color(hex: "74B9FF"), Color(hex: "0984E3")),  // Sky Blue
        (Color(hex: "FD79A8"), Color(hex: "E84393")),  // Pink
    ]

    private var gradientColors: (Color, Color) {
        let index = abs(user.id) % gradientSets.count
        return gradientSets[index]
    }

    var body: some View {
        Group {
            if let thumb = user.thumb, !thumb.isEmpty, let url = URL(string: thumb) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        initialsView
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        initialsView
                    @unknown default:
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initialsView: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [gradientColors.0, gradientColors.1],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Subtle inner shadow/highlight
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.2), Color.clear],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: size * 0.8
                    )
                )

            // Initials
            Text(user.initials)
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
        }
    }
}

// MARK: - Active Profile Avatar (for toolbar)

struct ActiveProfileAvatarView: View {
    let profile: ActiveProfile?
    var size: CGFloat = 32

    // Premium gradient color sets
    private let gradientSets: [(Color, Color)] = [
        (Color(hex: "FF6B6B"), Color(hex: "C44569")),
        (Color(hex: "4ECDC4"), Color(hex: "2C7873")),
        (Color(hex: "A8E6CF"), Color(hex: "56AB91")),
        (Color(hex: "DDA0DD"), Color(hex: "9B59B6")),
        (Color(hex: "FFD93D"), Color(hex: "F39C12")),
        (Color(hex: "6C5CE7"), Color(hex: "4834D4")),
        (Color(hex: "74B9FF"), Color(hex: "0984E3")),
        (Color(hex: "FD79A8"), Color(hex: "E84393")),
    ]

    private var gradientColors: (Color, Color) {
        guard let profile = profile else {
            return gradientSets[0]
        }
        let index = abs(profile.userId) % gradientSets.count
        return gradientSets[index]
    }

    private var initials: String {
        guard let profile = profile else {
            return "U"
        }
        let name = profile.title
        let components = name.split(separator: " ")
        if components.count >= 2 {
            let first = components[0].prefix(1)
            let last = components[1].prefix(1)
            return "\(first)\(last)".uppercased()
        }
        return String(name.prefix(1)).uppercased()
    }

    var body: some View {
        Group {
            if let thumb = profile?.thumb, !thumb.isEmpty, let url = URL(string: thumb) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        initialsView
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: size, height: size)
                    case .failure:
                        initialsView
                    @unknown default:
                        initialsView
                    }
                }
                .frame(width: size, height: size)
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initialsView: some View {
        ZStack {
            LinearGradient(
                colors: [gradientColors.0, gradientColors.1],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.2), Color.clear],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: size * 0.8
                    )
                )

            Text(initials)
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
        }
        .frame(width: size, height: size)
    }
}

#if DEBUG
struct ProfileAvatarView_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 20) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "FF6B6B"), Color(hex: "C44569")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 60, height: 60)
                .overlay(
                    Text("D")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                )

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "6C5CE7"), Color(hex: "4834D4")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 60, height: 60)
                .overlay(
                    Text("T")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                )
        }
        .padding()
        .background(Color.black)
    }
}
#endif
