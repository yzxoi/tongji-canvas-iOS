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

// MARK: - Manual zoom helpers

extension AVCaptureDevice {

    /// The maximum zoom factor the scanner should use (device limit or 6.0, whichever is lower).
    var scannerMaxZoom: CGFloat {
        min(maxAvailableVideoZoomFactor, 6.0)
    }

    /// Smoothly ramps to `factor` at `rate` zoom-units per second.
    func rampZoom(toFactor factor: CGFloat, rate: Float = 3.5) {
        let clamped = factor.zoomClamped(lo: minAvailableVideoZoomFactor, hi: scannerMaxZoom)
        guard abs(videoZoomFactor - clamped) > 0.01 else { return }
        do {
            try lockForConfiguration()
            ramp(toVideoZoomFactor: clamped, withRate: rate)
            unlockForConfiguration()
        } catch { }
    }

    /// Immediately sets `factor` without animation.
    func setZoomImmediate(_ factor: CGFloat) {
        let clamped = factor.zoomClamped(lo: minAvailableVideoZoomFactor, hi: scannerMaxZoom)
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
    var scannerMaxZoom: CGFloat { 1.0 }
    func setRecommendedZoomFactor(forMinimumCodeSize minimumCodeSize: Float = 20) {}
    func rampZoom(toFactor factor: CGFloat, rate: Float = 3.5) {}
    func setZoomImmediate(_ factor: CGFloat) {}
}

#endif  // os(iOS)
