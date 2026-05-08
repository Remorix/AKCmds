# iOS `textutil` Implementation Details

## Scope

This note describes the current iOS implementation shipped in
[textutil.m](./textutil.m).

The goal of the iOS port is not to reproduce AppKit internals literally. The
goal is to preserve the observable macOS command behavior where the iOS runtime
provides an equivalent path, and to document the remaining boundaries clearly.

## Architecture

The iOS port stays in the same source file as the macOS implementation and
keeps the same high-level helper layout:

- `main`
- the same small helper set recovered from the binary
- `TextutilWebDelegate` retained as a separate file

The platform split is controlled with `TARGET_OS_IPHONE`.

## Core Conversion Backend

For the supported rich/public formats, the iOS implementation continues to use
the native `NSAttributedString` document pipeline.

Supported directly on iOS:

- `txt`
- `html`
- `rtf`
- `rtfd`
- `webarchive`

The iOS path uses UIKit instead of AppKit for plain-text default styling:

- `UIFont`
- `NSParagraphStyle`

The plain-text font-selection helper is therefore a UIKit implementation under
`TARGET_OS_IPHONE`, while macOS keeps the AppKit implementation.

## HTML And WebArchive

The iOS implementation supports the HTML/WebArchive option family in the
current tested scope:

- `-noload`
- `-nostore`
- `-baseurl`
- `-timeout`
- `-textsizemultiplier`
- `-excludedelements`
- `-prefixspaces`

### `-noload`

The iOS path keeps the delegate-based subresource control path through
`TextutilWebDelegate` and `WebResourceLoadDelegate`.

In the tested fetched-subresource case:

- normal HTML to webarchive conversion produced `WebSubresources`
- `-noload` HTML to webarchive conversion produced only `WebMainResource`

That matches the current macOS behavior shape.

### `-nostore`

The public iOS `NSAttributedString` webarchive serializer was not sufficient
for parity in the `-nostore` path.

For HTML-backed input with subresources:

- the normal serializer emitted `WebSubresources`
- macOS `-nostore` output should contain only `WebMainResource`

The iOS implementation therefore uses a manual binary-plist writer for the
`-nostore` webarchive path.  That writer emits:

- `WebMainResource`

only, with no `WebSubresources`.

## Metadata

The tested rich formats on iOS accept the same metadata-oriented command-line
options as the macOS implementation:

- `-title`
- `-author`
- `-subject`
- `-keywords`
- `-comment`
- `-editor`
- `-company`
- `-creationtime`
- `-modificationtime`
- `-strip`

As on macOS, plain text does not preserve rich metadata.

## `doc` And `docx`

Public `NSAttributedString` document conversion on the tested iOS runtime does
not provide working read/write support for:

- `doc`
- `docx`

However, the device does include a private framework:

- `OfficeImport.framework`

The current iOS implementation uses a narrow private fallback through
`OISpotlightImporter` for:

- `-format doc -convert txt`
- `-format docx -convert txt`
- `-format doc -info`
- `-format docx -info`

This fallback extracts plain text only.  It does not claim rich formatting
fidelity and does not add support for writing `doc` or `docx`.

## `odt` And `wordml`

The current iOS implementation does not support:

- `odt`
- `wordml`

These formats are rejected by iOS.

## Current iOS Support Boundary

Public/native path:

- `txt`
- `html`
- `rtf`
- `rtfd`
- `webarchive`

Private read-only fallback:

- `doc`
- `docx`

Unsupported on current iOS target:

- `odt`
- `wordml`

Unsupported as output on current iOS target:

- `doc`
- `docx`
- `odt`
- `wordml`
