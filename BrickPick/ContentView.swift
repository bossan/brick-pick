import AVFoundation
import SwiftUI

struct ContentView: View {
    @State private var scanner = Scanner()
    @State private var showingPicker = false
    @State private var showingSets = false
    /// The sample being corrected while the "what is this really" picker is open.
    @State private var correctionSample: RGB?
    @State private var showingCorrection = false
    @State private var showingHelp = false
    @State private var calibrationFailed = false
    @AppStorage("hasSeenHelp") private var hasSeenHelp = false

    var body: some View {
        ZStack {
            viewfinder
            switch scanner.state {
            case .starting:
                ProgressView()
            case .running:
                controls
            case .unavailable:
                ContentUnavailableView(
                    "Camera unavailable",
                    systemImage: "camera.fill",
                    description: Text("Allow camera access for BrickPick in Settings.")
                )
            }
        }
        .task {
            await scanner.start()
            if !hasSeenHelp {
                hasSeenHelp = true
                showingHelp = true
            }
        }
        .sheet(isPresented: $showingPicker) {
            TargetPicker(
                palette: scanner.palette,
                legoSet: scanner.selectedSet
            ) {
                scanner.target = $0
            }
        }
        .sheet(isPresented: $showingCorrection) {
            TargetPicker(
                title: "What colour is this really?",
                palette: scanner.palette,
                legoSet: scanner.selectedSet
            ) { color in
                if let correctionSample {
                    scanner.teach(color, sample: correctionSample)
                }
            }
        }
        .sheet(isPresented: $showingSets) {
            SetPicker(selected: scanner.selectedSet) {
                scanner.selectSet($0)
            }
        }
        .sheet(isPresented: $showingHelp) {
            HelpView(onForget: scanner.hasLearned ? { scanner.forgetLearned() } : nil)
        }
        .alert("Couldn't calibrate", isPresented: $calibrationFailed) {
            Button("OK") {}
        } message: {
            Text("Aim the circle at plain white paper that is lit but not glaring, then try again.")
        }
        .sensoryFeedback(.success, trigger: scanner.verdict == .match) { _, isMatch in isMatch }
    }

    /// Camera image, target mask and reticle. All three are centred on the full screen so they line up.
    private var viewfinder: some View {
        Color.black
            .overlay {
                if scanner.state == .running {
                    #if targetEnvironment(simulator)
                    Image(decorative: SimulatedScene.image, scale: 1)
                        .resizable()
                        .scaledToFill()
                    #else
                    CameraPreview(session: scanner.camera.session)
                    #endif
                }
            }
            .overlay {
                if let mask = scanner.mask {
                    // The mask is coarse; blurring hides its blocky edges.
                    Image(decorative: mask, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 1.5)
                }
            }
            .overlay {
                if scanner.state == .running {
                    Reticle()
                }
            }
            .clipped()
            .ignoresSafeArea()
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack {
                targetChip
                Spacer()
                Button("Help", systemImage: "questionmark") { showingHelp = true }
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            HStack {
                setChip
                Spacer()
            }
            Spacer()
            if scanner.isTooDark && !scanner.torchOn {
                Label("Too dark — turn on the light", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            readout
        }
        .padding()
        .tint(.white)
    }

    private var targetChip: some View {
        HStack(spacing: 4) {
            Button { showingPicker = true } label: {
                HStack(spacing: 10) {
                    if let target = scanner.target {
                        Swatch(color: target)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Looking for").font(.caption).foregroundStyle(.secondary)
                            Text(target.name).font(.headline)
                        }
                    } else {
                        Image(systemName: "scope")
                        Text("No target colour").font(.headline)
                    }
                }
            }
            if scanner.target != nil {
                Button("Clear target", systemImage: "xmark.circle.fill") { scanner.target = nil }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, scanner.target == nil ? 14 : 4)
        .frame(minHeight: 44)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var setChip: some View {
        Button { showingSets = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "shippingbox.fill")
                if let set = scanner.selectedSet {
                    Text("\(set.displayNumber) \(set.name)").lineLimit(1)
                } else {
                    Text("Choose set")
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private var readout: some View {
        VStack(spacing: 14) {
            if let verdict = scanner.verdict, let target = scanner.target {
                VerdictBadge(verdict: verdict, target: target)
            }
            if let reading = scanner.reading {
                VStack(spacing: 2) {
                    Text(reading.best.name)
                        .font(.title.bold())
                    if !reading.alternatives.isEmpty {
                        Text("or " + reading.alternatives.map(\.name).joined(separator: " / "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.center)
                Button("Wrong colour?") {
                    correctionSample = scanner.sample
                    showingCorrection = true
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button {
                    scanner.torchOn.toggle()
                } label: {
                    ControlLabel(
                        title: "Light",
                        systemImage: scanner.torchOn ? "flashlight.on.fill" : "flashlight.off.fill",
                        isOn: scanner.torchOn
                    )
                }
                Button {
                    if scanner.isCalibrated {
                        scanner.resetCalibration()
                    } else if !scanner.calibrate() {
                        calibrationFailed = true
                    }
                } label: {
                    ControlLabel(
                        title: scanner.isCalibrated ? "Calibrated" : "Set white",
                        systemImage: scanner.isCalibrated ? "checkmark.circle.fill" : "circle.lefthalf.filled",
                        isOn: scanner.isCalibrated
                    )
                }
                Button {
                    scanner.setTargetFromReading()
                } label: {
                    ControlLabel(title: "Set target", systemImage: "scope", isOn: false)
                }
                .disabled(scanner.reading == nil)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
    }
}

/// Match state as a symbol and words, never as colour alone.
private struct VerdictBadge: View {
    let verdict: MatchVerdict
    let target: LegoColor

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.title3.bold())
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .foregroundStyle(verdict == .match ? .black : .white)
            .background(verdict == .match ? AnyShapeStyle(.white) : AnyShapeStyle(.clear), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(verdict == .match ? 0 : 0.5)))
    }

    private var title: String {
        switch verdict {
        case .match: "Match"
        case .possible: "Maybe \(target.name)"
        case .noMatch: "Not \(target.name)"
        }
    }

    private var symbol: String {
        switch verdict {
        case .match: "checkmark.circle.fill"
        case .possible: "questionmark.circle.fill"
        case .noMatch: "xmark.circle.fill"
        }
    }
}

private struct ControlLabel: View {
    let title: String
    let systemImage: String
    let isOn: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage).font(.title3)
            Text(title).font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .foregroundStyle(isOn ? .black : .white)
        .background(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.15)), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct Reticle: View {
    var body: some View {
        ZStack {
            Circle().stroke(.black.opacity(0.6), lineWidth: 5)
            Circle().stroke(.white, lineWidth: 2)
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }
}

struct Swatch: View {
    let color: LegoColor

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color(red: Double(color.rgb.r) / 255, green: Double(color.rgb.g) / 255, blue: Double(color.rgb.b) / 255))
            .frame(width: 26, height: 26)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.6)))
            .accessibilityHidden(true)
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        if let connection = view.previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
