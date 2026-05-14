import SwiftUI
@preconcurrency import AVFoundation

// MARK: - ScannerView

struct ScannerView: View {
    var onDetected: (URL) -> Void
    @Environment(\.dismiss) var dismiss
    @StateObject private var vm = ScannerViewModel()

    var body: some View {
        ZStack {
            // 1. Camera preview (full-screen, behind everything)
            CameraPreview(session: vm.captureSession)
                .ignoresSafeArea()

            // 2. Dimmed overlay with cut-out viewfinder + animated scanning line
            ScannerOverlay(
                isPaused: vm.isPaused,
                state: overlayState
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // 3. State-driven hero (centred over the viewfinder when paused)
            heroOverlay
                .allowsHitTesting(false)

            // 4. Foreground chrome
            VStack {
                topBar
                Spacer()
                zoomPill
                Spacer().frame(height: 12)
                bottomCard
            }
            .padding(.horizontal, 20)
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .onTapGesture(count: 2) { vm.toggleZoom() }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
        .onChange(of: vm.detectedURL) { _, url in
            if let url { onDetected(url) }
        }
    }

    private var overlayState: ScannerOverlay.State {
        if vm.detectedURL != nil { return .success }
        if vm.isPaused           { return .invalid }
        return .scanning
    }

    // MARK: - Top bar (close + status)

    private var topBar: some View {
        HStack {
            // Close button
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
            }
            .buttonStyle(PressableButtonStyle())

            Spacer()

            // Status chip
            statusChip
                .id(overlayState)
                .transition(.scale.combined(with: .opacity))
        }
        .padding(.top, 12)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: overlayState)
    }

    @ViewBuilder
    private var statusChip: some View {
        switch overlayState {
        case .scanning:
            chip(icon: "qrcode.viewfinder", label: "Scanning…", tint: Palette.accentMuted)
        case .success:
            chip(icon: "checkmark", label: "Acquired", tint: .green)
        case .invalid:
            chip(icon: "exclamationmark.triangle.fill", label: "Invalid Target", tint: .orange)
        }
    }

    private func chip(icon: String, label: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
            Text(label)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.4), lineWidth: 0.5))
    }

    // MARK: - Centre hero (success checkmark / warning glyph)

    @ViewBuilder
    private var heroOverlay: some View {
        ZStack {
            if vm.isPaused {
                if vm.detectedURL != nil {
                    successGlyph
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                } else {
                    invalidGlyph
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .offset(y: -50)        // sit just above viewfinder centre
        .animation(.spring(response: 0.45, dampingFraction: 0.65), value: overlayState)
    }

    private var successGlyph: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Color.green, Color(hex: 0x10B981)],
                                     startPoint: .topLeading,
                                     endPoint: .bottomTrailing))
                .frame(width: 90, height: 90)
                .shadow(color: .green.opacity(0.5), radius: 16, y: 6)
            Image(systemName: "checkmark")
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var invalidGlyph: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [.orange, Color(hex: 0xF59E0B)],
                                     startPoint: .topLeading,
                                     endPoint: .bottomTrailing))
                .frame(width: 90, height: 90)
                .shadow(color: .orange.opacity(0.5), radius: 16, y: 6)
            Image(systemName: "exclamationmark")
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Zoom pill (small indicator beneath viewfinder)

    @ViewBuilder
    private var zoomPill: some View {
        if vm.isZoomed {
            HStack(spacing: 6) {
                Image(systemName: "plus.magnifyingglass")
                    .font(.caption.weight(.bold))
                Text(String(format: "%.1f×", vm.zoomFactor))
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
            .transition(.scale.combined(with: .opacity))
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: vm.isZoomed)
        }
    }

    // MARK: - Bottom card (controls / detected)

    @ViewBuilder
    private var bottomCard: some View {
        Group {
            if vm.isPaused {
                if vm.detectedURL != nil {
                    successCard
                } else {
                    invalidCard
                }
            } else {
                scanningCard
            }
        }
        .padding(.bottom, 32)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: vm.isPaused)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: vm.detectedURL != nil)
    }

    private var scanningCard: some View {
        VStack(spacing: 14) {
            // Hint line
            HStack(spacing: 8) {
                Circle()
                    .fill(Palette.accent)
                    .frame(width: 8, height: 8)
                    .scaleEffect(scanPulse)
                    .opacity(2 - scanPulse)
                    .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true),
                               value: scanPulse)
                    .onAppear { scanPulse = 1.6 }
                Text("Hold QR code inside the frame")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
            }

            HStack(spacing: 10) {
                glassButton(
                    icon: vm.torchOn ? "flashlight.on.fill" : "flashlight.off.fill",
                    label: vm.torchOn ? "Torch On" : "Torch",
                    isActive: vm.torchOn,
                    action: vm.toggleTorch
                )

                glassButton(
                    icon: "plus.magnifyingglass",
                    label: vm.isZoomed ? String(format: "%.1f×", vm.zoomFactor) : "Zoom 2×",
                    isActive: vm.isZoomed,
                    action: vm.toggleZoom
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
    }

    private var successCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ProgressView()
                    .tint(.green)
                Text("Proceeding to fan-out…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            if let url = vm.detectedURL {
                Text(url.absoluteString)
                    .font(.caption.weight(.regular))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(Color.green.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .green.opacity(0.25), radius: 14, y: 6)
    }

    private var invalidCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Not a Canvas attendance link")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            if let raw = vm.lastResult {
                Text(raw)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
            Button {
                vm.resume()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Scan again")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Palette.accentGradient, in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: Palette.accent.opacity(0.4), radius: 8, y: 4)
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(.orange.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
    }

    // MARK: - Glass control button

    private func glassButton(
        icon: String,
        label: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.bold))
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(isActive ? .white : .white.opacity(0.9))
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                isActive
                ? AnyShapeStyle(Palette.accentGradient)
                : AnyShapeStyle(Color.white.opacity(0.12))
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.white.opacity(isActive ? 0 : 0.18), lineWidth: 0.5)
            )
            .shadow(color: isActive ? Palette.accent.opacity(0.35) : .clear,
                    radius: isActive ? 8 : 0, y: 4)
        }
        .buttonStyle(PressableButtonStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isActive)
    }

    // MARK: - Local animation state

    @State private var scanPulse: CGFloat = 0.6
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
    enum State { case scanning, success, invalid }

    let isPaused: Bool
    let state: State

    /// Reference time for the scanning animation cycle.
    @SwiftUI.State private var startTime = Date()

    var body: some View {
        TimelineView(.animation(paused: isPaused)) { timeline in
            Canvas { ctx, size in
                let frame = scanFrame(in: size)

                // Dim outside the viewfinder cutout
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.55)))
                ctx.blendMode = .destinationOut
                ctx.fill(Path(roundedRect: frame, cornerRadius: 28), with: .color(.white))
                ctx.blendMode = .normal

                // Corner accents — colour reflects state
                let accent = stateColor
                drawCorners(&ctx, frame: frame, color: accent, length: 32, width: 5)

                // Scanning line — only while actively scanning
                if !isPaused {
                    let elapsed = timeline.date.timeIntervalSince(startTime)
                    let cycle = elapsed.truncatingRemainder(dividingBy: 2.4) / 2.4
                    let progress = cycle < 0.5 ? cycle * 2 : 2 - cycle * 2
                    let inset: CGFloat = 24
                    let lineY = frame.minY + inset + (frame.height - 2 * inset) * CGFloat(progress)

                    // Soft glow band
                    let bandRect = CGRect(x: frame.minX + 12, y: lineY - 18,
                                          width: frame.width - 24, height: 36)
                    ctx.fill(Path(roundedRect: bandRect, cornerRadius: 12),
                             with: .color(accent.opacity(0.18)))

                    // Crisp scan line
                    var line = Path()
                    line.move(to: CGPoint(x: frame.minX + 16, y: lineY))
                    line.addLine(to: CGPoint(x: frame.maxX - 16, y: lineY))
                    ctx.stroke(line, with: .color(accent.opacity(0.95)), lineWidth: 2.5)
                }
            }
            .compositingGroup()
        }
        .onAppear { startTime = Date() }
        .onChange(of: isPaused) { _, paused in if !paused { startTime = Date() } }
    }

    private var stateColor: Color {
        switch state {
        case .scanning: return .white
        case .success:  return .green
        case .invalid:  return .orange
        }
    }

    private func scanFrame(in size: CGSize) -> CGRect {
        let side = min(size.width, size.height) * 0.68
        return CGRect(
            x: (size.width  - side) / 2,
            y: (size.height - side) / 2.2,
            width: side, height: side
        )
    }

    private func drawCorners(_ ctx: inout GraphicsContext, frame: CGRect,
                             color: Color, length: CGFloat, width: CGFloat) {
        let radius: CGFloat = 28
        let shading = GraphicsContext.Shading.color(color)

        // Top-left
        var p = Path()
        p.move(to: CGPoint(x: frame.minX, y: frame.minY + length))
        p.addLine(to: CGPoint(x: frame.minX, y: frame.minY + radius))
        p.addQuadCurve(to: CGPoint(x: frame.minX + radius, y: frame.minY),
                       control: CGPoint(x: frame.minX, y: frame.minY))
        p.addLine(to: CGPoint(x: frame.minX + length, y: frame.minY))
        ctx.stroke(p, with: shading, style: StrokeStyle(lineWidth: width, lineCap: .round))

        // Top-right
        p = Path()
        p.move(to: CGPoint(x: frame.maxX - length, y: frame.minY))
        p.addLine(to: CGPoint(x: frame.maxX - radius, y: frame.minY))
        p.addQuadCurve(to: CGPoint(x: frame.maxX, y: frame.minY + radius),
                       control: CGPoint(x: frame.maxX, y: frame.minY))
        p.addLine(to: CGPoint(x: frame.maxX, y: frame.minY + length))
        ctx.stroke(p, with: shading, style: StrokeStyle(lineWidth: width, lineCap: .round))

        // Bottom-left
        p = Path()
        p.move(to: CGPoint(x: frame.minX, y: frame.maxY - length))
        p.addLine(to: CGPoint(x: frame.minX, y: frame.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: frame.minX + radius, y: frame.maxY),
                       control: CGPoint(x: frame.minX, y: frame.maxY))
        p.addLine(to: CGPoint(x: frame.minX + length, y: frame.maxY))
        ctx.stroke(p, with: shading, style: StrokeStyle(lineWidth: width, lineCap: .round))

        // Bottom-right
        p = Path()
        p.move(to: CGPoint(x: frame.maxX - length, y: frame.maxY))
        p.addLine(to: CGPoint(x: frame.maxX - radius, y: frame.maxY))
        p.addQuadCurve(to: CGPoint(x: frame.maxX, y: frame.maxY - radius),
                       control: CGPoint(x: frame.maxX, y: frame.maxY))
        p.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY - length))
        ctx.stroke(p, with: shading, style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}
