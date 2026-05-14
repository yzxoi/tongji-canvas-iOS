import SwiftUI
@preconcurrency import AVFoundation

// MARK: - ScannerView

struct ScannerView: View {
    var onDetected: (URL) -> Void
    @Environment(\.dismiss) var dismiss
    @StateObject private var vm = ScannerViewModel()

    var body: some View {
        ZStack {
            CameraPreview(session: vm.captureSession)
                .ignoresSafeArea()

            ScannerOverlay(isPaused: vm.isPaused, isSuccess: vm.detectedURL != nil)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            topLabels
            bottomControls
            closeButton
        }
        .onTapGesture(count: 2) { vm.toggleZoom() }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
        .onChange(of: vm.detectedURL) { _, url in
            if let url { onDetected(url) }
        }
    }

    // MARK: - Top feedback

    private var topLabels: some View {
        Group {
            if vm.isPaused {
                if vm.detectedURL != nil {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.green)
                        Text("Target Acquired")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.orange)
                        Text("Invalid Target")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
            } else {
                VStack(spacing: 6) {
                    Text("Point at QR code")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Double-tap to toggle 2× zoom")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                    if vm.isZoomed {
                        Text(String(format: "%.1f×", vm.zoomFactor))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(.black.opacity(0.55), in: Capsule())
                            .foregroundStyle(.white)
                            .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    }
                }
            }
        }
        .padding(.top, 80)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: vm.isPaused)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: vm.detectedURL != nil)
        .animation(.easeInOut(duration: 0.2), value: vm.isZoomed)
    }

    // MARK: - Bottom controls

    private var bottomControls: some View {
        VStack(spacing: 12) {
            if let last = vm.lastResult {
                Label(last, systemImage: "qrcode.viewfinder")
                    .lineLimit(1)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.regularMaterial)
                    .clipShape(Capsule())
            }

            if vm.isPaused {
                detectedCard
            } else {
                scanningCard
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: vm.isPaused)
    }

    @ViewBuilder
    private var detectedCard: some View {
        if vm.detectedURL != nil {
            VStack(spacing: 12) {
                ProgressView()
                Text("Proceeding to fan-out...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24))
        } else {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("Not a valid target URL").font(.subheadline.weight(.semibold))
                    Spacer()
                }

                if let raw = vm.lastResult {
                    Text(raw)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Button {
                    vm.resume()
                } label: {
                    Label("Scan Again", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24))
        }
    }

    private var scanningCard: some View {
        VStack(spacing: 12) {
            Text("Place QR code in viewfinder").font(.body)
            HStack(spacing: 10) {
                Button {
                    vm.toggleTorch()
                } label: {
                    Label(
                        vm.torchOn ? "Torch Off" : "Torch On",
                        systemImage: vm.torchOn ? "flashlight.off.fill" : "flashlight.on.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    vm.toggleZoom()
                } label: {
                    Label(
                        vm.isZoomed ? String(format: "%.0f×", vm.zoomFactor) : "2×",
                        systemImage: vm.isZoomed ? "1.magnifyingglass" : "magnifyingglass"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(vm.isZoomed ? Color(hex: 0x7C3AED) : nil)
            }
        }
        .padding(20)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.8))
                .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, 48)
    }
}

// MARK: - ViewModel

@MainActor
final class ScannerViewModel: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    nonisolated(unsafe) let captureSession = AVCaptureSession()
    nonisolated(unsafe) var captureDevice: AVCaptureDevice?

    @Published var isPaused    = false
    @Published var torchOn     = false
    @Published var lastResult: String? = nil
    @Published var detectedURL: URL?   = nil
    @Published var zoomFactor: CGFloat = 1.0

    /// True when zoom is meaningfully above 1.0.
    var isZoomed: Bool { zoomFactor > 1.15 }

    private let queue = DispatchQueue(label: "scanner.queue")

    // MARK: Session lifecycle

    func start() {
        queue.async { [captureSession, weak self] in
            captureSession.beginConfiguration()

            let preferredType: AVCaptureDevice.DeviceType =
                AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) != nil
                ? .builtInDualCamera
                : .builtInWideAngleCamera

            guard let device = AVCaptureDevice.default(preferredType, for: .video, position: .back),
                  let input  = try? AVCaptureDeviceInput(device: device),
                  captureSession.canAddInput(input)
            else { captureSession.commitConfiguration(); return }

            captureSession.addInput(input)

            let output = AVCaptureMetadataOutput()
            if captureSession.canAddOutput(output) {
                captureSession.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                output.metadataObjectTypes = [.qr, .dataMatrix, .aztec]
            }

            captureSession.commitConfiguration()

            self?.captureDevice = device
            captureSession.startRunning()

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.zoomFactor = device.videoZoomFactor
            }
        }
    }

    func stop() {
        captureDevice?.setZoomImmediate(1.0)
        zoomFactor = 1.0
        queue.async { [captureSession] in captureSession.stopRunning() }
        setTorch(false)
    }

    // MARK: Controls

    func toggleTorch() {
        torchOn.toggle()
        setTorch(torchOn)
    }

    /// Toggle between 1× and 2× zoom.  On dual-camera devices this may switch
    /// from the wide lens to the telephoto lens around the device's switch-over factor.
    func toggleZoom() {
        guard let device = captureDevice else { return }
        let target: CGFloat = zoomFactor > 1.15 ? 1.0 : 2.0
        device.rampZoom(toFactor: target, rate: 8)
        withAnimation(.easeOut(duration: 0.25)) { zoomFactor = target }
    }

    func resume() {
        isPaused    = false
        lastResult  = nil
        detectedURL = nil
        // Reset zoom when re-scanning
        captureDevice?.rampZoom(toFactor: 1.0, rate: 8)
        withAnimation(.easeOut(duration: 0.25)) { zoomFactor = 1.0 }
    }

    private func setTorch(_ on: Bool) {
        let device = captureDevice ?? AVCaptureDevice.default(for: .video)
        guard let device, device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    // MARK: AVCaptureMetadataOutputObjectsDelegate

    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput,
                                     didOutput objects: [AVMetadataObject],
                                     from connection: AVCaptureConnection) {
        guard let obj = objects.first as? AVMetadataMachineReadableCodeObject,
              let raw = obj.stringValue, !raw.isEmpty
        else { return }

        Task { @MainActor [weak self] in
            guard let self, !self.isPaused else { return }

            self.lastResult = raw
            self.isPaused   = true

            let isValidURL = URL(string: raw)?.scheme?.hasPrefix("http") == true
            UINotificationFeedbackGenerator().notificationOccurred(isValidURL ? .success : .warning)
            if isValidURL { self.detectedURL = URL(string: raw) }
        }
    }
}

// MARK: - Camera Preview

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.videoPreviewLayer.session = session
        v.videoPreviewLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

// MARK: - Scanner Overlay

struct ScannerOverlay: View {
    let isPaused: Bool
    let isSuccess: Bool

    /// Reference time for the scanning animation cycle.
    @State private var startTime = Date()

    var body: some View {
        TimelineView(.animation(paused: isPaused)) { timeline in
            Canvas { ctx, size in
                let frame = scanFrame(in: size)

                // Semi-transparent mask with cutout
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.5)))
                ctx.blendMode = .destinationOut
                ctx.fill(Path(roundedRect: frame, cornerRadius: 24), with: .color(.white))
                ctx.blendMode = .normal

                // Corner accents
                let accentColor: Color = isSuccess ? .green : Color(hex: 0xB8A2FF)
                drawCorners(&ctx, frame: frame, color: accentColor, length: 28, width: 4)

                // Scanning line — position driven by elapsed time, not @State animation
                if !isPaused {
                    let elapsed = timeline.date.timeIntervalSince(startTime)
                    // Triangle wave: period 2.4 s, range 0…1
                    let cycle = elapsed.truncatingRemainder(dividingBy: 2.4) / 2.4
                    let progress = cycle < 0.5 ? cycle * 2 : 2 - cycle * 2

                    let inset: CGFloat = 20
                    let lineY = frame.minY + inset + (frame.height - 2 * inset) * CGFloat(progress)
                    var line = Path()
                    line.move(to: CGPoint(x: frame.minX + 12, y: lineY))
                    line.addLine(to: CGPoint(x: frame.maxX - 12, y: lineY))
                    ctx.stroke(line, with: .color(accentColor.opacity(0.8)), lineWidth: 2.5)

                    // Soft glow
                    let glowRect = CGRect(x: frame.minX + 12, y: lineY - 8,
                                          width: frame.width - 24, height: 16)
                    ctx.fill(Path(roundedRect: glowRect, cornerRadius: 8),
                             with: .color(accentColor.opacity(0.15)))
                }
            }
            .compositingGroup()
        }
        .onAppear { startTime = Date() }
        .onChange(of: isPaused) { _, paused in if !paused { startTime = Date() } }
    }

    private func scanFrame(in size: CGSize) -> CGRect {
        let side = min(size.width, size.height) * 0.65
        return CGRect(
            x: (size.width  - side) / 2,
            y: (size.height - side) / 2.2,
            width: side, height: side
        )
    }

    private func drawCorners(_ ctx: inout GraphicsContext, frame: CGRect,
                             color: Color, length: CGFloat, width: CGFloat) {
        // Top-left
        var p = Path()
        p.move(to: CGPoint(x: frame.minX, y: frame.minY + length))
        p.addLine(to: CGPoint(x: frame.minX, y: frame.minY))
        p.addLine(to: CGPoint(x: frame.minX + length, y: frame.minY))
        ctx.stroke(p, with: .color(color), lineWidth: width)

        // Top-right
        p = Path()
        p.move(to: CGPoint(x: frame.maxX - length, y: frame.minY))
        p.addLine(to: CGPoint(x: frame.maxX, y: frame.minY))
        p.addLine(to: CGPoint(x: frame.maxX, y: frame.minY + length))
        ctx.stroke(p, with: .color(color), lineWidth: width)

        // Bottom-left
        p = Path()
        p.move(to: CGPoint(x: frame.minX, y: frame.maxY - length))
        p.addLine(to: CGPoint(x: frame.minX, y: frame.maxY))
        p.addLine(to: CGPoint(x: frame.minX + length, y: frame.maxY))
        ctx.stroke(p, with: .color(color), lineWidth: width)

        // Bottom-right
        p = Path()
        p.move(to: CGPoint(x: frame.maxX - length, y: frame.maxY))
        p.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY))
        p.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY - length))
        ctx.stroke(p, with: .color(color), lineWidth: width)
    }
}
