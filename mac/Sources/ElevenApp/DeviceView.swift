import SwiftUI

/// Renders a device photo, cropped to its `focusRect`, and overlays
/// the simulator's most recent rendered PNG inside the screen rectangle.
///
/// Coords arithmetic: photo + screenRect + focusRect are all in the
/// photo's *natural pixel* coordinate space. We crop the photo to focusRect
/// and overlay a smaller image at (screenRect - focusRect.origin), scaled
/// proportionally to whatever pixel size the SwiftUI view ends up at.
struct DeviceView: View {
    let device: Device
    /// PNG of the simulator output. nil = nothing rendered yet.
    let screenContent: NSImage?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if let photo = device.photo {
                    croppedPhoto(photo, in: geo.size)
                } else {
                    placeholder
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(device.focusRect.width / device.focusRect.height,
                     contentMode: .fit)
    }

    @ViewBuilder
    private func croppedPhoto(_ photo: NSImage, in viewSize: CGSize) -> some View {
        // Convert focusRect (in photo pixels) to a fraction of the photo's
        // natural size, then offset/scale to display only that crop.
        let pw = photo.size.width
        let ph = photo.size.height
        let fr = device.focusRect

        // Scale so focusRect fits the view exactly
        let scaleX = viewSize.width / fr.width
        let scaleY = viewSize.height / fr.height
        let scale = min(scaleX, scaleY)

        ZStack(alignment: .topLeading) {
            // Render the full photo, scaled, but offset so focusRect.origin
            // sits at (0,0) and overflow is clipped.
            Image(nsImage: photo)
                .resizable()
                .interpolation(.high)
                .frame(width: pw * scale, height: ph * scale)
                .offset(x: -fr.minX * scale, y: -fr.minY * scale)

            // Overlay the screen content at screenRect (relative to focusRect)
            screenOverlay(scale: scale)
        }
        .frame(width: viewSize.width, height: viewSize.height)
        .clipped()
        .background(Color.black.opacity(0.05))
    }

    @ViewBuilder
    private func screenOverlay(scale: CGFloat) -> some View {
        let sr = device.screenRect
        let fr = device.focusRect
        let x = (sr.minX - fr.minX) * scale
        let y = (sr.minY - fr.minY) * scale
        let w = sr.width * scale
        let h = sr.height * scale

        Group {
            if let content = screenContent {
                Image(nsImage: content)
                    .resizable()
                    .interpolation(.none)  // pixel-honest; the device is portrait-pixel
                    .aspectRatio(device.screenSize.width / device.screenSize.height,
                                 contentMode: .fill)
                    .frame(width: w, height: h)
                    .clipped()
            } else {
                // Empty/idle state — subtle dotted rectangle so the user knows
                // where the screen lives even before any render
                RoundedRectangle(cornerRadius: 6 * scale)
                    .strokeBorder(Color.white.opacity(0.4),
                                  style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    .frame(width: w, height: h)
            }
        }
        .offset(x: x, y: y)
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.2))
            .overlay(Text("missing photo: \(device.photoResource).\(device.photoExtension)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary))
    }
}
