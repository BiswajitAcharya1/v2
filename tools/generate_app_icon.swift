import AppKit
import CoreGraphics
import Foundation

struct IconRenderer {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

    func renderAll() throws {
        let iconDir = root.appendingPathComponent("Notebook/Assets.xcassets/AppIcon.appiconset")
        let launchDir = root.appendingPathComponent("Notebook/Assets.xcassets/LaunchNotebookMark.imageset")

        let iconSizes: [(String, CGFloat)] = [
            ("AppIcon-40.png", 40),
            ("AppIcon-58.png", 58),
            ("AppIcon-60.png", 60),
            ("AppIcon-80.png", 80),
            ("AppIcon-87.png", 87),
            ("AppIcon-120.png", 120),
            ("AppIcon-180.png", 180),
            ("AppIcon-1024.png", 1024)
        ]

        for (name, size) in iconSizes {
            try writePNG(drawAppIcon(size: size), to: iconDir.appendingPathComponent(name))
        }

        let launchSizes: [(String, CGFloat)] = [
            ("LaunchNotebookMark-1x.png", 240),
            ("LaunchNotebookMark-2x.png", 480),
            ("LaunchNotebookMark-3x.png", 720)
        ]

        for (name, size) in launchSizes {
            try writePNG(drawLaunchMark(size: size), to: launchDir.appendingPathComponent(name))
        }

        try writePNG(drawLaunchMark(size: 720), to: root.appendingPathComponent("Notebook/LaunchNotebookMark.png"))
    }

    private func drawAppIcon(size: CGFloat) -> NSImage {
        draw(size: size) { context, scale in
            drawIconBackground(in: context, size: size, scale: scale)
            drawFlowingNotebookMark(in: context, rect: CGRect(x: size * 0.18, y: size * 0.19, width: size * 0.64, height: size * 0.62), scale: scale, showShadow: true)
            drawSpecularArc(in: context, size: size)
        }
    }

    private func drawLaunchMark(size: CGFloat) -> NSImage {
        draw(size: size) { context, scale in
            context.clear(CGRect(x: 0, y: 0, width: size, height: size))
            drawFlowingNotebookMark(in: context, rect: CGRect(x: size * 0.18, y: size * 0.17, width: size * 0.64, height: size * 0.66), scale: scale, showShadow: false)
        }
    }

    private func draw(size: CGFloat, _ block: (CGContext, CGFloat) -> Void) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
        }
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        block(context, max(size / 1024, 0.08))
        image.unlockFocus()
        return image
    }

    private func drawIconBackground(in context: CGContext, size: CGFloat, scale: CGFloat) {
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        let colors = [
            CGColor(red: 0.965, green: 0.965, blue: 0.94, alpha: 1),
            CGColor(red: 0.84, green: 0.88, blue: 0.83, alpha: 1),
            CGColor(red: 1.0, green: 0.82, blue: 0.72, alpha: 1)
        ] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.54, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.34))
        context.fillEllipse(in: CGRect(x: size * 0.08, y: size * 0.06, width: size * 0.64, height: size * 0.64))

        context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.72))
        context.setLineWidth(max(2, 8 * scale))
        context.addPath(rounded(rect.insetBy(dx: size * 0.045, dy: size * 0.045), radius: size * 0.21))
        context.strokePath()
    }

    private func drawFlowingNotebookMark(in context: CGContext, rect: CGRect, scale: CGFloat, showShadow: Bool) {
        if showShadow {
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: 24 * scale), blur: 34 * scale, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.17))
            drawOpenPages(in: context, rect: rect, scale: scale)
            context.restoreGState()
        } else {
            drawOpenPages(in: context, rect: rect, scale: scale)
        }

        drawMarbledSliver(in: context, rect: rect, scale: scale)
        drawCenterFold(in: context, rect: rect, scale: scale)
        drawInkCurve(in: context, rect: rect, scale: scale)
    }

    private func drawOpenPages(in context: CGContext, rect: CGRect, scale: CGFloat) {
        let left = CGRect(x: rect.minX + rect.width * 0.1, y: rect.minY + rect.height * 0.09, width: rect.width * 0.42, height: rect.height * 0.78)
        let right = CGRect(x: rect.minX + rect.width * 0.48, y: rect.minY + rect.height * 0.07, width: rect.width * 0.42, height: rect.height * 0.8)
        let page = CGColor(red: 0.975, green: 0.975, blue: 0.955, alpha: 1)
        let edge = CGColor(red: 0.69, green: 0.72, blue: 0.74, alpha: 0.26)

        context.setFillColor(page)
        context.addPath(pagePath(left, leftSide: true))
        context.fillPath()
        context.addPath(pagePath(right, leftSide: false))
        context.fillPath()

        context.setStrokeColor(edge)
        context.setLineWidth(max(0.7, 1.5 * scale))
        context.addPath(pagePath(left, leftSide: true))
        context.strokePath()
        context.addPath(pagePath(right, leftSide: false))
        context.strokePath()

        for index in 0..<7 {
            let y = rect.minY + rect.height * (0.28 + CGFloat(index) * 0.065)
            context.setStrokeColor(CGColor(red: 0.36, green: 0.62, blue: 0.82, alpha: 0.23))
            context.setLineWidth(max(0.5, 1.1 * scale))
            context.move(to: CGPoint(x: left.minX + left.width * 0.2, y: y))
            context.addCurve(to: CGPoint(x: right.maxX - right.width * 0.16, y: y + sin(CGFloat(index)) * 2 * scale), control1: CGPoint(x: rect.midX - 22 * scale, y: y - 4 * scale), control2: CGPoint(x: rect.midX + 22 * scale, y: y + 4 * scale))
            context.strokePath()
        }
    }

    private func drawMarbledSliver(in context: CGContext, rect: CGRect, scale: CGFloat) {
        let sliver = CGRect(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.14, width: rect.width * 0.15, height: rect.height * 0.73)
        context.setFillColor(CGColor(red: 0.02, green: 0.02, blue: 0.018, alpha: 1))
        context.addPath(rounded(sliver, radius: 30 * scale))
        context.fillPath()

        context.saveGState()
        context.addPath(rounded(sliver, radius: 30 * scale))
        context.clip()
        for index in 0..<130 {
            let x = sliver.minX + sliver.width * CGFloat((index * 37) % 101) / 101
            let y = sliver.minY + sliver.height * CGFloat((index * 61) % 103) / 103
            let w = max(1, CGFloat((index % 5) + 2) * scale)
            let a = index.isMultiple(of: 3) ? 0.72 : 0.38
            context.setFillColor(CGColor(red: 0.9, green: 0.91, blue: 0.88, alpha: a))
            context.fillEllipse(in: CGRect(x: x, y: y, width: w, height: max(1, w * 0.55)))
        }
        context.restoreGState()

        context.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.3))
        context.setLineWidth(max(1, 2 * scale))
        context.addPath(rounded(sliver, radius: 30 * scale))
        context.strokePath()
    }

    private func drawCenterFold(in context: CGContext, rect: CGRect, scale: CGFloat) {
        context.setStrokeColor(CGColor(red: 0.13, green: 0.13, blue: 0.12, alpha: 0.2))
        context.setLineWidth(max(1, 2 * scale))
        context.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.17))
        context.addCurve(to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.14), control1: CGPoint(x: rect.midX - 18 * scale, y: rect.midY - 62 * scale), control2: CGPoint(x: rect.midX + 18 * scale, y: rect.midY + 52 * scale))
        context.strokePath()
    }

    private func drawInkCurve(in context: CGContext, rect: CGRect, scale: CGFloat) {
        context.setStrokeColor(CGColor(red: 0.06, green: 0.06, blue: 0.055, alpha: 0.86))
        context.setLineWidth(max(2.2, 6 * scale))
        context.setLineCap(.round)
        context.move(to: CGPoint(x: rect.minX + rect.width * 0.32, y: rect.minY + rect.height * 0.61))
        context.addCurve(to: CGPoint(x: rect.maxX - rect.width * 0.22, y: rect.minY + rect.height * 0.6), control1: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.48), control2: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.minY + rect.height * 0.74))
        context.strokePath()
    }

    private func drawSpecularArc(in context: CGContext, size: CGFloat) {
        context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.34))
        context.setLineWidth(max(1, size * 0.006))
        context.setLineCap(.round)
        context.move(to: CGPoint(x: size * 0.22, y: size * 0.82))
        context.addCurve(to: CGPoint(x: size * 0.77, y: size * 0.86), control1: CGPoint(x: size * 0.34, y: size * 0.94), control2: CGPoint(x: size * 0.64, y: size * 0.94))
        context.strokePath()
    }

    private func pagePath(_ rect: CGRect, leftSide: Bool) -> CGPath {
        let path = CGMutablePath()
        if leftSide {
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY))
            path.addCurve(to: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.12), control1: CGPoint(x: rect.minX - rect.width * 0.05, y: rect.height * 0.36 + rect.minY), control2: CGPoint(x: rect.minX + rect.width * 0.04, y: rect.maxY - rect.height * 0.28))
            path.addCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control1: CGPoint(x: rect.width * 0.26 + rect.minX, y: rect.maxY + rect.height * 0.05), control2: CGPoint(x: rect.width * 0.76 + rect.minX, y: rect.maxY - rect.height * 0.03))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.08))
            path.addCurve(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY), control1: CGPoint(x: rect.width * 0.72 + rect.minX, y: rect.minY + rect.height * 0.02), control2: CGPoint(x: rect.width * 0.34 + rect.minX, y: rect.minY - rect.height * 0.03))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.08))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.12), control1: CGPoint(x: rect.width * 0.3 + rect.minX, y: rect.maxY - rect.height * 0.03), control2: CGPoint(x: rect.width * 0.72 + rect.minX, y: rect.maxY + rect.height * 0.05))
            path.addCurve(to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.minY), control1: CGPoint(x: rect.maxX - rect.width * 0.04, y: rect.maxY - rect.height * 0.28), control2: CGPoint(x: rect.maxX + rect.width * 0.05, y: rect.height * 0.36 + rect.minY))
            path.addCurve(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.08), control1: CGPoint(x: rect.width * 0.66 + rect.minX, y: rect.minY - rect.height * 0.03), control2: CGPoint(x: rect.width * 0.28 + rect.minX, y: rect.minY + rect.height * 0.02))
        }
        path.closeSubpath()
        return path
    }

    private func rounded(_ rect: CGRect, radius: CGFloat) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    private func writePNG(_ image: NSImage, to url: URL) throws {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "IconRenderer", code: 1, userInfo: [NSLocalizedDescriptionKey: "could not encode \(url.lastPathComponent)"])
        }
        try png.write(to: url, options: .atomic)
    }
}

try IconRenderer().renderAll()
