import SwiftUI
import AppKit

/// Renders a device photo (cropped to its `focusRect`) and overlays the
/// simulator's most recent rendered PNG inside the screen rectangle.
///
/// Aspect-ratio-preserving by construction: the photo uses `.scaledToFit()`
/// so it never squishes. An `.overlay(GeometryReader)` reads the photo's
/// *actual rendered* size and positions the screen content accordingly,
/// so the overlay tracks the image whether it letterboxes or pillarboxes.
struct DeviceView: View {
    let device: Device
    let screenContent: NSImage?
    /// When set, the view enters calibration mode: shows the screenRect
    /// as a draggable overlay, writes new coordinates back through the
    /// binding in photo-pixel coordinates.
    var editableRect: Binding<CGRect>? = nil
    /// Corner radius for the screen content mask, in *photo-pixel* units.
    /// Defaults to the device's own value but can be overridden (e.g.
    /// during calibration) via this binding.
    var cornerRadius: CGFloat? = nil

    var body: some View {
        if let cropped = device.croppedFocus() {
            // Scale to fill the available HEIGHT (aspect preserved), then
            // size the image to its naturally-scaled width so it doesn't
            // push past the pane horizontally. GeometryReader gives us
            // the displayed size for overlay positioning.
            GeometryReader { container in
                let aspect = device.focusRect.width / device.focusRect.height
                // Height-driven sizing:
                let imgH = container.size.height
                let imgW = imgH * aspect
                // Center horizontally if pane is wider than image
                let xPad = max(0, (container.size.width - imgW) / 2)

                ZStack(alignment: .topLeading) {
                    Image(nsImage: cropped)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: imgW, height: imgH)
                        .offset(x: xPad, y: 0)

                    // Screen overlay — uses the editable rect when
                    // calibration mode is active so button clicks move
                    // and resize the live screen content itself.
                    overlayView(imgWidth: imgW, imgHeight: imgH, xPad: xPad)
                }
            }
        } else {
            ZStack {
                Color.red.opacity(0.4)
                VStack {
                    Text("MISSING PHOTO").font(.headline).bold()
                    Text("\(device.photoResource).\(device.photoExtension)")
                        .font(.caption.monospaced())
                }
                .foregroundStyle(.white)
            }
        }
    }

    @ViewBuilder
    private func overlayView(imgWidth: CGFloat, imgHeight: CGFloat, xPad: CGFloat)
        -> some View
    {
        if let content = screenContent {
            // During calibration, use the editable rect so the screen
            // content itself moves + resizes live. Otherwise use the
            // device's canonical screenRect.
            let sr = editableRect?.wrappedValue ?? device.screenRect
            let scale = imgWidth / device.focusRect.width
            let fr = device.focusRect
            let sx = (sr.minX - fr.minX) * scale + xPad
            let sy = (sr.minY - fr.minY) * scale
            let sw = sr.width * scale
            let sh = sr.height * scale
            let radius = (cornerRadius ?? device.screenCornerRadius) * scale

            Image(nsImage: content)
                .resizable()
                .interpolation(.none)
                .frame(width: sw, height: sh)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .offset(x: sx, y: sy)
        }
    }
}

extension Device {
    /// Returns an NSImage cropped to focusRect using CGImage. CGImage
    /// uses pixel coordinates with origin at the top-left, matching how
    /// we measured screenRect/focusRect in Preview.
    func croppedFocus() -> NSImage? {
        guard let photo = self.photo,
              let cgImage = photo.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        let r = self.focusRect
        let cgRect = CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height)
        guard let cropped = cgImage.cropping(to: cgRect) else { return nil }
        return NSImage(cgImage: cropped, size: r.size)
    }
}
