import SwiftUI
@preconcurrency import AVFoundation

// MARK: - ScannerView

struct ScannerView: View {
    var onDetected: (URL) -> Void
    @Environment(\.dismiss) var dismiss
    @StateObject private var vm = ScannerViewModel()

    /// Zoom level captured at the moment a pinch gesture begins.
    @State private var pinchBaseZoom: CGFloat = 1.0
    /// True while a pinch gesture is active — prevents auto-zoom from overwriting the base.
    @State private var isPinching = false

    var body: some View {
        ZStack {
            CameraPreview(session: vm.captureSession)
                .ignoresSafeArea()
                .gesture(
                    MagnificationGesture()
                        .onChanged { scale in
                            isPinching = true
                            vm.setZoom(pinchBaseZoom * scale)
                        }
                        .onEnded { _ in
                            pinchBaseZoom = vm.zoomFactor
                            isPinching    = false
                        }
                )

            ScannerOverlay(isPaused: vm.isPaused, isSuccess: vm.detectedURL != nil)
                .ignoresSafeArea()

            topLabels
            bottomControls
            closeButton
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
        .onChange(of: vm.detectedURL) { _, url in
            if let url { onDetected(url) }
        }
        // Keep pinchBaseZoom in sync with auto-zoom (only when not actively pinching)
        .onChange(of: vm.zoomFactor) { _, newZoom in
            if !isPinching { pinchBaseZoom = newZoom }
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
                    Text("Supports small or skewed codes")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                    // Zoom level badge — appears when auto-zoom or pinch is active
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
                    pinchBaseZoom = 1.0
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

                // Reset-zoom button — visible whenever zoom is elevated above baseline
                if vm.isZoomed {
                    Button {
                        vm.resetZoomManual()
                        pinchBaseZoom = 1.0
                    } label: {
                        Label(String(format: "%.1f×", vm.zoomFactor),
                              systemImage: "arrow.down.right.and.arrow.up.left")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: vm.isZoomed)
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
    /// Retained to drive zoom after session start; nonisolated(unsafe) follows the same
    /// pattern as captureSession — all AVFoundation calls are serialised via lockForConfiguration.
    nonisolated(unsafe) var captureDevice: AVCaptureDevice?

    @Published var isPaused    = false
    @Published var torchOn     = false
    @Published var lastResult: String? = nil
    @Published var detectedURL: URL?   = nil
    /// Current zoom factor — updated when auto-zoom or pinch fires.
    @Published var zoomFactor: CGFloat = 1.0

    /// True when zoom is meaningfully above the session-start baseline.
    var isZoomed: Bool { zoomFactor > baseZoomFactor + 0.15 }

    private let queue = DispatchQueue(label: "scanner.queue")
    /// Zoom set once at session start by setRecommendedZoomFactor — the floor for resets.
    private var baseZoomFactor: CGFloat = 1.0
    /// Cancellable task that resets zoom after 3 s of silence.
    private var resetZoomTask: Task<Void, Never>?

    // MARK: Session lifecycle

    func start() {
        queue.async { [captureSession, weak self] in
            captureSession.beginConfiguration()

            // Prefer builtInDualCamera (iPhone 11+): supports optical zoom via
            // virtualDeviceSwitchOverVideoZoomFactors — the system switches
            // transparently between wide and telephoto lenses as videoZoomFactor rises.
            let preferredType: AVCaptureDevice.DeviceType =
                AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) != nil
                ? .builtInDualCamera
                : .builtInWideAngleCamera

            guard let device = AVCaptureDevice.default(preferredType, for: .video, position: .back),
                  let input  = try? AVCaptureDeviceInput(device: device),
                  captureSession.canAddInput(input)
            else { captureSession.commitConfiguration(); return }

            captureSession.addInput(input)

            // Static zoom — Apple AVCamBarcode technique (ported from CodeScanner, MIT).
            // Compensates for the increased minimum focus distance on iPhone 14 Pro+.
            device.setRecommendedZoomFactor(forMinimumCodeSize: 20)
            let initialZoom = device.videoZoomFactor

            let output = AVCaptureMetadataOutput()
            if captureSession.canAddOutput(output) {
                captureSession.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                output.metadataObjectTypes = [.qr, .dataMatrix, .aztec]
            }

            captureSession.commitConfiguration()

            // FIX: assign captureDevice *before* startRunning() to eliminate the race
            // condition where the first QR detection fires before the @MainActor Task
            // below has had a chance to run.  nonisolated(unsafe) permits this write
            // from a non-actor context.
            self?.captureDevice = device

            captureSession.startRunning()

            // @Published properties must be updated on the main actor.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.baseZoomFactor = initialZoom
                self.zoomFactor     = initialZoom
            }
        }
    }

    func stop() {
        resetZoomTask?.cancel()
        captureDevice?.resetZoom(to: baseZoomFactor, rate: 4.0)
        queue.async { [captureSession] in captureSession.stopRunning() }
        setTorch(false)
    }

    // MARK: Controls

    func toggleTorch() {
        torchOn.toggle()
        setTorch(torchOn)
    }

    func resume() {
        isPaused    = false
        lastResult  = nil
        detectedURL = nil
        resetZoomTask?.cancel()
        // Brief delay so the overlay transition completes before zoom resets
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            self.captureDevice?.resetZoom(to: self.baseZoomFactor)
            withAnimation(.easeOut(duration: 0.4)) { self.zoomFactor = self.baseZoomFactor }
        }
    }

    /// Called by the pinch gesture — sets zoom immediately without animation.
    func setZoom(_ factor: CGFloat) {
        guard let device = captureDevice else { return }
        // maxAvailableVideoZoomFactor is iOS-only; the macOS stub returns 1.0 (no-op).
        let maxZoom = Swift.min(device.maxAvailableVideoZoomFactor, 6.0)
        let clamped = Swift.min(Swift.max(factor, 1.0), maxZoom)
        device.setZoomImmediate(clamped)
        zoomFactor = clamped
        scheduleZoomReset()
    }

    /// Smoothly returns to the session-start base zoom; called by the reset button.
    func resetZoomManual() {
        resetZoomTask?.cancel()
        captureDevice?.resetZoom(to: baseZoomFactor)
        withAnimation(.easeOut(duration: 0.35)) { zoomFactor = baseZoomFactor }
    }

    // MARK: Private

    private func scheduleZoomReset() {
        resetZoomTask?.cancel()
        resetZoomTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self.captureDevice?.resetZoom(to: self.baseZoomFactor)
            withAnimation(.easeOut(duration: 0.5)) { self.zoomFactor = self.baseZoomFactor }
        }
    }

    private func setTorch(_ on: Bool) {
        // Use captureDevice (may be a virtual dual-camera) rather than the default device
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

        // Dynamic zoom: fires before the result is processed so the next frame
        // arrives at a more legible size if the QR was small.
        // Runs on DispatchQueue.main (delegate queue set above) — lockForConfiguration
        // is fast enough not to cause perceptible jank.
        //
        // FIX: iPhone sensors capture in landscape orientation regardless of how the
        // phone is held.  For a square QR code in portrait, bounds.width (horizontal
        // in sensor space) ≈ qr_pixels / frame_width (e.g. 200/1920 ≈ 0.10) while
        // bounds.height ≈ qr_pixels / frame_height (e.g. 200/1080 ≈ 0.19).
        // Using only bounds.width therefore understates the code size by ~44 % and
        // over-triggers zoom.  max(width, height) gives the correct linear extent of
        // the square QR regardless of sensor orientation.
        let qrSize  = max(obj.bounds.width, obj.bounds.height)
        let device  = captureDevice
        var zoomedTo: CGFloat?
        if let device, let target = device.targetZoom(forQRSize: qrSize) {
            device.rampZoom(toFactor: target)
            zoomedTo = target
        }

        Task { @MainActor [weak self] in
            guard let self, !self.isPaused else { return }

            if let z = zoomedTo { self.zoomFactor = z }
            self.scheduleZoomReset()

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

    @State private var lineProgress: CGFloat = 0

    var body: some View {
        TimelineView(.animation(paused: isPaused)) { _ in
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.4)))

                let frame = scanFrame(in: size)
                ctx.blendMode = .destinationOut
                ctx.fill(Path(roundedRect: frame, cornerRadius: 28), with: .color(.white))
                ctx.blendMode = .normal

                let borderColor: Color = isSuccess ? .green.opacity(0.9) : .white.opacity(0.5)
                ctx.stroke(
                    Path(roundedRect: frame, cornerRadius: 28),
                    with: .color(borderColor),
                    lineWidth: isSuccess ? 4 : 3
                )

                if !isPaused {
                    let lineY = frame.minY + frame.height * lineProgress
                    var line = Path()
                    line.move(to: CGPoint(x: frame.minX + 16, y: lineY))
                    line.addLine(to: CGPoint(x: frame.maxX - 16, y: lineY))
                    ctx.stroke(line, with: .color(.blue.opacity(0.9)), lineWidth: 3)
                }
            }
            .compositingGroup()
        }
        .onAppear { animate() }
        .onChange(of: isPaused) { _, paused in if !paused { lineProgress = 0; animate() } }
    }

    private func scanFrame(in size: CGSize) -> CGRect {
        let side = min(size.width, size.height) * 0.65
        return CGRect(
            x: (size.width  - side) / 2,
            y: (size.height - side) / 2.2,
            width: side, height: side
        )
    }

    private func animate() {
        withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
            lineProgress = 1
        }
    }
}
