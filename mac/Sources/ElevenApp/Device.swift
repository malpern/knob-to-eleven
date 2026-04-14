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
    /// The device's actual screen geometry in physical pixels.
    let screenSize: CGSize
    /// The portion of the photo to show by default — focuses on the screen
    /// module + nearby controls instead of the full keyboard.
    let focusRect: CGRect

    /// Resolved NSImage. Returns nil if the resource isn't bundled.
    var photo: NSImage? {
        Bundle.module.url(forResource: photoResource, withExtension: photoExtension,
                          subdirectory: "devices/knob")
            .flatMap { NSImage(contentsOf: $0) }
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
        screenRect: CGRect(x: 3415, y: 859, width: 163, height: 567),
        screenSize: CGSize(width: 100, height: 310),
        // Right portion of the keyboard — screen module, two encoders,
        // and the action keys. Skips most of the QWERTY field.
        focusRect: CGRect(x: 2700, y: 60, width: 1100, height: 1700)
    )
}
