import AppKit
import SwiftUI
@preconcurrency import AVFoundation

struct CameraPreview: NSViewRepresentable {
    let camera: PoseCamera
    func makeNSView(context: Context) -> PreviewView { let view = PreviewView(); view.preview.session = camera.session; view.mirror(); return view }
    func updateNSView(_ view: PreviewView,context: Context) { view.mirror() }
}
final class PreviewView: NSView {
    let preview = AVCaptureVideoPreviewLayer()
    override init(frame: NSRect) {
        super.init(frame:frame); wantsLayer = true; layer?.backgroundColor = NSColor.black.cgColor
        preview.videoGravity = .resizeAspect; layer?.addSublayer(preview)
    }
    required init?(coder: NSCoder) { nil }
    override func layout() { super.layout(); CATransaction.begin(); CATransaction.setDisableActions(true); preview.frame = bounds; CATransaction.commit(); mirror() }
    func mirror() {
        guard let connection = preview.connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false; connection.isVideoMirrored = true
    }
}
struct Landmarks: View {
    let frame: PoseFrame
    static let chains = [[0,1,2,3,4],[0,5,6,7,8],[0,9,10,11,12],[0,13,14,15,16],[0,17,18,19,20],[5,9,13,17]]
    var body: some View {
        Canvas { context,size in
            let scale = min(size.width/max(1,frame.width),size.height/max(1,frame.height))
            let width = frame.width*scale, height = frame.height*scale
            func position(_ p: Vector) -> CGPoint { .init(x:(size.width-width)/2+p.x*width,y:(size.height-height)/2+(1-p.y)*height) }
            for hand in frame.hands where hand.joints.count == 21 {
                for chain in Self.chains {
                    for i in 1..<chain.count {
                        if let a = hand.joints[chain[i-1]],let b = hand.joints[chain[i]],a.confidence >= 0.35,b.confidence >= 0.35 {
                            var line = Path(); line.move(to:position(a.point)); line.addLine(to:position(b.point))
                            context.stroke(line,with:.color(.white.opacity(0.55)),style:.init(lineWidth:1.3,lineCap:.round))
                        }
                    }
                }
                for joint in hand.joints.compactMap({$0}) where joint.confidence >= 0.35 {
                    let p = position(joint.point)
                    context.fill(Path(ellipseIn:.init(x:p.x-3,y:p.y-3,width:6,height:6)),with:.color(Color(red:0.67,green:0.76,blue:1)))
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
struct PoseDrawing: View {
    let signature: PoseSignature
    var body: some View {
        Canvas { context,size in
            for (index,hand) in [signature.first,signature.second].enumerated() {
                let values = hand.compactMap{$0}
                let minX = values.map(\.x).min() ?? -1, maxX = values.map(\.x).max() ?? 1
                let minY = values.map(\.y).min() ?? -1, maxY = values.map(\.y).max() ?? 1
                let scale = min((size.width/2-34)/max(0.5,maxX-minX),(size.height-32)/max(0.5,maxY-minY))
                func position(_ p: Vector) -> CGPoint {
                    .init(x:size.width*(Double(index)*0.5+0.25)+(p.x-(minX+maxX)/2)*scale,y:size.height/2-(p.y-(minY+maxY)/2)*scale)
                }
                for chain in Landmarks.chains {
                    for i in 1..<chain.count {
                        if let a = hand[chain[i-1]],let b = hand[chain[i]] {
                            var line = Path(); line.move(to:position(a)); line.addLine(to:position(b))
                            context.stroke(line,with:.color(.indigo.opacity(0.6)),style:.init(lineWidth:2,lineCap:.round))
                        }
                    }
                }
                for p in values { let p = position(p); context.fill(Path(ellipseIn:.init(x:p.x-3,y:p.y-3,width:6,height:6)),with:.color(.indigo)) }
            }
        }.accessibilityLabel("Saved landmark drawing of your two-hand pose")
    }
}
struct CameraStage: View {
    @ObservedObject var store: PoseStore
    var compact = false
    var bottomInset: CGFloat = 0
    var body: some View {
        ZStack {
            LinearGradient(colors:[Color(red:0.89,green:0.92,blue:0.99),Color(red:0.97,green:0.93,blue:0.91),Color(red:0.85,green:0.91,blue:0.98)],startPoint:.topLeading,endPoint:.bottomTrailing)
            if store.running {
                CameraPreview(camera:store.camera)
                Landmarks(frame:store.frame)
                VStack {
                    HStack(spacing:7) {
                        Circle().fill(store.frame.detectedCount == 2 ? Color.green : .orange).frame(width:7,height:7)
                        Text(store.trackingText).font(.system(size:12,weight:.medium))
                    }.padding(.horizontal,14).padding(.vertical,9).glassEffect(.regular,in:.capsule)
                    Spacer()
                }.padding(.top,compact ? 12 : 24)
            } else {
                VStack(spacing:14) {
                    HStack(spacing:4) {
                        Image(systemName:"hand.raised.fill").scaleEffect(x:-1,y:1)
                        Image(systemName:"hand.raised.fill")
                    }.font(.system(size:compact ? 36 : 50,weight:.ultraLight)).foregroundStyle(.indigo.opacity(0.65))
                    Text(compact ? "Show both hands" : "A meaning in every pose").font(.system(size:compact ? 20 : 28,weight:.medium,design:.rounded))
                    Text("Teach with your hands. Keep it on your Mac.").font(.system(size:13)).foregroundStyle(.secondary)
                    if store.cameraState == .starting { ProgressView().controlSize(.small).padding(8) }
                    else {
                        Button { store.startCamera() } label: { Label("Start camera",systemImage:"video").padding(.horizontal,8).padding(.vertical,3) }
                            .buttonStyle(.glassProminent).tint(.indigo)
                    }
                    if case .failed(let message) = store.cameraState {
                        Text(message).font(.system(size:12)).multilineTextAlignment(.center).frame(maxWidth:430)
                        Button("Camera settings") { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!) }.buttonStyle(.link)
                    }
                    if let notice = store.notice { Text(notice).font(.system(size:12)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth:460) }
                }.padding(24).frame(maxWidth:.infinity,maxHeight:.infinity).padding(.bottom,compact ? 0 : bottomInset)
            }
        }
    }
}
