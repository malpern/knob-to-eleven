import Foundation
import AppKit

/// One physical device we can frame in the UI.
struct Device: Identifiable, Hashable {
    let id: String
    let displayName: String
    /// Resource name (without extension) of the device photo.
    let photoResource: String
    let photoExtension: String
    /// Screen rectangle in the photo's *natural* pixel coords.
    let screenRect: CGRect
    /// Corner radius of the screen, in *photo-pixel* units. 0 = sharp
    /// corners. Rendered proportionally when displayed.
    let screenCornerRadius: CGFloat
    /// The device's actual screen geometry in physical pixels.
    let screenSize: CGSize
    /// The portion of the photo to show by default — focuses on the screen
    /// module + nearby controls instead of the full keyboard.
    let focusRect: CGRect

    /// Resolved NSImage. Returns nil if the resource isn't bundled.
    /// (`.process("Resources")` flattens the dir structure, so files
    /// land at the bundle root regardless of source subdirectory.)
    var photo: NSImage? {
        let url = Bundle.module.url(forResource: photoResource,
                                    withExtension: photoExtension)
        if url == nil {
            print("Device.photo: NO URL for \(photoResource).\(photoExtension)")
            print("  Bundle.module.bundlePath = \(Bundle.module.bundlePath)")
            print("  contents: \((try? FileManager.default.contentsOfDirectory(atPath: Bundle.module.bundlePath)) ?? [])")
        }
        guard let url, let img = NSImage(contentsOf: url) else { return nil }
        return img
    }
}

extension Device {
    /// The k·no·b·1 keyboard, photo knob-01.
    /// Screen rect identified by clicking the screen corners on the photo
    /// at 3415,859 – 3578,1426. Aspect 3.48; slightly taller than the
    /// device's 3.10 because the selection includes the rounded-rect
    /// bezel around the active pixel area.
    static let knob1 = Device(
        id: "knob-1",
        displayName: "k·no·b·1",
        photoResource: "knob-01",
        photoExtension: "png",
        // Calibrated against knob-01.png in-app (⌘E calibration, copy).
        // 595/192 = 3.099, matching the device's 310/100 physical aspect.
        screenRect: CGRect(x: 3407, y: 857, width: 192, height: 595),
        screenCornerRadius: 64,
        screenSize: CGSize(width: 100, height: 310),
        // Right portion of the keyboard — screen module, two encoders,
        // and the action keys. Skips most of the QWERTY field.
        focusRect: CGRect(x: 2700, y: 60, width: 1100, height: 1700)
    )
}
