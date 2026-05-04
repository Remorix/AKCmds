# iOS `open` Implementation Details

## Scope

This note describes the shipped iOS behavior currently implemented in
`ios_open.m`.

## Architecture

The iOS port uses two backends:

- `LSApplicationWorkspace` for implicit file and URL opens, document opens,
  and user-activity dispatch
- FrontBoard / BackBoard private APIs for explicit app launch, fresh launch,
  wait, and launch-option flows

The split is intentional. On iOS, plain open behavior is a LaunchServices
operation, while explicit app-targeted launch behavior is controlled through
FrontBoard.

## Application Resolution

Explicit app selection supports:

- `-b <bundle identifier>`
- `-a <application>`

Bundle IDs are matched against installed `LSApplicationProxy` objects.
Application names are matched against:

- `localizedNameForContext:`
- `itemName`
- `localizedShortName`

When no explicit app is already selected, a filesystem operand that matches an
installed app bundle path or canonical executable path is treated as an app
launch target.

## Header Search

`-h` searches header include and framework roots and opens the resolved match
or matches.

The implementation reuses the shared macOS header scanner and fast-path table,
but adapts the search roots to iOS SDK and framework locations.

`-s <partial SDK name>` filters the SDK-directory portion of that search.

The hidden `-H` variant is supported and excludes `.Internal.sdk` directories.

Without an explicit app target, resolved headers are opened through the same
plain-text-editor path used by `-t`.

## Text Editing Semantics

### `-e`

`-e` targets `com.apple.TextEdit` when it is available.

On iOS this is intentionally copy-to-app editing:

- LaunchServices imports a copy into the app
- edits do not write back to the original path
- successful opens print the imported destination path when LaunchServices
  reports it

### `-t`

`-t` resolves the default plain-text editor through LaunchServices document
binding for `public.text`.

Like `-e`, it is copy-to-app editing on iOS rather than in-place editing.

### `-f`

`-f` writes stdin to a temporary `.txt` file and opens it in TextEdit.

This still uses the same iOS copy-to-app editing model.

## Launch Options

Explicit app launches use `FBSOpenApplicationService` and
`FBSOpenApplicationOptions`.

The current implementation supports:

- `--args`
- `--env`
- `-o`
- `-E`
- `-g`
- `-n`
- `-W`
- `--unlock`
- `--intent`
- `--annotation`

### `-F`

`-F` is implemented as:

1. terminate the target app
2. clear Saved Application State
3. relaunch

This is only supported when an explicit app target is known.

### `-n`

On iOS, `-n` means request a new scene. It does not mean a second process
instance.

### `-g`

`-g` maps to suspended launch behavior when the launch path actually goes
through FrontBoard.

It is rejected with `--userActivity`, because the LaunchServices user-activity
open path did not honor it in runtime testing.

### `-W`

`-W` is implemented only for explicitly launched applications.

### `--unlock`

`--unlock` is supported only on explicit FrontBoard launch paths.

### `--intent`

`--intent` is intentionally narrow on iOS:

- a LaunchIntent boolean flag for explicit app launches
- also supported on user-activity opens

It is not a generic Siri or App Intent runner.

### `--annotation`

`--annotation` is supported only for:

- single explicit-app URL opens
- single explicit-app document opens

The generic implicit `LSApplicationWorkspace openURL:` path does not preserve
the annotation payload on the tested OS version.

## User Activities

`--userActivity <type>` opens the app for an `NSUserActivity` type.

The current payload surface supports:

- `--userActivityTitle`
- `--userActivityWebpageURL`
- repeated `--userActivityInfo KEY=VALUE`

When `-a` or `-b` is not supplied, the implementation falls back to scanning
installed `Info.plist` declarations if `applicationForUserActivityType:` is
not reliable enough.

If more than one app declares the same activity type, `open` fails with an
explicit ambiguity error.

The implementation does not expose a document-URL payload because the tested
LaunchServices user-activity path strips `NSUserActivityDocumentURLKey` before
the receiving app sees it.

## `-R` Reveal Semantics

`-R` is implemented as a Filza reveal path.

Requirements:

- a usable `com.tigisoftware.Filza` installation
- a declared `filza` URL scheme

Current behavior:

- `open -R <path>` launches Filza and highlights the requested item

This is reveal/highlight behavior, not a generic “open file in Filza viewer”
path.

## Unsupported Flags

The current iOS implementation rejects these with explicit messages:

- `-j`
- `-x`
- `-i`

## macOS Semantic Differences

The main iOS differences are:

- `-e` and `-t` are copy-to-app editing, not in-place editing
- `-n` means new scene, not new process
- `-W` only applies to explicitly launched applications
- `-R` uses Filza reveal instead of Finder reveal
- `--intent` is a narrow launch flag, not a generic intent runner

## Operational Notes

The current iOS implementation therefore behaves as follows:

- implicit opens go through LaunchServices
- explicit app launches go through FrontBoard
- document-style editor opens use the LaunchServices document-open path
- header search reuses the shared scanner
- Filza is used only for `-R`
