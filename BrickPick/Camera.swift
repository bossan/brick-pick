import AVFoundation
import CoreGraphics

/// Owns the capture session and runs every other video frame through a `FrameAnalyzer`.
final class Camera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    /// Called on the main queue for each analysed frame.
    var onOutput: ((FrameAnalyzer.Output) -> Void)?

    // The analyzer and device are only touched on this queue.
    private let queue = DispatchQueue(label: "BrickPick.camera")
    private var analyzer = FrameAnalyzer()
    private var device: AVCaptureDevice?
    private var frameCount = 0
    private var paletteGeneration = 0

    /// Asks for camera access and starts capturing. Returns false when there is no usable camera.
    func start() async -> Bool {
        #if targetEnvironment(simulator)
        startSimulatedFrames()
        return true
        #else
        guard await AVCaptureDevice.requestAccess(for: .video) else { return false }
        return await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.configure()) }
        }
        #endif
    }

    /// Switches the colours samples are matched against and the colour being looked for.
    /// The mask is off until the new lookup table has been built in the background.
    func setPalette(_ palette: Palette, targetIndex: Int?) {
        queue.async {
            self.paletteGeneration += 1
            let generation = self.paletteGeneration
            self.analyzer.palette = palette
            self.analyzer.lut = nil
            DispatchQueue.global(qos: .userInitiated).async {
                let lut = PaletteLUT(palette: palette, targetIndex: targetIndex)
                self.queue.async {
                    if generation == self.paletteGeneration { self.analyzer.lut = lut }
                }
            }
        }
    }

    func setTorch(_ on: Bool) {
        queue.async {
            guard let device = self.device, device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        }
    }

    /// Applies a white calibration and freezes exposure and white balance so it stays valid.
    /// Pass nil to go back to automatic.
    func setCalibration(_ calibration: Calibration?) {
        queue.async {
            self.analyzer.calibration = calibration ?? .identity
            guard let device = self.device, (try? device.lockForConfiguration()) != nil else { return }
            let locked = calibration != nil
            let whiteBalance: AVCaptureDevice.WhiteBalanceMode = locked ? .locked : .continuousAutoWhiteBalance
            let exposure: AVCaptureDevice.ExposureMode = locked ? .locked : .continuousAutoExposure
            if device.isWhiteBalanceModeSupported(whiteBalance) { device.whiteBalanceMode = whiteBalance }
            if device.isExposureModeSupported(exposure) { device.exposureMode = exposure }
            device.unlockForConfiguration()
        }
    }

    private func configure() -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return false }

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)

        session.beginConfiguration()
        session.sessionPreset = .hd1280x720
        // Keep frames in sRGB, which is what the palette is defined in.
        session.automaticallyConfiguresCaptureDeviceForWideColor = false
        session.addInput(input)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return false
        }
        session.addOutput(output)
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        session.commitConfiguration()

        self.device = device
        session.startRunning()
        return true
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameCount += 1
        guard frameCount % 2 == 0, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        process(Frame(
            base: UnsafePointer(base.assumingMemoryBound(to: UInt8.self)),
            width: CVPixelBufferGetWidth(buffer),
            height: CVPixelBufferGetHeight(buffer),
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer)
        ))
    }

    private func process(_ frame: Frame) {
        let output = analyzer.analyze(frame)
        DispatchQueue.main.async { self.onOutput?(output) }
    }

    #if targetEnvironment(simulator)
    private var simulationTimer: DispatchSourceTimer?

    /// The simulator has no camera; feed the analyzer a fixed test scene instead.
    private func startSimulatedFrames() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            SimulatedScene.pixels.withUnsafeBufferPointer { pixels in
                self?.process(Frame(
                    base: pixels.baseAddress!,
                    width: SimulatedScene.width,
                    height: SimulatedScene.height,
                    bytesPerRow: SimulatedScene.width * 4
                ))
            }
        }
        timer.resume()
        simulationTimer = timer
    }
    #endif
}

#if targetEnvironment(simulator)
/// A grid of palette swatches standing in for the camera image.
enum SimulatedScene {
    static let width = 360
    static let height = 640

    private static let swatches = [
        "White", "Dark Red", "Blue",
        "Yellow", "Red", "Green",
        "Orange", "Red", "Reddish Brown",
        "Black", "Light Bluish Gray", "Dark Bluish Gray",
        "Lime", "Tan", "Dark Pink",
    ].map { LegoColor.named($0)!.rgb }

    static let pixels: [UInt8] = {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let color = swatches[(y * 5 / height) * 3 + x * 3 / width]
                let i = (y * width + x) * 4
                pixels[i] = color.b
                pixels[i + 1] = color.g
                pixels[i + 2] = color.r
            }
        }
        return pixels
    }()

    static let image: CGImage = {
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }()
}
#endif
