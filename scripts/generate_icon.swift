import AppKit
import CoreGraphics

let size = CGSize(width: 1024, height: 1024)
let image = NSImage(size: size)

image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else {
    exit(1)
}

// 1. Background Squircle / Rounded Rect (Apple standard macOS app icon shape)
let squircleRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let cornerRadius: CGFloat = 185
let path = CGPath(roundedRect: squircleRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

// Shadow
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -20), blur: 50, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.6))

// Base Gradient (Deep Space Black to Dark Titanium Navy)
let colorSpace = CGColorSpaceCreateDeviceRGB()
let colors = [
    CGColor(red: 0.08, green: 0.10, blue: 0.18, alpha: 1.0),
    CGColor(red: 0.03, green: 0.04, blue: 0.07, alpha: 1.0)
] as CFArray

if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
    context.addPath(path)
    context.clip()
    context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
}
context.restoreGState()

// Subtle metallic rim
context.saveGState()
context.addPath(path)
context.setLineWidth(6)
context.setStrokeColor(CGColor(red: 0.3, green: 0.5, blue: 0.9, alpha: 0.4))
context.strokePath()
context.restoreGState()

// Glowing Cyber Circle in center
context.saveGState()
let centerGlow = CGRect(x: 312, y: 312, width: 400, height: 400)
context.addEllipse(in: centerGlow)
context.setShadow(offset: .zero, blur: 80, color: CGColor(red: 0.1, green: 0.6, blue: 1.0, alpha: 0.8))
context.setFillColor(CGColor(red: 0.08, green: 0.15, blue: 0.3, alpha: 0.5))
context.fillPath()
context.restoreGState()

// Game Controller Silhouette using SF Symbols
if let symbol = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: nil) {
    let config = NSImage.SymbolConfiguration(pointSize: 420, weight: .bold)
    if let configuredSymbol = symbol.withSymbolConfiguration(config) {
        let symbolRect = CGRect(x: 232, y: 232, width: 560, height: 560)
        
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -8), blur: 30, color: CGColor(red: 0.2, green: 0.8, blue: 1.0, alpha: 0.7))
        
        // Draw icon in bright cyan/electric blue gradient
        let tint = NSColor(calibratedRed: 0.3, green: 0.8, blue: 1.0, alpha: 1.0)
        tint.set()
        configuredSymbol.draw(in: symbolRect)
        context.restoreGState()
    }
}

image.unlockFocus()

// Save PNG representation
guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    exit(1)
}

let fm = FileManager.default
let iconsetDir = URL(fileURLWithPath: "AppIcon.iconset")
try? fm.removeItem(at: iconsetDir)
try? fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let iconSizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, targetSize) in iconSizes {
    let resized = NSImage(size: CGSize(width: targetSize, height: targetSize))
    resized.lockFocus()
    image.draw(in: CGRect(x: 0, y: 0, width: targetSize, height: targetSize),
               from: CGRect(origin: .zero, size: size),
               operation: .copy,
               fraction: 1.0)
    resized.unlockFocus()
    
    if let tiff = resized.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: iconsetDir.appendingPathComponent(name))
    }
}

print("Generated AppIcon.iconset with all resolutions.")
