import AVFoundation
import CoreMedia

// Zoom APIs (videoZoomFactor, ramp, min/maxAvailableVideoZoomFactor) are iOS-only.
// The "Designed for iPad" Mac destination still compiles this file under the macOS SDK,
// so the #else block below provides no-op stubs that satisfy the compiler there.

#if os(iOS)

// MARK: - Static close-range zoom
// Ported from twostraws/CodeScanner (MIT License, © 2021 Paul Hudson)
// https://github.com/twostraws/CodeScanner
// Technique: Apple WWDC 2021 session 10047 "What's new in camera capture" / AVCamBarcode sample.
//
// Problem: iPhone 14 Pro+ raised minimum focus distance 150 mm → 200 mm.
// Without compensation a QR code held at arm's length can't be focused and never decodes.
// Fix: raise videoZoomFactor so the minimum legible subject distance ≥ device minimum.

extension AVCaptureDevice {

    /// Adjusts `videoZoomFactor` so a QR code of `minimumCodeSize` millimetres can be
    /// reliably focused at the device's minimum focus distance.  No-op on iOS < 15 or
    /// when the device does not need compensation.
    func setRecommendedZoomFactor(forMinimumCodeSize minimumCodeSize: Float = 20) {
        guard #available(iOS 15, *) else { return }
        let minFocusMM = Float(minimumFocusDistance)
        guard minFocusMM != -1 else { return }

        let fov: Float              = activeFormat.videoFieldOfView
        let dims: CMVideoDimensions = CMVideoFormatDescriptionGetDimensions(activeFormat.formatDescription)
        let fillRatio: Float        = Float(dims.height) / Float(dims.width)

        let halfRad: Float      = (fov / 2) * .pi / 180
        let minSubjectMM: Float = (minimumCodeSize / fillRatio) / tan(halfRad)
        guard minSubjectMM < minFocusMM else { return }

        let recommended = CGFloat(minFocusMM / minSubjectMM)
            .zoomClamped(lo: minAvailableVideoZoomFactor, hi: maxAvailableVideoZoomFactor)
        do {
            try lockForConfiguration()
            videoZoomFactor = recommended
            unlockForConfiguration()
        } catch { }
    }
}

// MARK: - Dynamic QR-bounds-driven zoom

extension AVCaptureDevice {

    /// Returns the zoom factor needed to bring a small QR code to ~30 % of the larger
    /// frame dimension, or `nil` if no adjustment is needed.
    ///
    /// Pass `max(bounds.width, bounds.height)` from `AVMetadataMachineReadableCodeObject`
    /// rather than either dimension alone.  iPhone sensors capture in landscape regardless
    /// of phone orientation; a square QR code's width and height in normalised capture
    /// coordinates therefore differ by the sensor aspect ratio (~1920/1080 ≈ 1.78×).
    /// Using the larger dimension gives the correct linear size of the code.
    ///
    /// Threshold is 0.35 (fires when QR < 35 % of the larger frame dimension) so the
    /// function is inactive when the code is already comfortably readable.
    ///
    /// - Parameter normalizedSize: `max(bounds.width, bounds.height)` of the detected
    ///   code object, in capture-device normalised coordinates (0 … 1).
    func targetZoom(forQRSize normalizedSize: CGFloat) -> CGFloat? {
        guard normalizedSize > 0.01, normalizedSize < 0.35 else { return nil }
        let target:  CGFloat = 0.40           // aim for 40 % of larger frame dimension
        let current: CGFloat = videoZoomFactor
        let factor           = (current * (target / normalizedSize))
            .zoomClamped(lo: 1.0, hi: min(maxAvailableVideoZoomFactor, 6.0))
        guard abs(factor - current) / current > 0.10 else { return nil }   // 10 % dead-band
        return factor
    }

    /// Smoothly ramps to `factor` at `rate` zoom-units per second.
    func rampZoom(toFactor factor: CGFloat, rate: Float = 3.5) {
        let clamped = factor.zoomClamped(lo: minAvailableVideoZoomFactor,
                                         hi: min(maxAvailableVideoZoomFactor, 6.0))
        do {
            try lockForConfiguration()
            ramp(toVideoZoomFactor: clamped, withRate: rate)
            unlockForConfiguration()
        } catch { }
    }

    /// Smoothly returns to `factor` (typically the session-start base zoom).
    func resetZoom(to factor: CGFloat = 1.0, rate: Float = 2.0) {
        let clamped = factor.zoomClamped(lo: minAvailableVideoZoomFactor,
                                         hi: maxAvailableVideoZoomFactor)
        guard abs(videoZoomFactor - clamped) > 0.05 else { return }
        do {
            try lockForConfiguration()
            ramp(toVideoZoomFactor: clamped, withRate: rate)
            unlockForConfiguration()
        } catch { }
    }

    /// Immediately sets `factor` without animation — used for pinch-gesture tracking.
    func setZoomImmediate(_ factor: CGFloat) {
        let clamped = factor.zoomClamped(lo: minAvailableVideoZoomFactor,
                                         hi: min(maxAvailableVideoZoomFactor, 6.0))
        guard abs(videoZoomFactor - clamped) > 0.01 else { return }
        do {
            try lockForConfiguration()
            videoZoomFactor = clamped
            unlockForConfiguration()
        } catch { }
    }
}

// MARK: - Helpers (fileprivate to avoid collision with other CGFloat extensions)

private extension CGFloat {
    func zoomClamped(lo: CGFloat, hi: CGFloat) -> CGFloat {
        Swift.min(Swift.max(self, lo), hi)
    }
}

#else  // macOS — no-op stubs so ScannerViewModel compiles for the "Designed for iPad" destination

extension AVCaptureDevice {
    var maxAvailableVideoZoomFactor: CGFloat { 1.0 }
    func setRecommendedZoomFactor(forMinimumCodeSize minimumCodeSize: Float = 20) {}
    func targetZoom(forQRSize normalizedSize: CGFloat) -> CGFloat? { nil }
    func rampZoom(toFactor factor: CGFloat, rate: Float = 3.5) {}
    func resetZoom(to factor: CGFloat = 1.0, rate: Float = 2.0) {}
    func setZoomImmediate(_ factor: CGFloat) {}
}

#endif  // os(iOS)
