import SwiftUI

/// A neutral schematic of what the sex-linked staging scale *measures* — a top-down head with the
/// scale's characteristic assessment zones softly shaded. Norwood looks at frontal/temporal
/// recession plus the vertex; Ludwig looks at widening of the central part with the hairline
/// preserved. This illustrates the measurement pattern only — it is not a prediction and not the
/// user's own stage, so the shading stays calm (accentSoft fill, thin accent edge).
struct StagingScalePreview: View {
    let sex: BiologicalSex
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isLudwig: Bool { sex == .female }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                // Soft top-down head — nose notch (front, top) and ears orient the schematic.
                TopDownHeadShape()
                    .fill(Clinical.surface)
                    .shadow(color: Clinical.cardShadow, radius: 8, y: 3)
                TopDownHeadShape()
                    .stroke(Clinical.hairline, lineWidth: 1.5)

                // Norwood: frontal + temporal recession at the hairline, plus a vertex zone.
                ZStack {
                    NorwoodZonesShape().fill(Clinical.accentSoft)
                    NorwoodZonesShape().stroke(Clinical.accent.opacity(0.45), lineWidth: 1)
                }
                .opacity(isLudwig ? 0 : 1)

                // Ludwig: a widening central part down the mid-scalp; front hairline preserved.
                ZStack {
                    LudwigZoneShape().fill(Clinical.accentSoft)
                    LudwigZoneShape().stroke(Clinical.accent.opacity(0.45), lineWidth: 1)
                }
                .opacity(isLudwig ? 1 : 0)
            }
            .frame(width: 108, height: 118)

            VStack(spacing: 3) {
                Text("\(sex.stagingScaleName.uppercased()) SCALE")
                    .font(Clinical.eyebrow(10))
                    .tracking(1.4)
                    .foregroundStyle(Clinical.accent)
                Text(isLudwig ? "Assesses width of the central part" : "Assesses the hairline and crown")
                    .font(.system(size: 11))
                    .foregroundStyle(Clinical.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: isLudwig)
        .accessibilityHidden(true)
    }
}

// MARK: - Shared geometry

/// The head oval, inset so the nose notch and ears fit inside the shape's bounding rect.
private func headOval(in rect: CGRect) -> CGRect {
    rect.insetBy(dx: rect.width * 0.10, dy: rect.height * 0.055)
}

/// A point on the head oval at `angle` (radians; -π/2 is the front/top), optionally scaled inward.
private func ovalPoint(_ oval: CGRect, angle: CGFloat, scale: CGFloat = 1) -> CGPoint {
    CGPoint(x: oval.midX + cos(angle) * oval.width * 0.5 * scale,
            y: oval.midY + sin(angle) * oval.height * 0.5 * scale)
}

// MARK: - Head outline

/// Top-down head: an oval with a small nose notch at the front (top) and two ears at the sides.
private struct TopDownHeadShape: Shape {
    func path(in rect: CGRect) -> Path {
        let oval = headOval(in: rect)
        var p = Path()

        // Nose notch — small bump peeking above the front rim.
        let noseW = oval.width * 0.18
        let noseH = rect.height * 0.075
        p.addEllipse(in: CGRect(x: oval.midX - noseW / 2, y: oval.minY - noseH * 0.55,
                                width: noseW, height: noseH))

        // Ears — small lobes at the sides, slightly behind the midpoint.
        let earW = rect.width * 0.115
        let earH = oval.height * 0.20
        let earY = oval.midY - earH * 0.42
        p.addEllipse(in: CGRect(x: oval.minX - earW * 0.55, y: earY, width: earW, height: earH))
        p.addEllipse(in: CGRect(x: oval.maxX - earW * 0.45, y: earY, width: earW, height: earH))

        // Head last, so its fill sits over the notch/ear junctions.
        p.addEllipse(in: oval)
        return p
    }
}

// MARK: - Norwood zones (male / other)

/// The Norwood pattern: one band hugging the front rim — shallow at the mid-front, sweeping
/// deeper at both temples (the characteristic "M") — plus a separate vertex (crown) oval.
private struct NorwoodZonesShape: Shape {
    func path(in rect: CGRect) -> Path {
        let oval = headOval(in: rect)
        let w = oval.width
        let h = oval.height
        let cx = oval.midX
        var p = Path()

        // Outer edge: follow the front rim (slightly inset) from left temple to right temple.
        let startAngle: CGFloat = -.pi * 0.82
        let endAngle: CGFloat = -.pi * 0.18
        let steps = 24
        p.move(to: ovalPoint(oval, angle: startAngle, scale: 0.93))
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let angle = startAngle + (endAngle - startAngle) * t
            p.addLine(to: ovalPoint(oval, angle: angle, scale: 0.93))
        }
        // Inner edge: the receded hairline — deep at the temples, forward at the mid-front.
        p.addQuadCurve(to: CGPoint(x: cx, y: oval.minY + h * 0.155),
                       control: CGPoint(x: cx + w * 0.30, y: oval.minY + h * 0.335))
        p.addQuadCurve(to: ovalPoint(oval, angle: startAngle, scale: 0.93),
                       control: CGPoint(x: cx - w * 0.30, y: oval.minY + h * 0.335))
        p.closeSubpath()

        // Vertex (crown) zone toward the back of the scalp.
        let vertexW = w * 0.30
        let vertexH = h * 0.24
        p.addEllipse(in: CGRect(x: cx - vertexW / 2, y: oval.minY + h * 0.70 - vertexH / 2,
                                width: vertexW, height: vertexH))
        return p
    }
}

// MARK: - Ludwig zone (female)

/// The Ludwig pattern: a lens along the midline part — narrow behind the preserved front
/// hairline, widening over the mid-scalp — plus the part line itself.
private struct LudwigZoneShape: Shape {
    func path(in rect: CGRect) -> Path {
        let oval = headOval(in: rect)
        let w = oval.width
        let h = oval.height
        let cx = oval.midX
        let top = CGPoint(x: cx, y: oval.minY + h * 0.20)
        let bottom = CGPoint(x: cx, y: oval.minY + h * 0.76)
        var p = Path()

        // Widening lens, broadest over the mid/rear scalp.
        p.move(to: top)
        p.addCurve(to: bottom,
                   control1: CGPoint(x: cx + w * 0.10, y: oval.minY + h * 0.34),
                   control2: CGPoint(x: cx + w * 0.16, y: oval.minY + h * 0.62))
        p.addCurve(to: top,
                   control1: CGPoint(x: cx - w * 0.16, y: oval.minY + h * 0.62),
                   control2: CGPoint(x: cx - w * 0.10, y: oval.minY + h * 0.34))
        p.closeSubpath()

        // The central part line (zero-area subpath: shows in the stroke pass only).
        p.move(to: top)
        p.addLine(to: bottom)
        return p
    }
}

#Preview {
    VStack(spacing: 24) {
        StagingScalePreview(sex: .male)
        StagingScalePreview(sex: .female)
    }
    .padding()
    .background(Clinical.canvas)
}
