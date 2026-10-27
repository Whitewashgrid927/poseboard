import AppKit
import Foundation
let directory = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
for (name,pixels) in [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),("icon_512x512",512),("icon_512x512@2x",1024)] {
    let size = CGFloat(pixels)
    let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
    let rect = NSRect(x:size*0.06,y:size*0.06,width:size*0.88,height:size*0.88)
    let path = NSBezierPath(roundedRect:rect,xRadius:size*0.21,yRadius:size*0.21)
    NSGradient(colors:[NSColor(red:0.32,green:0.35,blue:0.85,alpha:1),NSColor(red:0.73,green:0.79,blue:1,alpha:1)])!.draw(in:path,angle:55)
    NSColor.white.withAlphaComponent(0.5).setStroke();path.lineWidth = max(0.5,size*0.006);path.stroke()
    // Original communication-bubble mark, drawn locally; no downloaded assets.
    let bubble = NSBezierPath(roundedRect:NSRect(x:size*0.20,y:size*0.31,width:size*0.60,height:size*0.43),xRadius:size*0.12,yRadius:size*0.12)
    NSColor.white.withAlphaComponent(0.94).setFill();bubble.fill()
    let tail = NSBezierPath();tail.move(to:.init(x:size*0.30,y:size*0.34));tail.line(to:.init(x:size*0.29,y:size*0.23));tail.line(to:.init(x:size*0.45,y:size*0.34));tail.close();tail.fill()
    NSColor(red:0.42,green:0.46,blue:0.88,alpha:1).setFill()
    for x in [0.38,0.56] { NSBezierPath(roundedRect:NSRect(x:size*x,y:size*0.43,width:size*0.065,height:size*0.19),xRadius:size*0.03,yRadius:size*0.03).fill() }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent(name+".png"))
}
