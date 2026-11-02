import AppKit
import CoreGraphics

// 代码生成的矢量图标：两个文件与合并箭头，不复用第三方图标素材。
let root = CommandLine.arguments[1]
for size in [16, 32, 64, 128, 256, 512, 1024] {
  let colorSpace = CGColorSpaceCreateDeviceRGB()
  let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
    bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
  context.addPath(CGPath(roundedRect: CGRect(x: 64, y: 64, width: 896, height: 896), cornerWidth: 200, cornerHeight: 200, transform: nil))
  context.setFillColor(CGColor(red: 0.067, green: 0.082, blue: 0.11, alpha: 1)); context.fillPath()
  context.setLineWidth(32); context.setLineCap(.round); context.setLineJoin(.round)
  for (x, color) in [(CGFloat(220), CGColor(red: 0.60, green: 0.77, blue: 1, alpha: 1)),
                     (CGFloat(624), CGColor(red: 0.55, green: 0.86, blue: 0.67, alpha: 1))] {
    context.setStrokeColor(color)
    context.addPath(CGPath(roundedRect: CGRect(x: x, y: 320, width: 180, height: 400), cornerWidth: 22, cornerHeight: 22, transform: nil)); context.strokePath()
    for y in [CGFloat(620), 540, 460] {
      context.move(to: CGPoint(x: x + 46, y: y)); context.addLine(to: CGPoint(x: x + 130, y: y)); context.strokePath()
    }
  }
  context.setStrokeColor(CGColor(red: 0.60, green: 0.77, blue: 1, alpha: 1))
  context.move(to: CGPoint(x: 450, y: 562)); context.addLine(to: CGPoint(x: 574, y: 562));
  context.move(to: CGPoint(x: 540, y: 604)); context.addLine(to: CGPoint(x: 582, y: 562)); context.addLine(to: CGPoint(x: 540, y: 520)); context.strokePath()
  context.move(to: CGPoint(x: 310, y: 258)); context.addLine(to: CGPoint(x: 512, y: 194)); context.addLine(to: CGPoint(x: 714, y: 258)); context.strokePath()
  let image = context.makeImage()!
  let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
  try data.write(to: URL(fileURLWithPath: "\(root)/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_\(size).png"))
}
