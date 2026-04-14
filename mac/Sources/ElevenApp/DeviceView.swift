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
    /// Optional live-editable backing rect (photo-pixel coords). Draws a
    /// black rounded rect behind the screen so the device bezel looks
    /// continuous below the active pixel area.
    var editableBackingRect: Binding<CGRect>? = nil
    /// Optional reference image to overlay on top of the live screen
    /// content (e.g. a native device photograph for visual comparison).
    /// Drawn inside the screen rect, same clip shape as `screenContent`.
    var referenceImage: NSImage? = nil
    /// Opacity of the reference image overlay, 0…1.
    var referenceOpacity: Double = 0
    /// Invoked when the user clicks a half of the top encoder. Delta is
    /// `-1` for left-side clicks (CCW) and `+1` for right-side (CW).
    var onEncoder: ((Int) -> Void)? = nil
    @State private var encoderFlashSide: Int = 0   // -1 / 0 / +1
    @State private var encoderHover: Int = 0       // -1 / 0 / +1

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

                    // Black backing — drawn before the screen so it sits
                    // behind any content and fills in the bezel area.
                    backingView(imgWidth: imgW, imgHeight: imgH, xPad: xPad)

                    // Screen overlay — uses the editable rect when
                    // calibration mode is active so button clicks move
                    // and resize the live screen content itself.
                    overlayView(imgWidth: imgW, imgHeight: imgH, xPad: xPad)

                    // Top-encoder click regions with tap feedback.
                    encoderClickRegions(imgWidth: imgW, imgHeight: imgH, xPad: xPad)
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
    private func backingView(imgWidth: CGFloat, imgHeight: CGFloat, xPad: CGFloat)
        -> some View
    {
        // Only draw the backing when there is live screen content to
        // sit behind, OR when the user is calibrating (so they can see
        // what they're positioning). In the plain "no app" case, the
        // device photo shows as-is.
        if screenContent != nil || editableBackingRect != nil {
            let br = editableBackingRect?.wrappedValue ?? device.screenBackingRect
            let fr = device.focusRect
            let scale = imgWidth / fr.width
            let bx = (br.minX - fr.minX) * scale + xPad
            let by = (br.minY - fr.minY) * scale
            let bw = br.width * scale
            let bh = br.height * scale
            let radius = (cornerRadius ?? device.screenCornerRadius) * scale
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.black)
                .frame(width: bw, height: bh)
                .offset(x: bx, y: by)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func encoderClickRegions(imgWidth: CGFloat, imgHeight: CGFloat, xPad: CGFloat)
        -> some View
    {
        let er = device.topEncoderRect
        let fr = device.focusRect
        let scale = imgWidth / fr.width
        let ex = (er.minX - fr.minX) * scale + xPad
        let ey = (er.minY - fr.minY) * scale
        let ew = er.width * scale
        let eh = er.height * scale
        let halfW = ew / 2

        let showRing = encoderHover != 0
        ZStack(alignment: .topLeading) {
            // Hover-only ring around the whole encoder + split line
            // so the clickable area is obvious while the mouse is over
            // it, but the photo stays clean otherwise.
            Circle()
                .strokeBorder(Color.orange.opacity(showRing ? 0.9 : 0),
                              style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                .frame(width: ew, height: eh)
                .offset(x: ex, y: ey)
                .animation(.easeOut(duration: 0.1), value: showRing)
                .allowsHitTesting(false)

            Rectangle()
                .fill(Color.orange.opacity(showRing ? 0.7 : 0))
                .frame(width: 1, height: eh)
                .offset(x: ex + halfW, y: ey)
                .animation(.easeOut(duration: 0.1), value: showRing)
                .allowsHitTesting(false)

            // Left half — CCW (-1).
            encoderHalf(side: -1, icon: "chevron.left")
                .frame(width: halfW, height: eh)
                .offset(x: ex, y: ey)

            // Right half — CW (+1).
            encoderHalf(side: +1, icon: "chevron.right")
                .frame(width: halfW, height: eh)
                .offset(x: ex + halfW, y: ey)
        }
    }

    @ViewBuilder
    private func encoderHalf(side: Int, icon: String) -> some View {
        let flashing = encoderFlashSide == side
        let hovering = encoderHover == side
        ZStack {
            // Hover tint — brighter than the dashed outline so it's
            // obvious which half you're about to click.
            Color.orange
                .opacity(hovering ? 0.25 : 0.0)

            Image(systemName: icon)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.7), radius: 3)
                .opacity(flashing ? 1.0 : (hovering ? 0.6 : 0.0))
                .scaleEffect(flashing ? 1.25 : (hovering ? 1.05 : 0.9))
                .animation(.easeOut(duration: 0.12), value: flashing)
                .animation(.easeOut(duration: 0.08), value: hovering)
        }
        .contentShape(Rectangle())
        .onHover { inside in
            encoderHover = inside ? side : (encoderHover == side ? 0 : encoderHover)
        }
        .onTapGesture {
            onEncoder?(side)
            NSSound(named: "Tink")?.play()
            encoderFlashSide = side
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                if encoderFlashSide == side { encoderFlashSide = 0 }
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

            // Display-layer simulation of the physical LCD:
            // - nearest-neighbor scaling preserves the pixel grid
            //   (consistent with Fryc's "suitable for pixel art" framing)
            // - tiny blur softens the otherwise-crisp pixel edges,
            //   approximating LCD subpixel smear
            // - a faint white overlay in .plusLighter mode raises the
            //   black floor so pure-black LVGL output looks like an LCD
            //   that can't quite reach true black, not like OLED
            ZStack {
                Image(nsImage: content)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: sw, height: sh)
                    .blur(radius: 0.3)
                    .overlay(
                        Color(white: 1.0)
                            .opacity(0.04)
                            .blendMode(.plusLighter)
                    )
                    .compositingGroup()

                if let ref = referenceImage, referenceOpacity > 0 {
                    Image(nsImage: ref)
                        .resizable()
                        .frame(width: sw, height: sh)
                        .opacity(referenceOpacity)
                        .allowsHitTesting(false)
                }
            }
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
