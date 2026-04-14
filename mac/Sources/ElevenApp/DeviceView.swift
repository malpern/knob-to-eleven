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

    var body: some View {
        if let cropped = device.croppedFocus() {
            Image(nsImage: cropped)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .overlay {
                    GeometryReader { geo in
                        // geo.size is the image's displayed size — already
                        // the correct aspect ratio. Position screen overlay
                        // relative to it.
                        let scale = geo.size.width / device.focusRect.width
                        let sr = device.screenRect
                        let fr = device.focusRect
                        let sx = (sr.minX - fr.minX) * scale
                        let sy = (sr.minY - fr.minY) * scale
                        let sw = sr.width * scale
                        let sh = sr.height * scale

                        Group {
                            if let content = screenContent {
                                Image(nsImage: content)
                                    .resizable()
                                    .interpolation(.none)
                                    .frame(width: sw, height: sh)
                            } else {
                                RoundedRectangle(cornerRadius: max(2, 6 * scale))
                                    .strokeBorder(Color.white.opacity(0.4),
                                                  style: StrokeStyle(lineWidth: 2,
                                                                     dash: [4, 3]))
                                    .frame(width: sw, height: sh)
                            }
                        }
                        .offset(x: sx, y: sy)
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
