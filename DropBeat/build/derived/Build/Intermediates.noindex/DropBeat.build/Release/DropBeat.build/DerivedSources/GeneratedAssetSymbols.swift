import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(DeveloperToolsSupport)
import DeveloperToolsSupport
#endif

#if SWIFT_PACKAGE
private let resourceBundle = Foundation.Bundle.module
#else
private class ResourceBundleClass {}
private let resourceBundle = Foundation.Bundle(for: ResourceBundleClass.self)
#endif

// MARK: - Color Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ColorResource {

}

// MARK: - Image Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ImageResource {

    /// The "dropbeats-decorative" asset catalog image resource.
    static let dropbeatsDecorative = DeveloperToolsSupport.ImageResource(name: "dropbeats-decorative", bundle: resourceBundle)

    /// The "dropbeats-mini-logo" asset catalog image resource.
    static let dropbeatsMiniLogo = DeveloperToolsSupport.ImageResource(name: "dropbeats-mini-logo", bundle: resourceBundle)

    /// The "instagram" asset catalog image resource.
    static let instagram = DeveloperToolsSupport.ImageResource(name: "instagram", bundle: resourceBundle)

    /// The "linkedin" asset catalog image resource.
    static let linkedin = DeveloperToolsSupport.ImageResource(name: "linkedin", bundle: resourceBundle)

    /// The "noise-texture" asset catalog image resource.
    static let noiseTexture = DeveloperToolsSupport.ImageResource(name: "noise-texture", bundle: resourceBundle)

    /// The "website" asset catalog image resource.
    static let website = DeveloperToolsSupport.ImageResource(name: "website", bundle: resourceBundle)

    /// The "x" asset catalog image resource.
    static let x = DeveloperToolsSupport.ImageResource(name: "x", bundle: resourceBundle)

}

// MARK: - Color Symbol Extensions -

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSColor {

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

}
#endif

#if canImport(SwiftUI)
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.Color {

}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {

}
#endif

// MARK: - Image Symbol Extensions -

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSImage {

    /// The "dropbeats-decorative" asset catalog image.
    static var dropbeatsDecorative: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .dropbeatsDecorative)
#else
        .init()
#endif
    }

    /// The "dropbeats-mini-logo" asset catalog image.
    static var dropbeatsMiniLogo: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .dropbeatsMiniLogo)
#else
        .init()
#endif
    }

    /// The "instagram" asset catalog image.
    static var instagram: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .instagram)
#else
        .init()
#endif
    }

    /// The "linkedin" asset catalog image.
    static var linkedin: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .linkedin)
#else
        .init()
#endif
    }

    /// The "noise-texture" asset catalog image.
    static var noiseTexture: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .noiseTexture)
#else
        .init()
#endif
    }

    /// The "website" asset catalog image.
    static var website: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .website)
#else
        .init()
#endif
    }

    /// The "x" asset catalog image.
    static var x: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .x)
#else
        .init()
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    /// The "dropbeats-decorative" asset catalog image.
    static var dropbeatsDecorative: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .dropbeatsDecorative)
#else
        .init()
#endif
    }

    /// The "dropbeats-mini-logo" asset catalog image.
    static var dropbeatsMiniLogo: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .dropbeatsMiniLogo)
#else
        .init()
#endif
    }

    /// The "instagram" asset catalog image.
    static var instagram: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .instagram)
#else
        .init()
#endif
    }

    /// The "linkedin" asset catalog image.
    static var linkedin: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .linkedin)
#else
        .init()
#endif
    }

    /// The "noise-texture" asset catalog image.
    static var noiseTexture: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .noiseTexture)
#else
        .init()
#endif
    }

    /// The "website" asset catalog image.
    static var website: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .website)
#else
        .init()
#endif
    }

    /// The "x" asset catalog image.
    static var x: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .x)
#else
        .init()
#endif
    }

}
#endif

// MARK: - Thinnable Asset Support -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@available(watchOS, unavailable)
extension DeveloperToolsSupport.ColorResource {

    private init?(thinnableName: Swift.String, bundle: Foundation.Bundle) {
#if canImport(AppKit) && os(macOS)
        if AppKit.NSColor(named: NSColor.Name(thinnableName), bundle: bundle) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#elseif canImport(UIKit) && !os(watchOS)
        if UIKit.UIColor(named: thinnableName, in: bundle, compatibleWith: nil) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
#if !os(watchOS)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(SwiftUI)
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.Color {

    private init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
        if let resource = thinnableResource {
            self.init(resource)
        } else {
            return nil
        }
    }

}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {

    private init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
        if let resource = thinnableResource {
            self.init(resource)
        } else {
            return nil
        }
    }

}
#endif

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@available(watchOS, unavailable)
extension DeveloperToolsSupport.ImageResource {

    private init?(thinnableName: Swift.String, bundle: Foundation.Bundle) {
#if canImport(AppKit) && os(macOS)
        if bundle.image(forResource: NSImage.Name(thinnableName)) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#elseif canImport(UIKit) && !os(watchOS)
        if UIKit.UIImage(named: thinnableName, in: bundle, compatibleWith: nil) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSImage {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ImageResource?) {
#if !targetEnvironment(macCatalyst)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ImageResource?) {
#if !os(watchOS)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

