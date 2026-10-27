import Foundation
@preconcurrency import AVFoundation
import Vision
import CoreMedia

enum CameraState: Equatable, Sendable { case off, starting, running, failed(String) }
struct CameraDevice: Identifiable { var id: String; var name: String }

/// Session mutations and Vision requests stay on one queue. Only numeric landmarks leave it.
final class PoseCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label:"poseboard.camera",qos:.userInitiated)
    private let onFrame: @Sendable (UUID,PoseFrame) -> Void
    private let onState: @Sendable (UUID,CameraState) -> Void
    private let request = VNDetectHumanHandPoseRequest()
    private var active = false
    private var generation = UUID()
    private var last = 0.0
    private var failures = 0
    static let jointNames: [VNHumanHandPoseObservation.JointName] = [
        .wrist,.thumbCMC,.thumbMP,.thumbIP,.thumbTip,
        .indexMCP,.indexPIP,.indexDIP,.indexTip,
        .middleMCP,.middlePIP,.middleDIP,.middleTip,
        .ringMCP,.ringPIP,.ringDIP,.ringTip,
        .littleMCP,.littlePIP,.littleDIP,.littleTip
    ]
    init(onFrame: @escaping @Sendable (UUID,PoseFrame) -> Void, onState: @escaping @Sendable (UUID,CameraState) -> Void) {
        self.onFrame = onFrame; self.onState = onState
        // Detect a third observation to reject extra hands, instead of silently choosing two.
        request.maximumHandCount = 3
    }
    static func devices() -> [CameraDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes:[.builtInWideAngleCamera,.external,.continuityCamera],mediaType:.video,position:.unspecified).devices.map { .init(id:$0.uniqueID,name:$0.localizedName) }
    }
    func start(deviceID: String?, generation: UUID) {
        queue.async { [self] in
            teardown(); self.generation = generation
            guard AVCaptureDevice.authorizationStatus(for:.video) == .authorized else { onState(generation,.failed("Allow Camera access in System Settings, then start the camera again.")); return }
            onState(generation,.starting)
            do {
                let devices = AVCaptureDevice.DiscoverySession(deviceTypes:[.builtInWideAngleCamera,.external,.continuityCamera],mediaType:.video,position:.unspecified).devices
                let device = deviceID.flatMap { id in devices.first { $0.uniqueID == id } } ?? (deviceID == nil ? AVCaptureDevice.default(for:.video) : nil)
                guard let device else { throw PoseError("The selected camera is unavailable. Choose another camera or reconnect it.") }
                session.beginConfiguration()
                do {
                    if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
                    let input = try AVCaptureDeviceInput(device:device)
                    guard session.canAddInput(input) else { throw PoseError("This camera cannot be opened.") }
                    session.addInput(input)
                    let output = AVCaptureVideoDataOutput(); output.alwaysDiscardsLateVideoFrames = true
                    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA]
                    output.setSampleBufferDelegate(self,queue:queue)
                    guard session.canAddOutput(output) else { throw PoseError("Camera processing could not start.") }
                    session.addOutput(output)
                    if let connection = output.connection(with:.video), connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false; connection.isVideoMirrored = false
                    }
                    session.commitConfiguration()
                } catch { session.commitConfiguration(); throw error }
                last = 0; failures = 0; session.startRunning()
                guard session.isRunning else { throw PoseError("The camera could not start. It may be disconnected or in use.") }
                active = true; onState(generation,.running)
            } catch { teardown(); onState(generation,.failed(error.localizedDescription)) }
        }
    }
    func stop() { queue.async { [self] in teardown(); onState(generation,.off) } }
    private func teardown() {
        active = false
        if session.isRunning { session.stopRunning() }
        session.beginConfiguration()
        for output in session.outputs { session.removeOutput(output) }
        for input in session.inputs { session.removeInput(input) }
        session.commitConfiguration()
    }
    func captureOutput(_ output: AVCaptureOutput,didOutput buffer: CMSampleBuffer,from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        guard active, now-last >= 1/15.0, let pixel = CMSampleBufferGetImageBuffer(buffer) else { return }
        last = now
        do {
            try VNImageRequestHandler(cvPixelBuffer:pixel,orientation:.up).perform([request])
            let observations = request.results ?? []
            let hands = observations.map { observation in
                ObservedHand(joints:Self.jointNames.map { key in
                    guard let p = try? observation.recognizedPoint(key), p.confidence >= 0.15,
                          p.location.x.isFinite, p.location.y.isFinite else { return nil }
                    return Joint(point:.init(x:1-p.location.x,y:p.location.y),confidence:Double(p.confidence))
                })
            }
            failures = 0
            onFrame(generation,.init(time:now,hands:hands,detectedCount:observations.count,width:Double(CVPixelBufferGetWidth(pixel)),height:Double(CVPixelBufferGetHeight(pixel))))
        } catch {
            failures += 1; onFrame(generation,.init(time:now))
            if failures >= 15 { teardown(); onState(generation,.failed("Hand tracking stopped. Restart the camera to try again.")) }
        }
    }
}
