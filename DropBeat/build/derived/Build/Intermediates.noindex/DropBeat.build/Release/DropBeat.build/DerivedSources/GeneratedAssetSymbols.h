#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The "dropbeats-decorative" asset catalog image resource.
static NSString * const ACImageNameDropbeatsDecorative AC_SWIFT_PRIVATE = @"dropbeats-decorative";

/// The "dropbeats-mini-logo" asset catalog image resource.
static NSString * const ACImageNameDropbeatsMiniLogo AC_SWIFT_PRIVATE = @"dropbeats-mini-logo";

/// The "instagram" asset catalog image resource.
static NSString * const ACImageNameInstagram AC_SWIFT_PRIVATE = @"instagram";

/// The "linkedin" asset catalog image resource.
static NSString * const ACImageNameLinkedin AC_SWIFT_PRIVATE = @"linkedin";

/// The "noise-texture" asset catalog image resource.
static NSString * const ACImageNameNoiseTexture AC_SWIFT_PRIVATE = @"noise-texture";

/// The "website" asset catalog image resource.
static NSString * const ACImageNameWebsite AC_SWIFT_PRIVATE = @"website";

/// The "x" asset catalog image resource.
static NSString * const ACImageNameX AC_SWIFT_PRIVATE = @"x";

#undef AC_SWIFT_PRIVATE
