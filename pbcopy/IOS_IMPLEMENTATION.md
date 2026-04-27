# iOS `pbcopy` / `pbpaste` Implementation Details

## Scope

This note describes the implementation currently in `pbcopy.m` of the shipped iOS behavior.

## Architecture

The iOS port uses two backends:

- the real general pasteboard for UI interoperability
- a compatibility store for AppKit-style named boards

The split is intentional. On iOS, the general pasteboard is the only board that behaves like a stable cross-process UI paste target. AppKit-style named boards do not have equivalent reliable system semantics on iOS.

## General Pasteboard

### Backend

The real board is:

- `com.apple.UIKit.pboard.general`

It is accessed through private `Pasteboard.framework` objects:

- `PBServerConnection`
- `PBItem`
- `PBItemCollection`

This path is used for both `pbcopy` and `pbpaste` on the general board.

### Plain text representation

Plain text writes use the general pasteboard directly and expose plain UTF-8 text.

### Rich text representation

Rich general-board writes are emitted as a rich-primary item with these representations:

1. `Apple Web Archive pasteboard type`
2. `com.apple.flat-rtfd`
3. `public.utf8-plain-text`

The primary representation is HTML data stored under:

- `Apple Web Archive pasteboard type`

This is intentionally HTML text, not a binary `NSWebArchive` plist.

The second representation is:

- `com.apple.flat-rtfd`

The plain-text fallback is:

- `public.utf8-plain-text`

### Rich text normalization

When rich text is copied to the iOS general pasteboard, the attributed string is normalized before export. The implementation mirrors the size regime currently produced by iOS TextEdit for macOS-origin rich text.

The implementation scales `NSFontAttributeName` by:

- `1.299f`

This produces the same size regime currently seen in iOS TextEdit for macOS-origin rich text:

- `10 -> 12.99`
- `12 -> 15.58`
- `15 -> 19.48`
- `18 -> 23.38`
- `26 -> 33.77`

The scaled attributed string is then exported to HTML and FlatRTFD.

## General Pasteboard Read Semantics

For default output, `pbpaste` prefers direct plain-text output when available.

For `pbpaste -Prefer rtf`, the current type preference order is:

1. `public.rtf`
2. `Apple Web Archive pasteboard type`
3. `public.html`
4. `com.apple.webarchive`
5. `com.apple.flat-rtfd`
6. `com.apple.rtfd`
7. `public.utf8-plain-text`

`Apple Web Archive pasteboard type` is decoded as HTML.

`com.apple.webarchive` is decoded as `NSWebArchiveTextDocumentType`.

`com.apple.flat-rtfd` and `com.apple.rtfd` are decoded as `NSRTFDTextDocumentType`.

## Named Boards

### Backend

The named-board compatibility store is a `CFPreferences` domain:

- `pbcopy.pboards`

The implementation synchronizes that domain for the `mobile` user, which makes it visible to both `root` and `mobile`.

### Stored layout

The current write format is:

- top-level dictionary keyed by pasteboard name
- each value is the board's type dictionary

Backward-compatible reads still accept the older wrapped format:

- `{"name": ..., "types": ...}`

### Implemented named boards

The iOS implementation recognizes:

- `NSFontPboard`
- `NSFindPboard`
- `NSRulerPboard`

These are compatibility boards, not system UIKit boards.

## `-pboard font`

`-pboard font` is implemented as a separate logical board in the compatibility store.

It supports:

- plain text round-trip
- rich RTF round-trip
- cross-process use
- cross-user use between `root` and `mobile`

It does not participate in UIKit app pasteboard behavior as a real platform font board.

## `-pboard find` and `-pboard ruler`

These names are implemented only at the compatibility layer.

They do not correspond to a meaningful iOS system-wide UI feature in this port.

## macOS Semantic Differences

### General board model

The iOS implementation is centered on one real general board with multiple representations. This differs from the AppKit model, where several named boards have stronger system semantics.

### `font` semantics

On iOS, `-pboard font` is a CLI compatibility feature. It is not equivalent to a true platform font pasteboard used by UIKit apps.

### Private API dependence

The general-board path depends on private APIs and matching entitlements. That dependency is part of the implementation, not an optional optimization.

## Operational Notes

The current iOS implementation therefore behaves as follows:

- UI interoperability goes through the real general pasteboard
- rich UI-facing content is emitted as HTML + FlatRTFD + UTF-8 text
- AppKit-style named boards are emulated through the compatibility store
- `font` is supported as a logical board, while `find` and `ruler` remain compatibility-only
