//
//  IntegrationIcons.swift
//  FlixorMac
//
//  Monochrome SVG icons for integrations - matching mobile app
//

import SwiftUI

// MARK: - Plex Icon

struct PlexIcon: View {
    var size: CGFloat = 24
    var color: Color = .secondary

    var body: some View {
        GeometryReader { _ in
            Path { path in
                // Chevron shape from mobile SVG
                let scale = size / 512
                path.move(to: CGPoint(x: 256 * scale, y: 70 * scale))
                path.addLine(to: CGPoint(x: 148 * scale, y: 70 * scale))
                path.addLine(to: CGPoint(x: 256 * scale, y: 256 * scale))
                path.addLine(to: CGPoint(x: 148 * scale, y: 442 * scale))
                path.addLine(to: CGPoint(x: 256 * scale, y: 442 * scale))
                path.addLine(to: CGPoint(x: 364 * scale, y: 256 * scale))
                path.closeSubpath()
            }
            .fill(color)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Trakt Icon

struct TraktIcon: View {
    var size: CGFloat = 24
    var color: Color = .secondary

    var body: some View {
        Image(systemName: "circle")
            .font(.system(size: size * 0.8, weight: .light))
            .foregroundStyle(color)
            .overlay(
                Image(systemName: "line.diagonal")
                    .font(.system(size: size * 0.5, weight: .medium))
                    .foregroundStyle(color)
                    .rotationEffect(.degrees(-45))
            )
            .frame(width: size, height: size)
    }
}

// MARK: - MDBList Icon

struct MDBListIcon: View {
    var size: CGFloat = 24
    var color: Color = .secondary

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.15, style: .continuous)
                .fill(color)

            // M shape cutout
            Text("M")
                .font(.system(size: size * 0.6, weight: .bold, design: .rounded))
                .foregroundStyle(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - TMDB Icon

struct TMDBIcon: View {
    var size: CGFloat = 24
    var color: Color = .secondary

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.15, style: .continuous)
                .fill(color)

            VStack(spacing: 1) {
                Text("THE")
                    .font(.system(size: size * 0.18, weight: .bold))
                Text("MOVIE")
                    .font(.system(size: size * 0.22, weight: .black))
                Text("DB")
                    .font(.system(size: size * 0.22, weight: .bold))
            }
            .foregroundStyle(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Overseerr Icon

struct OverseerrIcon: View {
    var size: CGFloat = 24
    var color: Color = .secondary

    var body: some View {
        ZStack {
            Circle()
                .fill(color)

            // Crescent moon cutout
            Circle()
                .fill(Color(NSColor.windowBackgroundColor))
                .frame(width: size * 0.55, height: size * 0.55)
                .offset(x: size * 0.08, y: size * 0.08)

            // Small circle
            Circle()
                .fill(Color(NSColor.windowBackgroundColor))
                .frame(width: size * 0.25, height: size * 0.25)
                .offset(x: -size * 0.15, y: -size * 0.15)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Preview

#if DEBUG
struct IntegrationIcons_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 20) {
            PlexIcon(size: 32, color: .secondary)
            TraktIcon(size: 32, color: .secondary)
            MDBListIcon(size: 32, color: .secondary)
            TMDBIcon(size: 32, color: .secondary)
            OverseerrIcon(size: 32, color: .secondary)
        }
        .padding()
        .background(Color.black)
    }
}
#endif
