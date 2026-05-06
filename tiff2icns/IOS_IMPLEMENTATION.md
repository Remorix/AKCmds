# iOS `tiff2icns` Implementation Details

## Scope

This note describes the implementation currently in `tiff2icns.m` of the
shipped iOS behavior.

The goal of the iOS port is not to reproduce AppKit internals literally. The
goal is to reproduce the observable behavior of `/usr/bin/tiff2icns` as closely
as possible on iOS.

## Architecture

The iOS port stays in the same source file and preserves the same high-level
function layout as the macOS implementation:

- `main`
- one worker routine
- one exact-size selection helper

The platform split is controlled with `TARGET_OS_IPHONE`.

## Input Backend

The iOS implementation does not use `UIImage`.

It uses public ImageIO entry points for container loading and representation
enumeration:

- `CGImageSourceCreateWithURL`
- `CGImageSourceGetCount`
- `CGImageSourceCopyPropertiesAtIndex`
- `CGImageSourceCreateImageAtIndex`

This keeps the input side closer to the macOS command's real behavior, which is
representation-oriented rather than `UIImage`-oriented.

In practice, this preserves the tested input classes already covered on macOS:

- TIFF
- PNG
- ICNS
- generic image files loadable through ImageIO

## Representation Selection

The iOS helper implements the same selection policy as the macOS helper:

- only exact square representations are considered
- sizes are searched in this order:
  - `48`
  - `32`
  - `16`
  - `128`
  - `256`
  - `512`
  - `1024`
- if multiple exact matches exist for one size, the preferred representation is
  the one with the highest depth

On iOS, the depth comparison uses:

- `kCGImagePropertyDepth`

This is the public ImageIO analogue of the macOS implementation's
`bitsPerSample` preference.

## Output Backend

The iOS output path uses public ImageIO serialization:

- `CGImageDestinationCreateWithData(..., kUTTypeAppleICNS, ...)`
- `CGImageDestinationAddImage(...)`
- `CGImageDestinationFinalize()`

The chosen representations are appended in the same order they were selected.

If no suitable representation is found, the iOS implementation matches the
macOS command's fallback behavior:

- print the same warning
- write an empty output file

## Synthetic `32x32` Behavior

The original macOS binary contains an AppKit focus-based path that appears
intended to synthesize a `32x32` icon when `-noLarge` is not used and no real
`32x32` representation exists.

The iOS port intentionally does not emit a synthetic `32x32` representation.

This is a compatibility choice, not an API limitation.

Reason:

- local differential testing showed that the current macOS
  `/usr/bin/tiff2icns` did not emit an extra usable `32x32` icon for the
  exercised inputs
- an earlier CoreGraphics-based replacement on iOS changed the output bytes
- preserving the system command's observable output was the higher-priority
  goal

So the iOS implementation preserves the current macOS result, not the dormant
AppKit implementation detail.

## `1024x1024` Behavior

During runtime probing on a jailbroken iOS device, public ImageIO reported
`com.apple.icns` as a supported destination type, but its behavior for
`1024x1024` inputs matched the current macOS command's observable result in the
tested cases:

- single `1024x1024` input produced an empty output file
- mixed inputs such as `512 + 1024` produced the same output as macOS

The iOS implementation therefore preserves the same tested `1024` behavior as
the host macOS binary.

## API Surface

The current iOS implementation depends only on public frameworks:

- `Foundation`
- `CoreFoundation`
- `CoreGraphics`
- `ImageIO`
- `MobileCoreServices`

It does not depend on private icon-writing APIs.

In the shipped implementation:

- ImageIO is responsible for input enumeration and `icns` serialization
- CoreGraphics is present only through the shared image object/type layer used
  by those public APIs

## Operational Notes

The current iOS implementation therefore behaves as follows:

- input enumeration is ImageIO-based
- exact-size selection follows the macOS command's size order and depth
  preference
- output serialization uses public ImageIO `icns` writing
- synthetic `32x32` emission is intentionally suppressed to preserve observed
  macOS output
- `1024` behavior follows the current system command's tested output, including
  the empty-file case for single-size input
