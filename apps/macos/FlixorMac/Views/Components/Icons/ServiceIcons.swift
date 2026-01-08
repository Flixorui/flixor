//
//  ServiceIcons.swift
//  FlixorMac
//
//  SwiftUI Shape icons for third-party services with customizable colors.
//

import SwiftUI

// MARK: - Settings Icon View (Wrapper)

/// A composable icon view with background and foreground color control.
/// Usage: SettingsIconView(icon: PlexIconShape(), backgroundColor: .orange, iconColor: .white)
struct SettingsIconView<IconShape: Shape>: View {
    let icon: IconShape
    let backgroundColor: Color
    let iconColor: Color
    var size: CGFloat = 28
    var iconScale: CGFloat = 0.55
    var cornerRadius: CGFloat? = nil
    var useGradient: Bool = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius ?? size * 0.22, style: .continuous)
                .fill(useGradient ? AnyShapeStyle(backgroundColor.gradient) : AnyShapeStyle(backgroundColor))
                .frame(width: size, height: size)

            icon
                .fill(iconColor)
                .frame(width: size * iconScale, height: size * iconScale)
        }
    }
}

// MARK: - Large Header Icon View

/// Larger icon for settings content headers
struct SettingsHeaderIconView<IconShape: Shape>: View {
    let icon: IconShape
    let backgroundColor: Color
    let iconColor: Color
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(backgroundColor.gradient)
                .frame(width: size, height: size)

            icon
                .fill(iconColor)
                .frame(width: size * 0.55, height: size * 0.55)
        }
    }
}

// MARK: - Plex Icon Shape

struct PlexIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        path.move(to: CGPoint(x: 0.5*width, y: 0.13672*height))
        path.addLine(to: CGPoint(x: 0.28906*width, y: 0.13672*height))
        path.addLine(to: CGPoint(x: 0.5*width, y: 0.5*height))
        path.addLine(to: CGPoint(x: 0.28906*width, y: 0.86328*height))
        path.addLine(to: CGPoint(x: 0.5*width, y: 0.86328*height))
        path.addLine(to: CGPoint(x: 0.71094*width, y: 0.5*height))
        path.closeSubpath()
        return path
    }
}

// MARK: - Trakt Icon Shape

struct TraktIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        path.move(to: CGPoint(x: 0.20373*width, y: 0.7721*height))
        path.addCurve(to: CGPoint(x: 0.5*width, y: 0.90193*height), control1: CGPoint(x: 0.27693*width, y: 0.85221*height), control2: CGPoint(x: 0.3826*width, y: 0.90193*height))
        path.addCurve(to: CGPoint(x: 0.66782*width, y: 0.86533*height), control1: CGPoint(x: 0.56008*width, y: 0.90193*height), control2: CGPoint(x: 0.61671*width, y: 0.88881*height))
        path.addLine(to: CGPoint(x: 0.38881*width, y: 0.58702*height))
        path.closeSubpath()
        path.move(to: CGPoint(x: 0.38743*width, y: 0.41851*height))
        path.addLine(to: CGPoint(x: 0.1761*width, y: 0.62914*height))
        path.addLine(to: CGPoint(x: 0.14779*width, y: 0.60083*height))
        path.addLine(to: CGPoint(x: 0.37017*width, y: 0.37845*height))
        path.addLine(to: CGPoint(x: 0.62983*width, y: 0.11878*height))
        path.addCurve(to: CGPoint(x: 0.5*width, y: 0.09738*height), control1: CGPoint(x: 0.58909*width, y: 0.10497*height), control2: CGPoint(x: 0.54558*width, y: 0.09738*height))
        path.addCurve(to: CGPoint(x: 0.09738*width, y: 0.5*height), control1: CGPoint(x: 0.27762*width, y: 0.09738*height), control2: CGPoint(x: 0.09738*width, y: 0.27762*height))
        path.addCurve(to: CGPoint(x: 0.17818*width, y: 0.74171*height), control1: CGPoint(x: 0.09738*width, y: 0.59047*height), control2: CGPoint(x: 0.12707*width, y: 0.67403*height))
        path.addLine(to: CGPoint(x: 0.38881*width, y: 0.53108*height))
        path.addLine(to: CGPoint(x: 0.40331*width, y: 0.54489*height))
        path.addLine(to: CGPoint(x: 0.70511*width, y: 0.84669*height))
        path.addCurve(to: CGPoint(x: 0.72238*width, y: 0.83564*height), control1: CGPoint(x: 0.71133*width, y: 0.84323*height), control2: CGPoint(x: 0.71685*width, y: 0.83978*height))
        path.addLine(to: CGPoint(x: 0.38881*width, y: 0.50207*height))
        path.addLine(to: CGPoint(x: 0.18646*width, y: 0.70442*height))
        path.addLine(to: CGPoint(x: 0.15815*width, y: 0.6761*height))
        path.addLine(to: CGPoint(x: 0.38881*width, y: 0.44544*height))
        path.addLine(to: CGPoint(x: 0.40331*width, y: 0.45925*height))
        path.addLine(to: CGPoint(x: 0.75552*width, y: 0.81077*height))
        path.addCurve(to: CGPoint(x: 0.77072*width, y: 0.79765*height), control1: CGPoint(x: 0.76105*width, y: 0.80663*height), control2: CGPoint(x: 0.76588*width, y: 0.8018*height))
        path.addLine(to: CGPoint(x: 0.39088*width, y: 0.41782*height))
        path.closeSubpath()
        path.move(to: CGPoint(x: 0.79903*width, y: 0.76934*height))
        path.addCurve(to: CGPoint(x: 0.90262*width, y: 0.5*height), control1: CGPoint(x: 0.86326*width, y: 0.6982*height), control2: CGPoint(x: 0.90262*width, y: 0.60359*height))
        path.addCurve(to: CGPoint(x: 0.67058*width, y: 0.13536*height), control1: CGPoint(x: 0.90262*width, y: 0.3384*height), control2: CGPoint(x: 0.80732*width, y: 0.19959*height))
        path.addLine(to: CGPoint(x: 0.41713*width, y: 0.38812*height))
        path.closeSubpath()
        path.move(to: CGPoint(x: 0.5145*width, y: 0.46133*height))
        path.addLine(to: CGPoint(x: 0.48619*width, y: 0.43301*height))
        path.addLine(to: CGPoint(x: 0.68577*width, y: 0.23343*height))
        path.addLine(to: CGPoint(x: 0.71409*width, y: 0.26174*height))
        path.closeSubpath()
        path.move(to: CGPoint(x: 0.70373*width, y: 0.18715*height))
        path.addLine(to: CGPoint(x: 0.47376*width, y: 0.41713*height))
        path.addLine(to: CGPoint(x: 0.44544*width, y: 0.38881*height))
        path.addLine(to: CGPoint(x: 0.67541*width, y: 0.15884*height))
        path.closeSubpath()
        // Outer circle
        path.move(to: CGPoint(x: 0.5*width, y: height))
        path.addCurve(to: CGPoint(x: 0, y: 0.5*height), control1: CGPoint(x: 0.22445*width, y: height), control2: CGPoint(x: 0, y: 0.77555*height))
        path.addCurve(to: CGPoint(x: 0.5*width, y: 0), control1: CGPoint(x: 0, y: 0.22445*height), control2: CGPoint(x: 0.22445*width, y: 0))
        path.addCurve(to: CGPoint(x: width, y: 0.5*height), control1: CGPoint(x: 0.77555*width, y: 0), control2: CGPoint(x: width, y: 0.22445*height))
        path.addCurve(to: CGPoint(x: 0.5*width, y: height), control1: CGPoint(x: width, y: 0.77555*height), control2: CGPoint(x: 0.77555*width, y: height))
        path.closeSubpath()
        // Inner circle stroke
        path.move(to: CGPoint(x: 0.5*width, y: 0.05041*height))
        path.addCurve(to: CGPoint(x: 0.05041*width, y: 0.5*height), control1: CGPoint(x: 0.25207*width, y: 0.05041*height), control2: CGPoint(x: 0.05041*width, y: 0.25207*height))
        path.addCurve(to: CGPoint(x: 0.5*width, y: 0.94959*height), control1: CGPoint(x: 0.05041*width, y: 0.74793*height), control2: CGPoint(x: 0.25207*width, y: 0.94959*height))
        path.addCurve(to: CGPoint(x: 0.94959*width, y: 0.5*height), control1: CGPoint(x: 0.74793*width, y: 0.94959*height), control2: CGPoint(x: 0.94959*width, y: 0.74793*height))
        path.addCurve(to: CGPoint(x: 0.5*width, y: 0.05041*height), control1: CGPoint(x: 0.94959*width, y: 0.25207*height), control2: CGPoint(x: 0.74793*width, y: 0.05041*height))
        path.closeSubpath()
        return path
    }
}

// MARK: - TMDB Icon Shape

struct TMDBIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        path.move(to: CGPoint(x: 0.27594*width, y: 0.5*height))
        path.addLine(to: CGPoint(x: 0.27594*width, y: 0.5*height))
        path.move(to: CGPoint(x: 0.27594*width, y: 0.5*height))
        path.addLine(to: CGPoint(x: 0.27594*width, y: 0.5*height))
        path.addLine(to: CGPoint(x: 0.37089*width, y: 0))
        path.addLine(to: CGPoint(x: 0.46639*width, y: 0))
        path.addLine(to: CGPoint(x: 0.37143*width, y: 0))
        path.closeSubpath()
        path.move(to: CGPoint(x: 0.72271*width, y: 0.26514*height))
        path.addLine(to: CGPoint(x: 0.90051*width, y: 0.26514*height))
        path.addLine(to: CGPoint(x: 0.996*width, y: 0))
        path.addLine(to: CGPoint(x: 0.72271*width, y: 0))
        path.addLine(to: CGPoint(x: 0.62722*width, y: 0))
        path.closeSubpath()
        path.move(to: CGPoint(x: 0.11203*width, y: 0.99978*height))
        path.addLine(to: CGPoint(x: 0.45736*width, y: 0.99978*height))
        path.addLine(to: CGPoint(x: 0.55285*width, y: 0))
        path.addLine(to: CGPoint(x: 0.11203*width, y: 0))
        path.addLine(to: CGPoint(x: 0.01654*width, y: 0))
        path.closeSubpath()
        path.move(to: CGPoint(x: 0.56555*width, y: 0.63246*height))
        path.addLine(to: CGPoint(x: 0.59933*width, y: 0.63246*height))
        path.addLine(to: CGPoint(x: 0.67823*width, y: 0.36732*height))
        path.addLine(to: CGPoint(x: 0.63311*width, y: 0.36732*height))
        path.addLine(to: CGPoint(x: 0.58501*width, y: 0.54123*height))
        path.addLine(to: CGPoint(x: 0.58447*width, y: 0.54123*height))
        path.addLine(to: CGPoint(x: 0.53718*width, y: 0.36732*height))
        path.addLine(to: CGPoint(x: 0.48908*width, y: 0.36732*height))
        path.closeSubpath()
        path.move(to: CGPoint(x: 0.74092*width, y: 0.63246*height))
        path.addLine(to: CGPoint(x: 0.78307*width, y: 0.63246*height))
        path.addLine(to: CGPoint(x: 0.78307*width, y: 0.36732*height))
        path.addLine(to: CGPoint(x: 0.74092*width, y: 0.36732*height))
        path.closeSubpath()
        path.move(to: CGPoint(x: 0.86089*width, y: 0.63246*height))
        path.addLine(to: CGPoint(x: 0.99573*width, y: 0.63246*height))
        path.addLine(to: CGPoint(x: 0.99573*width, y: 0.57871*height))
        path.addLine(to: CGPoint(x: 0.90305*width, y: 0.57871*height))
        path.addLine(to: CGPoint(x: 0.90305*width, y: 0.52474*height))
        path.addLine(to: CGPoint(x: 0.986*width, y: 0.52474*height))
        path.addLine(to: CGPoint(x: 0.986*width, y: 0.47076*height))
        path.addLine(to: CGPoint(x: 0.90305*width, y: 0.47076*height))
        path.addLine(to: CGPoint(x: 0.90305*width, y: 0.42129*height))
        path.addLine(to: CGPoint(x: 0.99087*width, y: 0.42129*height))
        path.addLine(to: CGPoint(x: 0.99087*width, y: 0.36732*height))
        path.addLine(to: CGPoint(x: 0.86117*width, y: 0.36732*height))
        path.closeSubpath()
        path.move(to: CGPoint(x: 0.05458*width, y: 0.26537*height))
        path.addLine(to: CGPoint(x: 0.09674*width, y: 0.26537*height))
        path.addLine(to: CGPoint(x: 0.09674*width, y: 0.05172*height))
        path.addLine(to: CGPoint(x: 0.15132*width, y: 0.05172*height))
        path.addLine(to: CGPoint(x: 0.15132*width, y: 0))
        path.addLine(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: 0.05172*height))
        path.addLine(to: CGPoint(x: 0.05458*width, y: 0.05172*height))
        path.closeSubpath()
        path.move(to: CGPoint(x: 0.21077*width, y: 0.26537*height))
        path.addLine(to: CGPoint(x: 0.25292*width, y: 0.26537*height))
        path.addLine(to: CGPoint(x: 0.25292*width, y: 0.15067*height))
        path.addLine(to: CGPoint(x: 0.33452*width, y: 0.15067*height))
        path.addLine(to: CGPoint(x: 0.33452*width, y: 0.26537*height))
        path.addLine(to: CGPoint(x: 0.37668*width, y: 0.26537*height))
        path.addLine(to: CGPoint(x: 0.37668*width, y: 0))
        path.addLine(to: CGPoint(x: 0.33452*width, y: 0))
        path.addLine(to: CGPoint(x: 0.33452*width, y: 0.09895*height))
        path.addLine(to: CGPoint(x: 0.25265*width, y: 0.09895*height))
        path.addLine(to: CGPoint(x: 0.25265*width, y: 0))
        path.addLine(to: CGPoint(x: 0.21077*width, y: 0))
        path.closeSubpath()
        path.move(to: CGPoint(x: 0.43369*width, y: 0.26537*height))
        path.addLine(to: CGPoint(x: 0.5688*width, y: 0.26537*height))
        path.addLine(to: CGPoint(x: 0.5688*width, y: 0.21139*height))
        path.addLine(to: CGPoint(x: 0.47557*width, y: 0.21139*height))
        path.addLine(to: CGPoint(x: 0.47557*width, y: 0.15742*height))
        path.addLine(to: CGPoint(x: 0.55853*width, y: 0.15742*height))
        path.addLine(to: CGPoint(x: 0.55853*width, y: 0.10345*height))
        path.addLine(to: CGPoint(x: 0.47557*width, y: 0.10345*height))
        path.addLine(to: CGPoint(x: 0.47557*width, y: 0.05397*height))
        path.addLine(to: CGPoint(x: 0.56339*width, y: 0.05397*height))
        path.addLine(to: CGPoint(x: 0.56339*width, y: 0))
        path.addLine(to: CGPoint(x: 0.43369*width, y: 0))
        path.closeSubpath()
        path.move(to: CGPoint(x: 0.00676*width, y: 0.63268*height))
        path.addLine(to: CGPoint(x: 0.04864*width, y: 0.63268*height))
        path.addLine(to: CGPoint(x: 0.04864*width, y: 0.42916*height))
        path.addLine(to: CGPoint(x: 0.04918*width, y: 0.42916*height))
        path.addLine(to: CGPoint(x: 0.09782*width, y: 0.63268*height))
        path.addLine(to: CGPoint(x: 0.1297*width, y: 0.63268*height))
        path.addLine(to: CGPoint(x: 0.17996*width, y: 0.42916*height))
        path.addLine(to: CGPoint(x: 0.1805*width, y: 0.42916*height))
        path.addLine(to: CGPoint(x: 0.1805*width, y: 0.63268*height))
        path.addLine(to: CGPoint(x: 0.22265*width, y: 0.63268*height))
        path.addLine(to: CGPoint(x: 0.22265*width, y: 0.36732*height))
        path.addLine(to: CGPoint(x: 0.15915*width, y: 0.36732*height))
        path.addLine(to: CGPoint(x: 0.11484*width, y: 0.54048*height))
        path.addLine(to: CGPoint(x: 0.1143*width, y: 0.54048*height))
        path.addLine(to: CGPoint(x: 0.07026*width, y: 0.36732*height))
        path.addLine(to: CGPoint(x: 0.00649*width, y: 0.36732*height))
        path.closeSubpath()
        path.move(to: CGPoint(x: 0.61252*width, y: height))
        path.addLine(to: CGPoint(x: 0.68093*width, y: height))
        path.addLine(to: CGPoint(x: 0.61225*width, y: 0))
        path.closeSubpath()
        path.move(to: CGPoint(x: 0.65472*width, y: 0.78861*height))
        path.addLine(to: CGPoint(x: 0.67958*width, y: 0.78861*height))
        path.addLine(to: CGPoint(x: 0.65445*width, y: 0))
        path.closeSubpath()
        path.move(to: CGPoint(x: 0.85003*width, y: height))
        path.addLine(to: CGPoint(x: 0.92839*width, y: height))
        path.addLine(to: CGPoint(x: 0, y: 0.86057*height))
        path.addLine(to: CGPoint(x: 0.85003*width, y: 0))
        path.closeSubpath()
        path.move(to: CGPoint(x: 0.89219*width, y: 0.78411*height))
        path.addLine(to: CGPoint(x: 0.92083*width, y: 0.78411*height))
        path.addLine(to: CGPoint(x: 0.8917*width, y: 0))
        path.closeSubpath()
        path.move(to: CGPoint(x: 0.89219*width, y: 0.89018*height))
        path.addLine(to: CGPoint(x: 0.92407*width, y: 0.89018*height))
        path.addLine(to: CGPoint(x: 0.89192*width, y: 0))
        path.closeSubpath()
        return path
    }
}

// MARK: - Overseerr Icon Shape

struct OverseerrIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        path.move(to: CGPoint(x: 0, y: 0))
        path.addCurve(to: CGPoint(x: 0.00307*width, y: 0.00278*height), control1: CGPoint(x: 0.00152*width, y: 0.00138*height), control2: CGPoint(x: 0.00152*width, y: 0.00138*height))
        path.addCurve(to: CGPoint(x: 0.08838*width, y: 0.12878*height), control1: CGPoint(x: 0.04007*width, y: 0.03703*height), control2: CGPoint(x: 0.06898*width, y: 0.08252*height))
        path.addCurve(to: CGPoint(x: 0.09139*width, y: 0.13589*height), control1: CGPoint(x: 0.08937*width, y: 0.13113*height), control2: CGPoint(x: 0.09037*width, y: 0.13347*height))
        path.addCurve(to: CGPoint(x: 0.11572*width, y: 0.2323*height), control1: CGPoint(x: 0.10379*width, y: 0.16632*height), control2: CGPoint(x: 0.11215*width, y: 0.19963*height))
        path.addCurve(to: CGPoint(x: 0.11637*width, y: 0.23737*height), control1: CGPoint(x: 0.11594*width, y: 0.23397*height), control2: CGPoint(x: 0.11615*width, y: 0.23565*height))
        path.addCurve(to: CGPoint(x: 0.03101*width, y: 0.52441*height), control1: CGPoint(x: 0.12755*width, y: 0.34098*height), control2: CGPoint(x: 0.09574*width, y: 0.44356*height))
        path.addCurve(to: CGPoint(x: 0.01013*width, y: 0.54822*height), control1: CGPoint(x: 0.02424*width, y: 0.53252*height), control2: CGPoint(x: 0.01725*width, y: 0.54042*height))
        path.addCurve(to: CGPoint(x: 0.00735*width, y: 0.55129*height), control1: CGPoint(x: 0.00875*width, y: 0.54974*height), control2: CGPoint(x: 0.00875*width, y: 0.54974*height))
        path.addCurve(to: CGPoint(x: -0.11865*width, y: 0.6366*height), control1: CGPoint(x: -0.0269*width, y: 0.58829*height), control2: CGPoint(x: -0.07239*width, y: 0.6172*height))
        path.addCurve(to: CGPoint(x: -0.12576*width, y: 0.63961*height), control1: CGPoint(x: -0.121*width, y: 0.63759*height), control2: CGPoint(x: -0.12334*width, y: 0.63859*height))
        path.addCurve(to: CGPoint(x: -0.22217*width, y: 0.66394*height), control1: CGPoint(x: -0.15619*width, y: 0.652*height), control2: CGPoint(x: -0.1895*width, y: 0.66037*height))
        path.addCurve(to: CGPoint(x: -0.22724*width, y: 0.66459*height), control1: CGPoint(x: -0.22384*width, y: 0.66415*height), control2: CGPoint(x: -0.22552*width, y: 0.66437*height))
        path.addCurve(to: CGPoint(x: -0.51428*width, y: 0.57922*height), control1: CGPoint(x: -0.33085*width, y: 0.67577*height), control2: CGPoint(x: -0.43343*width, y: 0.64396*height))
        path.addCurve(to: CGPoint(x: -0.53809*width, y: 0.55835*height), control1: CGPoint(x: -0.52239*width, y: 0.57246*height), control2: CGPoint(x: -0.53028*width, y: 0.56547*height))
        path.addCurve(to: CGPoint(x: -0.54116*width, y: 0.55557*height), control1: CGPoint(x: -0.53961*width, y: 0.55697*height), control2: CGPoint(x: -0.53961*width, y: 0.55697*height))
        path.addCurve(to: CGPoint(x: -0.62646*width, y: 0.42957*height), control1: CGPoint(x: -0.57816*width, y: 0.52132*height), control2: CGPoint(x: -0.60707*width, y: 0.47583*height))
        path.addCurve(to: CGPoint(x: -0.62948*width, y: 0.42246*height), control1: CGPoint(x: -0.62746*width, y: 0.42722*height), control2: CGPoint(x: -0.62845*width, y: 0.42488*height))
        path.addCurve(to: CGPoint(x: -0.65381*width, y: 0.32605*height), control1: CGPoint(x: -0.64187*width, y: 0.39203*height), control2: CGPoint(x: -0.65024*width, y: 0.35871*height))
        path.addCurve(to: CGPoint(x: -0.65446*width, y: 0.32098*height), control1: CGPoint(x: -0.65402*width, y: 0.32438*height), control2: CGPoint(x: -0.65424*width, y: 0.3227*height))
        path.addCurve(to: CGPoint(x: -0.56909*width, y: 0.03394*height), control1: CGPoint(x: -0.66564*width, y: 0.21737*height), control2: CGPoint(x: -0.63382*width, y: 0.11479*height))
        path.addCurve(to: CGPoint(x: -0.54822*width, y: 0.01013*height), control1: CGPoint(x: -0.56232*width, y: 0.02583*height), control2: CGPoint(x: -0.55534*width, y: 0.01793*height))
        path.addCurve(to: CGPoint(x: -0.54543*width, y: 0.00706*height), control1: CGPoint(x: -0.5473*width, y: 0.00912*height), control2: CGPoint(x: -0.54638*width, y: 0.0081*height))
        path.addCurve(to: CGPoint(x: -0.41943*width, y: -0.07825*height), control1: CGPoint(x: -0.51119*width, y: -0.02994*height), control2: CGPoint(x: -0.4657*width, y: -0.05885*height))
        path.addCurve(to: CGPoint(x: -0.41233*width, y: -0.08126*height), control1: CGPoint(x: -0.41709*width, y: -0.07924*height), control2: CGPoint(x: -0.41475*width, y: -0.08024*height))
        path.addCurve(to: CGPoint(x: -0.31592*width, y: -0.10559*height), control1: CGPoint(x: -0.3819*width, y: -0.09366*height), control2: CGPoint(x: -0.34858*width, y: -0.10202*height))
        path.addCurve(to: CGPoint(x: -0.31084*width, y: -0.10624*height), control1: CGPoint(x: -0.31424*width, y: -0.1058*height), control2: CGPoint(x: -0.31257*width, y: -0.10602*height))
        path.addCurve(to: CGPoint(x: 0, y: 0), control1: CGPoint(x: -0.19497*width, y: -0.11874*height), control2: CGPoint(x: -0.08505*width, y: -0.07759*height))
        path.closeSubpath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addCurve(to: CGPoint(x: 0.01512*width, y: 0.01339*height), control1: CGPoint(x: 0.00515*width, y: 0.00435*height), control2: CGPoint(x: 0.01014*width, y: 0.00885*height))
        path.addCurve(to: CGPoint(x: 0.01941*width, y: 0.0172*height), control1: CGPoint(x: 0.01654*width, y: 0.01465*height), control2: CGPoint(x: 0.01795*width, y: 0.0159*height))
        path.addCurve(to: CGPoint(x: 0.08372*width, y: 0.15363*height), control1: CGPoint(x: 0.05541*width, y: 0.05085*height), control2: CGPoint(x: 0.08155*width, y: 0.10422*height))
        path.addCurve(to: CGPoint(x: 0.02684*width, y: 0.32784*height), control1: CGPoint(x: 0.08537*width, y: 0.21945*height), control2: CGPoint(x: 0.07146*width, y: 0.27762*height))
        path.addCurve(to: CGPoint(x: 0.0221*width, y: 0.33318*height), control1: CGPoint(x: 0.02449*width, y: 0.33048*height), control2: CGPoint(x: 0.02449*width, y: 0.33048*height))
        path.addCurve(to: CGPoint(x: -0.12854*width, y: 0.40067*height), control1: CGPoint(x: -0.01666*width, y: 0.3741*height), control2: CGPoint(x: -0.07245*width, y: 0.39874*height))
        path.addCurve(to: CGPoint(x: -0.19777*width, y: 0.39425*height), control1: CGPoint(x: -0.15223*width, y: 0.40113*height), control2: CGPoint(x: -0.17489*width, y: 0.40089*height))
        path.addCurve(to: CGPoint(x: -0.20473*width, y: 0.39237*height), control1: CGPoint(x: -0.20122*width, y: 0.39332*height), control2: CGPoint(x: -0.20122*width, y: 0.39332*height))
        path.addCurve(to: CGPoint(x: -0.29152*width, y: 0.34347*height), control1: CGPoint(x: -0.23712*width, y: 0.3827*height), control2: CGPoint(x: -0.26631*width, y: 0.36586*height))
        path.addCurve(to: CGPoint(x: -0.29679*width, y: 0.3388*height), control1: CGPoint(x: -0.29326*width, y: 0.34193*height), control2: CGPoint(x: -0.295*width, y: 0.34039*height))
        path.addCurve(to: CGPoint(x: -0.35793*width, y: 0.23409*height), control1: CGPoint(x: -0.32697*width, y: 0.31022*height), control2: CGPoint(x: -0.3469*width, y: 0.27393*height))
        path.addCurve(to: CGPoint(x: -0.35982*width, y: 0.2273*height), control1: CGPoint(x: -0.35855*width, y: 0.23185*height), control2: CGPoint(x: -0.35918*width, y: 0.22961*height))
        path.addCurve(to: CGPoint(x: -0.35793*width, y: 0.11691*height), control1: CGPoint(x: -0.36771*width, y: 0.19319*height), control2: CGPoint(x: -0.36911*width, y: 0.15044*height))
        path.addCurve(to: CGPoint(x: -0.35402*width, y: 0.11105*height), control1: CGPoint(x: -0.35664*width, y: 0.11497*height), control2: CGPoint(x: -0.35535*width, y: 0.11304*height))
        path.addCurve(to: CGPoint(x: -0.35208*width, y: 0.11463*height), control1: CGPoint(x: -0.35338*width, y: 0.11223*height), control2: CGPoint(x: -0.35274*width, y: 0.11341*height))
        path.addCurve(to: CGPoint(x: -0.28298*width, y: 0.17233*height), control1: CGPoint(x: -0.33637*width, y: 0.14231*height), control2: CGPoint(x: -0.31405*width, y: 0.16307*height))
        path.addCurve(to: CGPoint(x: -0.18605*width, y: 0.15401*height), control1: CGPoint(x: -0.24831*width, y: 0.1783*height), control2: CGPoint(x: -0.21573*width, y: 0.17329*height))
        path.addCurve(to: CGPoint(x: -0.14308*width, y: 0.0837*height), control1: CGPoint(x: -0.16329*width, y: 0.13768*height), control2: CGPoint(x: -0.14795*width, y: 0.11118*height))
        path.addCurve(to: CGPoint(x: -0.16968*width, y: -0.01198*height), control1: CGPoint(x: -0.13957*width, y: 0.04695*height), control2: CGPoint(x: -0.14598*width, y: 0.01717*height))
        path.addCurve(to: CGPoint(x: -0.19708*width, y: -0.03255*height), control1: CGPoint(x: -0.17766*width, y: -0.02059*height), control2: CGPoint(x: -0.18706*width, y: -0.02651*height))
        path.addCurve(to: CGPoint(x: -0.20558*width, y: -0.03934*height), control1: CGPoint(x: -0.20168*width, y: -0.03544*height), control2: CGPoint(x: -0.20168*width, y: -0.03544*height))
        path.addCurve(to: CGPoint(x: -0.1957*width, y: -0.04215*height), control1: CGPoint(x: -0.20229*width, y: -0.04029*height), control2: CGPoint(x: -0.19899*width, y: -0.04122*height))
        path.addCurve(to: CGPoint(x: -0.19013*width, y: -0.04373*height), control1: CGPoint(x: -0.19294*width, y: -0.04293*height), control2: CGPoint(x: -0.19294*width, y: -0.04293*height))
        path.addCurve(to: CGPoint(x: 0, y: 0), control1: CGPoint(x: -0.12547*width, y: -0.05951*height), control2: CGPoint(x: -0.05126*width, y: -0.04191*height))
        path.closeSubpath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addCurve(to: CGPoint(x: 0.15033*width, y: 0.05908*height), control1: CGPoint(x: 0.05374*width, y: -0.00302*height), control2: CGPoint(x: 0.11072*width, y: 0.02415*height))
        path.addCurve(to: CGPoint(x: 0.2309*width, y: 0.21749*height), control1: CGPoint(x: 0.19543*width, y: 0.10005*height), control2: CGPoint(x: 0.22684*width, y: 0.15592*height))
        path.addCurve(to: CGPoint(x: 0.16294*width, y: 0.40931*height), control1: CGPoint(x: 0.23337*width, y: 0.29183*height), control2: CGPoint(x: 0.21396*width, y: 0.35401*height))
        path.addCurve(to: CGPoint(x: -0.00337*width, y: 0.48139*height), control1: CGPoint(x: 0.11954*width, y: 0.45462*height), control2: CGPoint(x: 0.05895*width, y: 0.47985*height))
        path.addCurve(to: CGPoint(x: -0.18267*width, y: 0.40918*height), control1: CGPoint(x: -0.0732*width, y: 0.48193*height), control2: CGPoint(x: -0.13265*width, y: 0.45827*height))
        path.addCurve(to: CGPoint(x: -0.25019*width, y: 0.26545*height), control1: CGPoint(x: -0.21882*width, y: 0.37236*height), control2: CGPoint(x: -0.24853*width, y: 0.31809*height))
        path.addCurve(to: CGPoint(x: -0.25012*width, y: 0.25989*height), control1: CGPoint(x: -0.25017*width, y: 0.26361*height), control2: CGPoint(x: -0.25015*width, y: 0.26178*height))
        path.addCurve(to: CGPoint(x: -0.25007*width, y: 0.25422*height), control1: CGPoint(x: -0.2501*width, y: 0.25802*height), control2: CGPoint(x: -0.25009*width, y: 0.25615*height))
        path.addCurve(to: CGPoint(x: -0.25*width, y: 0.25*height), control1: CGPoint(x: -0.25003*width, y: 0.25213*height), control2: CGPoint(x: -0.25003*width, y: 0.25213*height))
        path.addCurve(to: CGPoint(x: -0.24805*width, y: 0.25*height), control1: CGPoint(x: -0.24936*width, y: 0.25*height), control2: CGPoint(x: -0.24871*width, y: 0.25*height))
        path.addCurve(to: CGPoint(x: -0.24682*width, y: 0.25731*height), control1: CGPoint(x: -0.24764*width, y: 0.25241*height), control2: CGPoint(x: -0.24724*width, y: 0.25482*height))
        path.addCurve(to: CGPoint(x: -0.1875*width, y: 0.37891*height), control1: CGPoint(x: -0.23835*width, y: 0.30494*height), control2: CGPoint(x: -0.22003*width, y: 0.34318*height))
        path.addCurve(to: CGPoint(x: -0.18413*width, y: 0.38277*height), control1: CGPoint(x: -0.18639*width, y: 0.38018*height), control2: CGPoint(x: -0.18527*width, y: 0.38145*height))
        path.addCurve(to: CGPoint(x: -0.04921*width, y: 0.44555*height), control1: CGPoint(x: -0.15143*width, y: 0.41814*height), control2: CGPoint(x: -0.09732*width, y: 0.44344*height))
        path.addCurve(to: CGPoint(x: 0.125*width, y: 0.38867*height), control1: CGPoint(x: 0.01671*width, y: 0.4472*height), control2: CGPoint(x: 0.07464*width, y: 0.43323*height))
        path.addCurve(to: CGPoint(x: 0.1299*width, y: 0.38437*height), control1: CGPoint(x: 0.12662*width, y: 0.38725*height), control2: CGPoint(x: 0.12823*width, y: 0.38583*height))
        path.addCurve(to: CGPoint(x: 0.19587*width, y: 0.23524*height), control1: CGPoint(x: 0.17022*width, y: 0.34644*height), control2: CGPoint(x: 0.19399*width, y: 0.29007*height))
        path.addCurve(to: CGPoint(x: 0.18945*width, y: 0.16602*height), control1: CGPoint(x: 0.19633*width, y: 0.21156*height), control2: CGPoint(x: 0.19609*width, y: 0.1889*height))
        path.addCurve(to: CGPoint(x: 0.18758*width, y: 0.15906*height), control1: CGPoint(x: 0.18883*width, y: 0.16372*height), control2: CGPoint(x: 0.18821*width, y: 0.16142*height))
        path.addCurve(to: CGPoint(x: 0.13867*width, y: 0.07227*height), control1: CGPoint(x: 0.17787*width, y: 0.12657*height), control2: CGPoint(x: 0.16096*width, y: 0.09766*height))
        path.addCurve(to: CGPoint(x: 0.13444*width, y: 0.06744*height), control1: CGPoint(x: 0.13727*width, y: 0.07067*height), control2: CGPoint(x: 0.13588*width, y: 0.06908*height))
        path.addCurve(to: CGPoint(x: 0, y: 0.00195*height), control1: CGPoint(x: 0.09858*width, y: 0.02929*height), control2: CGPoint(x: 0.05076*width, y: 0.01016*height))
        path.addCurve(to: CGPoint(x: 0, y: 0), control1: CGPoint(x: 0, y: 0.00131*height), control2: CGPoint(x: 0, y: 0.00066*height))
        path.closeSubpath()
        return path
    }
}

// MARK: - MDBList Icon Shape

struct MDBListIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        path.move(to: CGPoint(x: 0, y: 0))
        path.addCurve(to: CGPoint(x: 0.00977*width, y: -0.00003*height), control1: CGPoint(x: 0.00326*width, y: -0.00001*height), control2: CGPoint(x: 0.00652*width, y: -0.00002*height))
        path.addCurve(to: CGPoint(x: 0.03621*width, y: 0.00004*height), control1: CGPoint(x: 0.01859*width, y: -0.00006*height), control2: CGPoint(x: 0.0274*width, y: -0.00002*height))
        path.addCurve(to: CGPoint(x: 0.06391*width, y: 0.00008*height), control1: CGPoint(x: 0.04544*width, y: 0.00009*height), control2: CGPoint(x: 0.05468*width, y: 0.00008*height))
        path.addCurve(to: CGPoint(x: 0.1104*width, y: 0.00022*height), control1: CGPoint(x: 0.07941*width, y: 0.00009*height), control2: CGPoint(x: 0.09491*width, y: 0.00014*height))
        path.addCurve(to: CGPoint(x: 0.16414*width, y: 0.00034*height), control1: CGPoint(x: 0.12832*width, y: 0.00031*height), control2: CGPoint(x: 0.14623*width, y: 0.00034*height))
        path.addCurve(to: CGPoint(x: 0.2214*width, y: 0.00043*height), control1: CGPoint(x: 0.18323*width, y: 0.00033*height), control2: CGPoint(x: 0.20231*width, y: 0.00037*height))
        path.addCurve(to: CGPoint(x: 0.23789*width, y: 0.00045*height), control1: CGPoint(x: 0.2269*width, y: 0.00044*height), control2: CGPoint(x: 0.23239*width, y: 0.00044*height))
        path.addCurve(to: CGPoint(x: 0.26379*width, y: 0.00055*height), control1: CGPoint(x: 0.24652*width, y: 0.00045*height), control2: CGPoint(x: 0.25515*width, y: 0.00049*height))
        path.addCurve(to: CGPoint(x: 0.27329*width, y: 0.00057*height), control1: CGPoint(x: 0.26695*width, y: 0.00056*height), control2: CGPoint(x: 0.27012*width, y: 0.00057*height))
        path.addCurve(to: CGPoint(x: 0.28626*width, y: 0.00064*height), control1: CGPoint(x: 0.27761*width, y: 0.00056*height), control2: CGPoint(x: 0.28193*width, y: 0.0006*height))
        path.addCurve(to: CGPoint(x: 0.29359*width, y: 0.00067*height), control1: CGPoint(x: 0.28868*width, y: 0.00065*height), control2: CGPoint(x: 0.2911*width, y: 0.00066*height))
        path.addCurve(to: CGPoint(x: 0.31608*width, y: 0.01346*height), control1: CGPoint(x: 0.30321*width, y: 0.00181*height), control2: CGPoint(x: 0.30975*width, y: 0.00626*height))
        path.addCurve(to: CGPoint(x: 0.32284*width, y: 0.05501*height), control1: CGPoint(x: 0.32475*width, y: 0.02572*height), control2: CGPoint(x: 0.323*width, y: 0.04064*height))
        path.addCurve(to: CGPoint(x: 0.32287*width, y: 0.06478*height), control1: CGPoint(x: 0.32285*width, y: 0.05826*height), control2: CGPoint(x: 0.32286*width, y: 0.06152*height))
        path.addCurve(to: CGPoint(x: 0.3228*width, y: 0.09122*height), control1: CGPoint(x: 0.3229*width, y: 0.07359*height), control2: CGPoint(x: 0.32286*width, y: 0.0824*height))
        path.addCurve(to: CGPoint(x: 0.32276*width, y: 0.11892*height), control1: CGPoint(x: 0.32275*width, y: 0.10045*height), control2: CGPoint(x: 0.32276*width, y: 0.10968*height))
        path.addCurve(to: CGPoint(x: 0.32262*width, y: 0.16541*height), control1: CGPoint(x: 0.32275*width, y: 0.13442*height), control2: CGPoint(x: 0.3227*width, y: 0.14991*height))
        path.addCurve(to: CGPoint(x: 0.3225*width, y: 0.21915*height), control1: CGPoint(x: 0.32253*width, y: 0.18332*height), control2: CGPoint(x: 0.3225*width, y: 0.20124*height))
        path.addCurve(to: CGPoint(x: 0.32241*width, y: 0.27641*height), control1: CGPoint(x: 0.32251*width, y: 0.23823*height), control2: CGPoint(x: 0.32247*width, y: 0.25732*height))
        path.addCurve(to: CGPoint(x: 0.3224*width, y: 0.29289*height), control1: CGPoint(x: 0.3224*width, y: 0.2819*height), control2: CGPoint(x: 0.3224*width, y: 0.2874*height))
        path.addCurve(to: CGPoint(x: 0.32229*width, y: 0.31879*height), control1: CGPoint(x: 0.32239*width, y: 0.30153*height), control2: CGPoint(x: 0.32235*width, y: 0.31016*height))
        path.addCurve(to: CGPoint(x: 0.32227*width, y: 0.32829*height), control1: CGPoint(x: 0.32228*width, y: 0.32196*height), control2: CGPoint(x: 0.32227*width, y: 0.32513*height))
        path.addCurve(to: CGPoint(x: 0.3222*width, y: 0.34126*height), control1: CGPoint(x: 0.32228*width, y: 0.33262*height), control2: CGPoint(x: 0.32224*width, y: 0.33694*height))
        path.addCurve(to: CGPoint(x: 0.32217*width, y: 0.3486*height), control1: CGPoint(x: 0.32219*width, y: 0.34368*height), control2: CGPoint(x: 0.32218*width, y: 0.3461*height))
        path.addCurve(to: CGPoint(x: 0.30939*width, y: 0.37109*height), control1: CGPoint(x: 0.32103*width, y: 0.35821*height), control2: CGPoint(x: 0.31658*width, y: 0.36475*height))
        path.addCurve(to: CGPoint(x: 0.26783*width, y: 0.37785*height), control1: CGPoint(x: 0.29712*width, y: 0.37976*height), control2: CGPoint(x: 0.2822*width, y: 0.37801*height))
        path.addCurve(to: CGPoint(x: 0.25806*width, y: 0.37788*height), control1: CGPoint(x: 0.26458*width, y: 0.37785*height), control2: CGPoint(x: 0.26132*width, y: 0.37786*height))
        path.addCurve(to: CGPoint(x: 0.23162*width, y: 0.3778*height), control1: CGPoint(x: 0.24925*width, y: 0.37791*height), control2: CGPoint(x: 0.24044*width, y: 0.37786*height))
        path.addCurve(to: CGPoint(x: 0.20392*width, y: 0.37777*height), control1: CGPoint(x: 0.22239*width, y: 0.37775*height), control2: CGPoint(x: 0.21316*width, y: 0.37776*height))
        path.addCurve(to: CGPoint(x: 0.15743*width, y: 0.37763*height), control1: CGPoint(x: 0.18843*width, y: 0.37776*height), control2: CGPoint(x: 0.17293*width, y: 0.37771*height))
        path.addCurve(to: CGPoint(x: 0.10369*width, y: 0.37751*height), control1: CGPoint(x: 0.13952*width, y: 0.37754*height), control2: CGPoint(x: 0.12161*width, y: 0.37751*height))
        path.addCurve(to: CGPoint(x: 0.04643*width, y: 0.37742*height), control1: CGPoint(x: 0.08461*width, y: 0.37751*height), control2: CGPoint(x: 0.06552*width, y: 0.37747*height))
        path.addCurve(to: CGPoint(x: 0.02995*width, y: 0.3774*height), control1: CGPoint(x: 0.04094*width, y: 0.37741*height), control2: CGPoint(x: 0.03544*width, y: 0.3774*height))
        path.addCurve(to: CGPoint(x: 0.00405*width, y: 0.3773*height), control1: CGPoint(x: 0.02131*width, y: 0.3774*height), control2: CGPoint(x: 0.01268*width, y: 0.37736*height))
        path.addCurve(to: CGPoint(x: -0.00545*width, y: 0.37728*height), control1: CGPoint(x: 0.00088*width, y: 0.37728*height), control2: CGPoint(x: -0.00229*width, y: 0.37728*height))
        path.addCurve(to: CGPoint(x: -0.01842*width, y: 0.37721*height), control1: CGPoint(x: -0.00978*width, y: 0.37728*height), control2: CGPoint(x: -0.0141*width, y: 0.37725*height))
        path.addCurve(to: CGPoint(x: -0.02575*width, y: 0.37718*height), control1: CGPoint(x: -0.02084*width, y: 0.3772*height), control2: CGPoint(x: -0.02326*width, y: 0.37719*height))
        path.addCurve(to: CGPoint(x: -0.04824*width, y: 0.36439*height), control1: CGPoint(x: -0.03537*width, y: 0.37603*height), control2: CGPoint(x: -0.04191*width, y: 0.37159*height))
        path.addCurve(to: CGPoint(x: -0.05501*width, y: 0.32284*height), control1: CGPoint(x: -0.05692*width, y: 0.35213*height), control2: CGPoint(x: -0.05517*width, y: 0.33721*height))
        path.addCurve(to: CGPoint(x: -0.05504*width, y: 0.31307*height), control1: CGPoint(x: -0.05501*width, y: 0.31958*height), control2: CGPoint(x: -0.05502*width, y: 0.31633*height))
        path.addCurve(to: CGPoint(x: -0.05496*width, y: 0.28663*height), control1: CGPoint(x: -0.05507*width, y: 0.30425*height), control2: CGPoint(x: -0.05502*width, y: 0.29544*height))
        path.addCurve(to: CGPoint(x: -0.05492*width, y: 0.25893*height), control1: CGPoint(x: -0.05491*width, y: 0.2774*height), control2: CGPoint(x: -0.05492*width, y: 0.26816*height))
        path.addCurve(to: CGPoint(x: -0.05479*width, y: 0.21244*height), control1: CGPoint(x: -0.05492*width, y: 0.24343*height), control2: CGPoint(x: -0.05487*width, y: 0.22793*height))
        path.addCurve(to: CGPoint(x: -0.05467*width, y: 0.1587*height), control1: CGPoint(x: -0.0547*width, y: 0.19452*height), control2: CGPoint(x: -0.05467*width, y: 0.17661*height))
        path.addCurve(to: CGPoint(x: -0.05458*width, y: 0.10144*height), control1: CGPoint(x: -0.05467*width, y: 0.13961*height), control2: CGPoint(x: -0.05463*width, y: 0.12053*height))
        path.addCurve(to: CGPoint(x: -0.05456*width, y: 0.08495*height), control1: CGPoint(x: -0.05457*width, y: 0.09594*height), control2: CGPoint(x: -0.05456*width, y: 0.09045*height))
        path.addCurve(to: CGPoint(x: -0.05446*width, y: 0.05906*height), control1: CGPoint(x: -0.05455*width, y: 0.07632*height), control2: CGPoint(x: -0.05452*width, y: 0.06769*height))
        path.addCurve(to: CGPoint(x: -0.05444*width, y: 0.04955*height), control1: CGPoint(x: -0.05444*width, y: 0.05589*height), control2: CGPoint(x: -0.05444*width, y: 0.05272*height))
        path.addCurve(to: CGPoint(x: -0.05437*width, y: 0.03658*height), control1: CGPoint(x: -0.05444*width, y: 0.04523*height), control2: CGPoint(x: -0.05441*width, y: 0.04091*height))
        path.addCurve(to: CGPoint(x: -0.05434*width, y: 0.02925*height), control1: CGPoint(x: -0.05435*width, y: 0.03295*height), control2: CGPoint(x: -0.05435*width, y: 0.03295*height))
        path.addCurve(to: CGPoint(x: -0.04155*width, y: 0.00676*height), control1: CGPoint(x: -0.05319*width, y: 0.01963*height), control2: CGPoint(x: -0.04874*width, y: 0.01309*height))
        path.addCurve(to: CGPoint(x: 0, y: 0), control1: CGPoint(x: -0.02928*width, y: -0.00191*height), control2: CGPoint(x: -0.01437*width, y: -0.00016*height))
        path.closeSubpath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addCurve(to: CGPoint(x: 0.03906*width, y: 0), control1: CGPoint(x: 0.01289*width, y: 0), control2: CGPoint(x: 0.02578*width, y: 0))
        path.addCurve(to: CGPoint(x: 0.03906*width, y: 0.18555*height), control1: CGPoint(x: 0.03906*width, y: 0.06123*height), control2: CGPoint(x: 0.03906*width, y: 0.12246*height))
        path.addCurve(to: CGPoint(x: -0.00195*width, y: 0.18555*height), control1: CGPoint(x: 0.02553*width, y: 0.18555*height), control2: CGPoint(x: 0.01199*width, y: 0.18555*height))
        path.addCurve(to: CGPoint(x: -0.00391*width, y: 0.05469*height), control1: CGPoint(x: -0.00292*width, y: 0.12077*height), control2: CGPoint(x: -0.00292*width, y: 0.12077*height))
        path.addCurve(to: CGPoint(x: -0.01758*width, y: 0.06836*height), control1: CGPoint(x: -0.00842*width, y: 0.0592*height), control2: CGPoint(x: -0.01293*width, y: 0.06371*height))
        path.addCurve(to: CGPoint(x: -0.02515*width, y: 0.07495*height), control1: CGPoint(x: -0.02007*width, y: 0.07059*height), control2: CGPoint(x: -0.02258*width, y: 0.0728*height))
        path.addCurve(to: CGPoint(x: -0.04615*width, y: 0.09529*height), control1: CGPoint(x: -0.03258*width, y: 0.08134*height), control2: CGPoint(x: -0.03938*width, y: 0.08821*height))
        path.addCurve(to: CGPoint(x: -0.06445*width, y: 0.10938*height), control1: CGPoint(x: -0.05178*width, y: 0.10054*height), control2: CGPoint(x: -0.05819*width, y: 0.1049*height))
        path.addCurve(to: CGPoint(x: -0.06445*width, y: 0.06055*height), control1: CGPoint(x: -0.06445*width, y: 0.09326*height), control2: CGPoint(x: -0.06445*width, y: 0.07715*height))
        path.addCurve(to: CGPoint(x: -0.05859*width, y: 0.05859*height), control1: CGPoint(x: -0.06252*width, y: 0.0599*height), control2: CGPoint(x: -0.06059*width, y: 0.05926*height))
        path.addCurve(to: CGPoint(x: -0.05859*width, y: 0.05469*height), control1: CGPoint(x: -0.05859*width, y: 0.0573*height), control2: CGPoint(x: -0.05859*width, y: 0.05602*height))
        path.addCurve(to: CGPoint(x: -0.05176*width, y: 0.04858*height), control1: CGPoint(x: -0.05573*width, y: 0.05186*height), control2: CGPoint(x: -0.05573*width, y: 0.05186*height))
        path.addCurve(to: CGPoint(x: -0.03516*width, y: 0.0332*height), control1: CGPoint(x: -0.04596*width, y: 0.04367*height), control2: CGPoint(x: -0.04048*width, y: 0.03863*height))
        path.addCurve(to: CGPoint(x: -0.01573*width, y: 0.0153*height), control1: CGPoint(x: -0.02894*width, y: 0.02689*height), control2: CGPoint(x: -0.02249*width, y: 0.02102*height))
        path.addCurve(to: CGPoint(x: 0, y: 0), control1: CGPoint(x: -0.01028*width, y: 0.01043*height), control2: CGPoint(x: -0.00517*width, y: 0.00517*height))
        path.closeSubpath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addCurve(to: CGPoint(x: 0.04932*width, y: 0.00793*height), control1: CGPoint(x: 0.03906*width, y: 0), control2: CGPoint(x: 0.03906*width, y: 0))
        path.addCurve(to: CGPoint(x: 0.05664*width, y: 0.01758*height), control1: CGPoint(x: 0.0518*width, y: 0.01112*height), control2: CGPoint(x: 0.05424*width, y: 0.01433*height))
        path.addCurve(to: CGPoint(x: 0.06421*width, y: 0.02417*height), control1: CGPoint(x: 0.0591*width, y: 0.01985*height), control2: CGPoint(x: 0.06162*width, y: 0.02205*height))
        path.addCurve(to: CGPoint(x: 0.08865*width, y: 0.04775*height), control1: CGPoint(x: 0.07284*width, y: 0.03155*height), control2: CGPoint(x: 0.08072*width, y: 0.03964*height))
        path.addCurve(to: CGPoint(x: 0.09924*width, y: 0.05573*height), control1: CGPoint(x: 0.09345*width, y: 0.05289*height), control2: CGPoint(x: 0.09345*width, y: 0.05289*height))
        path.addCurve(to: CGPoint(x: 0.10413*width, y: 0.08545*height), control1: CGPoint(x: 0.10668*width, y: 0.06411*height), control2: CGPoint(x: 0.10451*width, y: 0.07472*height))
        path.addCurve(to: CGPoint(x: 0.10399*width, y: 0.0924*height), control1: CGPoint(x: 0.10408*width, y: 0.08774*height), control2: CGPoint(x: 0.10404*width, y: 0.09004*height))
        path.addCurve(to: CGPoint(x: 0.10352*width, y: 0.10938*height), control1: CGPoint(x: 0.10388*width, y: 0.09806*height), control2: CGPoint(x: 0.10372*width, y: 0.10372*height))
        path.addCurve(to: CGPoint(x: 0.05856*width, y: 0.06821*height), control1: CGPoint(x: 0.08803*width, y: 0.09616*height), control2: CGPoint(x: 0.07272*width, y: 0.08286*height))
        path.addCurve(to: CGPoint(x: 0.04297*width, y: 0.05469*height), control1: CGPoint(x: 0.05362*width, y: 0.06342*height), control2: CGPoint(x: 0.04825*width, y: 0.05909*height))
        path.addCurve(to: CGPoint(x: 0.04102*width, y: 0.18555*height), control1: CGPoint(x: 0.04232*width, y: 0.09787*height), control2: CGPoint(x: 0.04168*width, y: 0.14105*height))
        path.addCurve(to: CGPoint(x: 0, y: 0.18555*height), control1: CGPoint(x: 0.02748*width, y: 0.18555*height), control2: CGPoint(x: 0.01395*width, y: 0.18555*height))
        path.addCurve(to: CGPoint(x: 0, y: 0), control1: CGPoint(x: 0, y: 0.12432*height), control2: CGPoint(x: 0, y: 0.06309*height))
        path.closeSubpath()
        return path
    }
}

// MARK: - Service Icon Colors

struct ServiceColors {
    // Grey background for sidebar icons
    static let grey = Color.gray.opacity(0.3)
}

// MARK: - Convenience Views

/// Pre-configured Plex icon using PDF asset (grey background, original PDF colors)
struct PlexServiceIcon: View {
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(ServiceColors.grey)
                .frame(width: size, height: size)

            Image("plex")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundColor(.white)
                .frame(width: size * 0.65, height: size * 0.65)
        }
    }
}

/// Pre-configured TMDB icon using PDF asset (grey background, white foreground)
struct TMDBServiceIcon: View {
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(ServiceColors.grey)
                .frame(width: size, height: size)

            Image("tmdb")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundColor(.white)
                .frame(width: size * 0.65, height: size * 0.65)
        }
    }
}

/// Pre-configured Trakt icon using PDF asset (grey background, white foreground)
struct TraktServiceIcon: View {
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(ServiceColors.grey)
                .frame(width: size, height: size)

            Image("trakt")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundColor(.white)
                .frame(width: size * 0.65, height: size * 0.65)
        }
    }
}

/// Pre-configured Overseerr icon using PDF asset (grey background, original PDF colors)
struct OverseerrServiceIcon: View {
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(ServiceColors.grey)
                .frame(width: size, height: size)

            Image("overseerr")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundColor(.white)
                .frame(width: size * 0.65, height: size * 0.65)
        }
    }
}

/// Pre-configured MDBList icon using PDF asset (grey background, original PDF colors)
struct MDBListServiceIcon: View {
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(ServiceColors.grey)
                .frame(width: size, height: size)

            Image("mdblist")
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.65, height: size * 0.65)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ServiceIcons_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            Text("Settings Row Icons (28pt)")
                .font(.headline)
            HStack(spacing: 16) {
                PlexServiceIcon()
                TMDBServiceIcon()
                TraktServiceIcon()
                OverseerrServiceIcon()
                MDBListServiceIcon()
            }

            Text("Header Icons (64pt)")
                .font(.headline)
            HStack(spacing: 16) {
                PlexServiceIcon(size: 64)
                TMDBServiceIcon(size: 64)
                TraktServiceIcon(size: 64)
                OverseerrServiceIcon(size: 64)
                MDBListServiceIcon(size: 64)
            }
        }
        .padding(40)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
#endif
