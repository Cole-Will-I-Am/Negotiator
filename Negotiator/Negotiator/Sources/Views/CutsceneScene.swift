import SpriteKit
import SwiftUI
import UIKit

// Procedural "approach the bridge" intro — the shippable placeholder behind the same CutsceneView
// interface (and a low-data fallback even after real footage lands). Stylized + atmospheric:
// a Gloaming gradient sky, a low moon, drifting fog, the bridge in shadow, and Bartholomew's two
// amber eyes blinking slowly open. Hard art note: lonely / ancient / curious, never menacing.
final class CutsceneSKScene: SKScene {
    var onEnd: (() -> Void)?
    private var ended = false

    override func didMove(to view: SKView) {
        backgroundColor = UIColor(Palette.ink)
        buildSky()
        buildMoon()
        buildBridge()
        buildEyes()
        buildFog()
        buildTitle()
        run(.sequence([.wait(forDuration: 8.5), .run { [weak self] in self?.finish() }]))
    }

    func finish() { guard !ended else { return }; ended = true; onEnd?() }

    private func buildSky() {
        let img = CutsceneArt.verticalGradient(size: size, top: UIColor(Palette.troll), bottom: UIColor(Palette.ink))
        let sky = SKSpriteNode(texture: SKTexture(image: img))
        sky.size = size
        sky.position = CGPoint(x: size.width / 2, y: size.height / 2)
        sky.zPosition = -10
        addChild(sky)
    }

    private func buildMoon() {
        let moon = SKShapeNode(circleOfRadius: size.width * 0.10)
        moon.fillColor = UIColor(Palette.gold).withAlphaComponent(0.85)
        moon.strokeColor = .clear
        moon.glowWidth = 16
        moon.position = CGPoint(x: size.width * 0.64, y: size.height * 0.76)
        moon.zPosition = -5
        moon.alpha = 0
        moon.run(.fadeAlpha(to: 0.85, duration: 2.2))
        addChild(moon)
    }

    private func buildBridge() {
        // A dark mass across the lower third — the bridge in shadow, where the eyes glow.
        let h = size.height * 0.34
        let bridge = SKShapeNode(rectOf: CGSize(width: size.width * 1.15, height: h), cornerRadius: 30)
        bridge.fillColor = UIColor(Palette.ink)
        bridge.strokeColor = .clear
        bridge.position = CGPoint(x: size.width / 2, y: h * 0.40)
        bridge.zPosition = 2
        addChild(bridge)
    }

    private func buildEyes() {
        let y = size.height * 0.24
        let dx = size.width * 0.06
        let r = size.width * 0.024
        for sign in [-1.0, 1.0] {
            let eye = SKShapeNode(ellipseOf: CGSize(width: r * 2.2, height: r * 1.6))
            eye.fillColor = UIColor(Palette.gold)
            eye.strokeColor = UIColor(Palette.amber)
            eye.lineWidth = 1
            eye.glowWidth = 9
            eye.position = CGPoint(x: size.width / 2 + CGFloat(sign) * dx, y: y)
            eye.yScale = 0.02      // closed
            eye.alpha = 0
            eye.zPosition = 6
            addChild(eye)
            eye.run(.sequence([
                .wait(forDuration: 4.3),
                .group([.fadeAlpha(to: 0.95, duration: 1.3), .scaleY(to: 1.0, duration: 1.3)]),   // blink open, slow
                .repeatForever(.sequence([.fadeAlpha(to: 0.70, duration: 1.6), .fadeAlpha(to: 0.95, duration: 1.6)])),
            ]))
        }
    }

    private func buildFog() {
        let fog = SKEmitterNode()
        fog.particleTexture = SKTexture(image: CutsceneArt.softDot(diameter: 120))
        fog.particleBirthRate = 5
        fog.numParticlesToEmit = 0
        fog.particleLifetime = 16
        fog.particleLifetimeRange = 6
        fog.position = CGPoint(x: size.width * 0.5, y: size.height * 0.34)
        fog.particlePositionRange = CGVector(dx: size.width * 1.5, dy: size.height * 0.4)
        fog.particleAlpha = 0.05
        fog.particleAlphaRange = 0.04
        fog.particleScale = 3.0
        fog.particleScaleRange = 1.6
        fog.particleSpeed = 9
        fog.particleSpeedRange = 7
        fog.emissionAngle = 0
        fog.emissionAngleRange = .pi
        fog.particleColor = UIColor(Palette.paper)
        fog.particleColorBlendFactor = 1
        fog.zPosition = 4
        fog.advanceSimulationTime(10)   // pre-warm so fog is present at t=0
        addChild(fog)
    }

    private func buildTitle() {
        let label = SKLabelNode(text: "The Mossback Bridge")
        label.fontName = "Georgia-Bold"
        label.fontSize = size.width * 0.062
        label.fontColor = UIColor(Palette.paper)
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: size.width / 2, y: size.height * 0.54)
        label.alpha = 0
        label.zPosition = 8
        addChild(label)
        label.run(.sequence([.wait(forDuration: 6.4), .fadeAlpha(to: 1.0, duration: 1.1)]))
    }
}

// Tiny procedural texture helpers (no bundled assets needed).
enum CutsceneArt {
    static func verticalGradient(size: CGSize, top: UIColor, bottom: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
    }
    static func softDot(diameter: CGFloat) -> UIImage {
        let s = CGSize(width: diameter, height: diameter)
        let renderer = UIGraphicsImageRenderer(size: s)
        return renderer.image { ctx in
            let c = CGPoint(x: diameter / 2, y: diameter / 2)
            let colors = [UIColor.white.withAlphaComponent(0.9).cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            ctx.cgContext.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: diameter / 2, options: [])
        }
    }
}

struct ProceduralCutscene: UIViewRepresentable {
    let onEnd: () -> Void
    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.backgroundColor = UIColor(Palette.ink)
        let scene = CutsceneSKScene(size: UIScreen.main.bounds.size)
        scene.scaleMode = .resizeFill
        scene.onEnd = onEnd
        view.presentScene(scene)
        return view
    }
    func updateUIView(_ uiView: SKView, context: Context) {}
}
