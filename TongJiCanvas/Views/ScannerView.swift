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

            topLabels
            bottomControls
            closeButton
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
        // Auto-trigger sign-in flow when a valid URL is detected; invalid QRs
        // still surface the retry card so the user knows why nothing happened.
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
                        Text("识别成功")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.orange)
                        Text("未识别到签到链接")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
            } else {
                VStack(spacing: 6) {
                    Text("对准签到二维码")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("自动支持小尺寸、倾斜二维码")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .padding(.top, 80)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: vm.isPaused)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: vm.detectedURL != nil)
    }

    // MARK: - Bottom controls

    private var bottomControls: some View {
        VStack(spacing: 12) {
            // URL / raw text preview chip
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

    // MARK: - Detected card (only invalid QR; valid URLs auto-trigger)

    @ViewBuilder
    private var detectedCard: some View {
        if vm.detectedURL != nil {
            // ── 有效签到链接 — 已自动触发,只显示过渡反馈 ────────────
            VStack(spacing: 12) {
                ProgressView()
                Text("正在跳转签到…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24))
        } else {
            // ── 非签到 QR 码 ──────────────────────────────────
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("非签到二维码，请重试").font(.subheadline.weight(.semibold))
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
                    Label("重新扫描", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24))
        }
    }

    // MARK: - Scanning card

    private var scanningCard: some View {
        VStack(spacing: 12) {
            Text("将二维码置于取景框中").font(.body)
            Button {
                vm.toggleTorch()
            } label: {
                Label(
                    vm.torchOn ? "关闭手电" : "开启手电",
                    systemImage: vm.torchOn ? "flashlight.off.fill" : "flashlight.on.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    // MARK: - Close

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
    // nonisolated(unsafe): AVCaptureSession must be called on a background queue
    nonisolated(unsafe) let captureSession = AVCaptureSession()

    @Published var isPaused    = false
    @Published var torchOn     = false
    @Published var lastResult: String? = nil
    @Published var detectedURL: URL?   = nil

    private let queue = DispatchQueue(label: "scanner.queue")

    func start() {
        queue.async { [captureSession] in
            captureSession.beginConfiguration()

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
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
            captureSession.startRunning()
        }
    }

    func stop() {
        queue.async { [captureSession] in captureSession.stopRunning() }
        setTorch(false)
    }

    func toggleTorch() {
        torchOn.toggle()
        setTorch(torchOn)
    }

    func resume() {
        isPaused    = false
        lastResult  = nil
        detectedURL = nil
    }

    private func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    // AVCaptureMetadataOutputObjectsDelegate
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

            // 触觉反馈
            let isValidURL = URL(string: raw)?.scheme?.hasPrefix("http") == true
            let generator  = UINotificationFeedbackGenerator()
            generator.notificationOccurred(isValidURL ? .success : .warning)

            if isValidURL {
                self.detectedURL = URL(string: raw)
            }
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
                // Cut out
                ctx.blendMode = .destinationOut
                ctx.fill(Path(roundedRect: frame, cornerRadius: 28), with: .color(.white))
                ctx.blendMode = .normal

                // Frame border — green on success
                let borderColor: Color = isSuccess ? .green.opacity(0.9) : .white.opacity(0.5)
                ctx.stroke(
                    Path(roundedRect: frame, cornerRadius: 28),
                    with: .color(borderColor),
                    lineWidth: isSuccess ? 4 : 3
                )

                // Scan line (hidden when paused)
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
