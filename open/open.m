// macOS implementation of open.

#import "open_internal.h"

#include <errno.h>
#include <getopt.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/event.h>
#include <sys/time.h>
#include <sys/types.h>
#include <unistd.h>

BOOL gVerbose            = NO;
BOOL gHideInternalSDKs   = NO;
NSString *gSDKFilter     = nil;
BOOL gBackground         = NO;
BOOL gWait               = NO;
BOOL gFresh              = NO;
BOOL gDefaultTextEditor  = NO;
BOOL gTextEdit           = NO;
BOOL gHideApp            = NO;
BOOL gNewInstance        = NO;
BOOL gExcludeFromRecents = NO;
BOOL gReadStdin          = NO;
BOOL gArgsSeen           = NO;
BOOL gReveal             = NO;
BOOL gHeaderMode         = NO;
BOOL gCancelled          = NO;
NSURL *gStdinURL         = nil;
NSURL *gStdoutURL        = nil;
NSURL *gStderrURL        = nil;
NSMutableDictionary *gEnvVars = nil;

int main(int argc, const char *argv[]) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    NSMutableArray *extraURLs  = [NSMutableArray array];
    NSMutableArray *appArgs    = nil;

    // Stop option parsing at "--args" and keep the remaining argv entries for
    // the launched application.
    int argc2 = argc;
    const char **argv2 = argv;
    const char **scanArgv = argv;
    for (int remaining = argc; remaining > 0; --remaining, ++scanArgv) {
        char *arg = (char *)*scanArgv;
        if (gArgsSeen) {
            if (!appArgs)
                appArgs = [NSMutableArray array];
            NSString *s = stringFromArg(arg);
            if (s) [appArgs addObject:s];
            *arg = '\0';
            --argc2;
        } else if (strcmp(arg, "--args") == 0) {
            gArgsSeen = YES;
            *arg = '\0';
            --argc2;
        }
    }

    struct option longopts[] = {
        { "new",        no_argument,       (int *)&gNewInstance,        1 },
        { "background", no_argument,       (int *)&gBackground,         1 },
        { "hide",       no_argument,       (int *)&gHideApp,            1 },
        { "reveal",     no_argument,       (int *)&gReveal,             1 },
        { "wait-apps",  no_argument,       (int *)&gWait,               1 },
        { "no-recents", no_argument,       (int *)&gExcludeFromRecents, 1 },
        { "header",     no_argument,       (int *)&gHeaderMode,         1 },
        { "fresh",      no_argument,       (int *)&gFresh,              1 },
        { "stdin",      required_argument, NULL, 'i' },
        { "stdout",     required_argument, NULL, 'o' },
        { "stderr",     required_argument, NULL, 'E' },
        { "env",        required_argument, NULL, 'V' },
        { "url",        required_argument, NULL, 'u' },
        { NULL, 0, NULL, 0 }
    };

    NSString *appName    = nil;
    NSString *bundleID   = nil;

    int ch;
    while ((ch = getopt_long(argc2, (char *const *)argv2,
                             "etfFb:a:s:WRnghHvji:o:E:u:", longopts, NULL)) != -1) {
        switch (ch) {
            case 0:
                break;
            case 'E':
                [gStderrURL release];
                gStderrURL = [[NSURL fileURLWithFileSystemRepresentation:optarg
                                                             isDirectory:NO
                                                         relativeToURL:nil] retain];
                break;
            case 'F': gFresh = YES; break;
            case 'H': gHeaderMode = YES; gHideInternalSDKs = YES; break;
            case 'R': gReveal = YES; break;
            case 'V': {
                if (optarg && *optarg) {
                    char *eq = strchr(optarg, '=');
                    NSString *key = nil, *val = nil;
                    if (eq) {
                        ptrdiff_t klen = eq - optarg;
                        if (klen >= 2) {
                            key = [[[NSString alloc] initWithBytes:optarg
                                                            length:(NSUInteger)klen
                                                          encoding:NSUTF8StringEncoding]
                                       autorelease];
                            val = [[[NSString alloc] initWithCString:eq + 1
                                                            encoding:NSUTF8StringEncoding]
                                       autorelease];
                        } else {
                            NSString *msg = [NSString stringWithFormat:
                                @"Ignoring incorrectly formatted enviroment variable %s", optarg];
                            fputs([msg UTF8String], stderr);
                            fputc('\n', stderr);
                        }
                    } else {
                        key = [NSString stringWithUTF8String:optarg];
                        val = @"";
                    }
                    if (key && val) {
                        if (!gEnvVars)
                            gEnvVars = [[NSMutableDictionary dictionary] retain];
                        gEnvVars[key] = val;
                    }
                }
                break;
            }
            case 'W': gWait = YES; break;
            case 'a':
                appName = [NSString stringWithUTF8String:optarg];
                break;
            case 'b':
                bundleID = [NSString stringWithUTF8String:optarg];
                break;
            case 'e': gTextEdit = YES; break;
            case 'f': gReadStdin = YES; break;
            case 'g': gBackground = YES; break;
            case 'h': gHeaderMode = YES; gHideInternalSDKs = NO; break;
            case 'i':
                [gStdinURL release];
                gStdinURL = [[NSURL fileURLWithFileSystemRepresentation:optarg
                                                            isDirectory:NO
                                                        relativeToURL:nil] retain];
                break;
            case 'j': gHideApp = YES; break;
            case 'n': gNewInstance = YES; break;
            case 'o':
                [gStdoutURL release];
                gStdoutURL = [[NSURL fileURLWithFileSystemRepresentation:optarg
                                                             isDirectory:NO
                                                         relativeToURL:nil] retain];
                break;
            case 's':
                gSDKFilter = [NSString stringWithUTF8String:optarg];
                break;
            case 't': gDefaultTextEditor = YES; break;
            case 'u': {
                NSString *s = stringFromArg(optarg);
                if (!s
                    || ![s containsString:@":"]
                    || ![NSURL URLWithString:s]) {
                    dieWithError([NSString stringWithFormat:
                        @"Unable to interpret '%s' as a URL", optarg]);
                }
                [extraURLs addObject:[NSURL URLWithString:s]];
                break;
            }
            case 'v': gVerbose = YES; break;
            case 'x': gExcludeFromRecents = YES; break;
            default:
                if (ch == '?') goto usage;
                if (ch == -1) goto done_opts;
                goto usage;
        }
    }
done_opts:;

    // ── -f: read stdin to a temp file, open in TextEdit ─────────────────────
    NSMutableArray *pendingURLs = [NSMutableArray array]; // URLs to open
    NSString *targetBundleID   = nil;

    if (gReadStdin) {
        char tmpPath[64];
        strcpy(tmpPath, "/tmp/open_XXXXXXXX.txt");
        int fd = mkstemps(tmpPath, 4);
        if (fd == -1) {
            int e = errno;
            dieWithError([NSString stringWithFormat:
                @"Unable to open temporary file.  The error was %d: %s", e, strerror(e)]);
        }
        [pendingURLs addObject:[NSURL fileURLWithPath:
            [NSString stringWithUTF8String:tmpPath]]];

        char buf[0x1000];
        size_t n;
        while ((n = fread(buf, 1, sizeof(buf), stdin)) > 0) {
            for (size_t written = 0; written < n; ) {
                ssize_t w = write(fd, buf + written, n - written);
                if (w < 0) {
                    int e = errno;
                    dieWithError([NSString stringWithFormat:
                        @"Unable to write to temporary file %s.  The error was %d: %s",
                        tmpPath, e, strerror(e)]);
                }
                written += (size_t)w;
            }
        }
        if (ferror(stdin)) {
            int e = errno;
            dieWithError([NSString stringWithFormat:
                @"Error reading from stdin, while writing to temporary file %s.  The error was %d: %s",
                tmpPath, e, strerror(e)]);
        }
        gTextEdit = YES;
        targetBundleID = @"com.apple.TextEdit";
    }

    // ── -t / -e: pick target text editor ────────────────────────────────────
    NSURL *appURL = nil;  // explicit app URL (from -t lookup or later resolution)

    if (gDefaultTextEditor) {
        CFURLRef editorURL = LSCopyDefaultApplicationURLForContentType(
            (CFStringRef)@"public.plain-text", kLSRolesAll, NULL);
        if (editorURL) {
            appURL = [(NSURL *)editorURL autorelease];
        } else {
            NSString *warn = @"LSCopyDefaultApplicationURLForContentType(\"txt\") failed "
                              "while trying to determine the default text editor.  "
                              "TextEdit will be used instead.";
            fputs([warn UTF8String], stderr);
            fputc('\n', stderr);
            targetBundleID = @"com.apple.TextEdit";
        }
    } else if (gTextEdit) {
        targetBundleID = @"com.apple.TextEdit";
    } else {
        targetBundleID = bundleID;
    }

    // ── Build file-argument list from remaining argv ─────────────────────────
    NSMutableArray *fileArgs = [NSMutableArray arrayWithCapacity:
        argc2 - optind];
    for (int i = optind; i < argc2; ++i) {
        NSString *s = stringFromArg(argv2[i]);
        if (!s) {
            dieWithError([NSString stringWithFormat:
                @"Unable to read path '%s'", argv2[i]]);
        }
        [fileArgs addObject:(s.length ? s : @".")];
    }

    // ── -h/-H: header search mode ────────────────────────────────────────────
    if (gHeaderMode) {
        NSMutableArray *searchRoots = [NSMutableArray arrayWithObjects:
            [@"/usr/include/" stringByExpandingTildeInPath],
            [@"/usr/local/include/" stringByExpandingTildeInPath],
            [@"/System/Library/Frameworks/" stringByExpandingTildeInPath],
            [@"/System/Library/PrivateFrameworks/" stringByExpandingTildeInPath],
            [@"/Library/Frameworks/" stringByExpandingTildeInPath],
            [@"~/Library/Frameworks/" stringByExpandingTildeInPath],
            [@"~/Library/PrivateFrameworks/" stringByExpandingTildeInPath],
            nil];

        NSMutableArray *sdkRoots  = [NSMutableArray array];
        NSFileManager  *fm        = [NSFileManager defaultManager];

        // Determine Xcode developer directory
        NSString *developerDir = nil;
        const char *envDev = getenv("DEVELOPER_DIR");
        if (envDev) {
            developerDir = [fm stringWithFileSystemRepresentation:envDev
                                                           length:strlen(envDev)];
        } else {
            NSTask *task = [[NSTask alloc] init];
            [task setLaunchPath:@"/usr/bin/xcode-select"];
            [task setArguments:@[@"-p"]];
            NSPipe *pipe = [NSPipe pipe];
            [task setStandardOutput:pipe];
            [task launch];
            NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
            [task waitUntilExit];
            [task release];
            if (data.length) {
                developerDir = [fm
                    stringWithFileSystemRepresentation:data.bytes
                                               length:data.length];
            }
        }

        if (!developerDir)
            developerDir = @"/Applications/Xcode.app";
        else
            developerDir = [developerDir
                stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceAndNewlineCharacterSet]];

        if ([[developerDir pathExtension] isEqual:@"app"])
            developerDir = [developerDir
                stringByAppendingPathComponent:@"Contents/Developer"];

        NSURL *platformsURL = [NSURL fileURLWithPath:
            [developerDir stringByAppendingPathComponent:@"Platforms"]];

        if ([platformsURL checkResourceIsReachableAndReturnError:nil]) {
            NSArray *platformEntries = [fm
                contentsOfDirectoryAtURL:platformsURL
              includingPropertiesForKeys:@[]
                                 options:0
                                   error:nil];
            if (platformEntries) {
                NSMutableArray *platforms = [platformEntries mutableCopy];
                NSURL *macOS   = [platformsURL URLByAppendingPathComponent:@"MacOSX.platform"
                                                               isDirectory:YES];
                NSURL *iphoneOS = [platformsURL URLByAppendingPathComponent:@"iPhoneOS.platform"
                                                                isDirectory:YES];
                if ([platforms containsObject:macOS]) {
                    [sdkRoots addObjectsFromArray:getSDKPathsForPlatform(macOS)];
                    [platforms removeObject:macOS];
                }
                if ([platforms containsObject:iphoneOS]) {
                    [sdkRoots addObjectsFromArray:getSDKPathsForPlatform(iphoneOS)];
                    [platforms removeObject:iphoneOS];
                }
                for (NSURL *plat in platforms) {
                    if ([[plat pathExtension] isEqual:@"platform"])
                        [sdkRoots addObjectsFromArray:getSDKPathsForPlatform(plat)];
                }
                [platforms release];

                // Convert SDK NSURL paths to NSString paths
                NSMutableArray *sdkPaths = [NSMutableArray array];
                for (NSURL *u in sdkRoots)
                    [sdkPaths addObject:[u path]];
                [searchRoots addObjectsFromArray:sdkPaths];
            } else {
                NSString *warn = [NSString stringWithFormat:
                    @"Warning: Xcode platforms folder not found at \"%@\". "
                     "You may have invalid DEVELOPER_DIR or stale xcode-select setting.",
                    developerDir];
                fputs([warn UTF8String], stderr);
                fputc('\n', stderr);
            }
        }

        HeaderOpenState *state = [[[HeaderOpenState alloc]
            initWithRemainingHeaders:[NSMutableArray arrayWithArray:fileArgs]]
            autorelease];
        [state performFastPathSearch];

        if (!state.finished) {
            for (id root in searchRoots) {
                if ([root hasSuffix:@"Frameworks"])
                    scanFrameworksDirectory(root, state);
                else
                    scanHeadersDirectory(root, state);
                if (state.finished) break;
            }
        }

        NSDictionary *headerMap = [state headersToHeaderPaths];

        // Identify headers for which nothing was found
        NSMutableArray *notFound = [NSMutableArray array];
        for (NSString *h in fileArgs)
            if (![[headerMap objectForKey:h] count])
                [notFound addObject:h];

        if (notFound.count) {
            NSString *plural = notFound.count == 1 ? @"" : @"s";
            NSString *list   = joinArrayWithConjunction(notFound, @"or");
            dieWithError([NSString stringWithFormat:
                @"Unable to find header file%@ matching %@", plural, list]);
        }

        // For each requested header prompt if multiple matches
        NSMutableArray *chosen = [NSMutableArray array];
        NSCharacterSet *sepSet = [[NSCharacterSet
            whitespaceAndNewlineCharacterSet] mutableCopy];
        [(NSMutableCharacterSet *)sepSet addCharactersInString:@","];
        NSCharacterSet *immutable = [sepSet copy];
        [sepSet release];

        for (NSString *h in fileArgs) {
            NSArray *hits = headerMap[h];
            if (hits.count == 1) {
                [chosen addObject:hits[0]];
                continue;
            }
            printf("%s?\n", [h UTF8String]);
            puts("[0]\tcancel");
            puts("[1]\tall");
            putchar('\n');
            for (NSUInteger idx = 0; idx < hits.count; ++idx)
                printf("[%lu]\t%s\n", (unsigned long)(idx + 2), [hits[idx] UTF8String]);

            printf("\nWhich header(s) for \"%s\"? ", [h UTF8String]);
            fflush(stdout);

            NSMutableArray *selected = [NSMutableArray array];
            int count2 = 0;
            while (count2 < 1) {
                char lineBuf[1024];
                bzero(lineBuf, sizeof(lineBuf));
                if (!fgets(lineBuf, sizeof(lineBuf), stdin))
                    dieWithError(@"Cancelled.");
                // consume rest of line
                while (!strchr(lineBuf, '\n') && fgets(lineBuf, sizeof(lineBuf), stdin))
                    ;
                NSString *line = [NSString stringWithUTF8String:lineBuf];
                if (!line) break;
                NSScanner *sc = [NSScanner scannerWithString:line];
                [sc setCharactersToBeSkipped:immutable];
                count2 = 0;
                while (![sc isAtEnd]) {
                    int val = -1;
                    if (![sc scanInt:&val]) break;
                    ++count2;
                    if (val == 1) {
                        [selected addObjectsFromArray:hits];
                    } else if (val == 0) {
                        gCancelled = YES;
                        break;
                    } else if (val < 2 || (NSUInteger)val >= hits.count + 2) {
                        NSString *msg = [NSString stringWithFormat:
                            @"Please enter values in the range 0 through %lu",
                            (unsigned long)(hits.count + 1)];
                        fputs([msg UTF8String], stderr);
                        fputc('\n', stderr);
                        [sc setScanLocation:line.length];
                        count2 = 0;
                    } else {
                        [selected addObject:hits[val - 2]];
                    }
                }
            }
            if (count2 >= 1)
                [chosen addObjectsFromArray:selected];
        }
        [immutable release];

        // Deduplicate preserving order
        NSMutableArray *deduped = [NSMutableArray array];
        NSMutableSet   *seen    = [NSMutableSet set];
        for (id obj in chosen) {
            if (![seen member:obj]) {
                [seen addObject:obj];
                [deduped addObject:obj];
            }
        }
        fileArgs = deduped;
    } // end header mode

    // ── Convert fileArgs strings to URLs ────────────────────────────────────
    for (NSString *arg in fileArgs) {
        NSURL *url = nil;

        if (![arg containsString:@":"]) {
            url = [NSURL fileURLWithPath:arg];
        } else {
            BOOL treatAsFilePath = NO;
            // Check if the scheme part looks like a URL scheme
            BOOL looksLikeURL = NO;
            if (arg.length >= 2) {
                unichar first = [arg characterAtIndex:0];
                if ((first <= 0x7F
                     ? (_DefaultRuneLocale.__runetype[first] & 0x100) != 0
                     : (bool)__maskrune(first, 256))) {
                    // walk characters checking for scheme validity until ':'
                    NSUInteger j = 2;
                    while (j <= arg.length) {
                        unichar c = [arg characterAtIndex:j - 1];
                        if (c == ':') { looksLikeURL = YES; break; }
                        BOOL alpha = (c <= 0x7F)
                            ? ((_DefaultRuneLocale.__runetype[c] & 0x100) != 0)
                            : (bool)__maskrune(c, 256);
                        BOOL digit = (c >= '0' && c <= '9');
                        BOOL special = (c == '+' || c == '-' || c == '.');
                        if (!alpha && !digit && !special)
                            break;
                        if (j++ >= arg.length) break;
                    }
                }
            }

            if (!looksLikeURL) {
                treatAsFilePath = YES;
            } else {
                // Extract scheme (up to first ':') and check if LS knows it
                NSUInteger colonIdx = [arg rangeOfString:@":"].location;
                NSString *schemeStr = [arg substringToIndex:colonIdx + 1];
                NSURL *schemeURL = [NSURL URLWithString:schemeStr];
                if (schemeURL && ![schemeURL isFileURL]) {
                    CFURLRef defaultApp = LSCopyDefaultApplicationURLForURL(
                        (__bridge CFURLRef)schemeURL, 0xFFFFFFFF, NULL);
                    if (defaultApp) {
                        CFRelease(defaultApp);
                        // It's a valid non-file URL scheme – build the full URL
                        NSURL *candidate = [NSURL URLWithString:arg];
                        if (candidate) {
                            url = candidate;
                        } else {
                            // Percent-encode characters not in RFC-compliant set
                            NSMutableString *enc = [NSMutableString stringWithString:arg];
                            NSCharacterSet *allowed = [NSCharacterSet
                                characterSetWithCharactersInString:
                                    @"ABCDEFGHIJKLMNOPQRSTUVWYXZabcdefghijklmnopqrstuvwxyz"
                                     "0123456789;/?:@&=+$,-_.!~*'()%"];
                            for (NSInteger k = (NSInteger)enc.length - 1; k >= 0; --k) {
                                unichar c = [enc characterAtIndex:(NSUInteger)k];
                                if (![allowed characterIsMember:c]) {
                                    NSAutoreleasePool *inner = [[NSAutoreleasePool alloc] init];
                                    NSString *sub = [enc substringWithRange:
                                        NSMakeRange((NSUInteger)k, 1)];
                                    NSString *encoded = [sub
                                        stringByAddingPercentEncodingWithAllowedCharacters:
                                            [NSCharacterSet new]];
                                    [enc replaceCharactersInRange:NSMakeRange((NSUInteger)k, 1)
                                                      withString:encoded];
                                    [inner release];
                                }
                            }
                            url = [NSURL URLWithString:enc];
                        }
                    }
                }
            }

            if (treatAsFilePath) {
                url = [NSURL fileURLWithPath:arg];
            } else if (!url) {
                url = [NSURL URLWithString:arg];
            }

            if (![[url scheme] isEqual:@"file"]
                && [[NSFileManager defaultManager] fileExistsAtPath:arg]) {
                if (gTextEdit || gDefaultTextEditor || gReveal) {
                    url = [NSURL fileURLWithPath:arg];
                } else {
                    NSURL *fileURL = [NSURL fileURLWithPath:arg];
                    printf("%s?\n", [arg UTF8String]);
                    puts("[0]\tcancel");
                    printf("[1]\tOpen the file %s\n",
                           [arg fileSystemRepresentation]);
                    printf("[2]\tOpen the URL  %s\n",
                           [[url absoluteString] UTF8String]);
                    printf("\nWhich did you mean? ");
                    fflush(stdout);
                    int choice = 0;
                    scanf(" %d", &choice);
                    char drain[1024]; bzero(drain, sizeof(drain));
                    while (!strchr(drain, '\n') && fgets(drain, sizeof(drain), stdin))
                        ;
                    if (choice == 0 || choice > 2)
                        dieWithError(@"Cancelled.");
                    if (choice == 1)
                        url = fileURL;
                }
            }
        }

        if (!url) {
            dieWithError([NSString stringWithFormat:
                @"Unable to interpret '%@' as a path or URL", arg]);
        }
        [pendingURLs addObject:url];
    }

    // ── Validate that file:// URLs with empty paths are reported ─────────────
    NSMutableArray *badURLs = [NSMutableArray array];
    for (NSURL *u in pendingURLs)
        if ([u isFileURL] && ![[u path] length])
            [badURLs addObject:[u absoluteString]];

    if (badURLs.count) {
        NSUInteger n     = badURLs.count;
        NSString  *list  = joinArrayWithConjunction(badURLs, @"and");
        NSString  *hint  = @"";
        if (fileArgs.count == 1) {
            NSString *arg = fileArgs[0];
            if ([arg hasPrefix:@"file://"] && ![arg hasPrefix:@"file:///"])
                hint = [NSString stringWithFormat:@"\nPerhaps you meant '%@'?",
                    [@"file:///" stringByAppendingString:
                        [arg substringFromIndex:[@"file://" length]]]];
        }
        dieWithError([NSString stringWithFormat:
            @"The URL%s %@ do%s not refer to a file.%@",
            n == 1 ? "" : "s", list,
            n == 1 ? "es" : "",
            hint]);
    }

    // ── Check all file:// URLs exist ─────────────────────────────────────────
    checkFilesExistForArguments(pendingURLs, fileArgs);

    // ── Standardise file:// URL paths ────────────────────────────────────────
    NSMutableArray *allURLs = [NSMutableArray array]; // -u URLs + file URLs
    for (NSURL *u in pendingURLs) {
        NSURL *final;
        if ([u isFileURL]) {
            NSString *std = [[u path] stringByStandardizingPath];
            final = std ? [NSURL fileURLWithPath:std] : u;
        } else {
            final = nil;
        }
        [allURLs addObject:final ?: u];
    }
    [allURLs addObjectsFromArray:extraURLs];

    // ── Resolve target bundle ID to an app URL if no explicit -a ─────────────
    NSURL *resolvedAppURL = appURL; // may have been set by -t

    if (!resolvedAppURL && !appName && targetBundleID) {
        CFArrayRef apps = LSCopyApplicationURLsForBundleIdentifier(
            (__bridge CFStringRef)targetBundleID, NULL);
        NSURL *first = [(__bridge NSArray *)apps firstObject];
        if (first) {
            resolvedAppURL = [[first retain] autorelease];
            CFRelease(apps);
        } else {
            if (apps) CFRelease(apps);
            dieWithError([NSString stringWithFormat:
                @"LSCopyApplicationURLsForBundleIdentifier() failed while trying to "
                 "determine the application with bundle identifier %@.", targetBundleID]);
        }
    }

    // ── -a: look up by application name ──────────────────────────────────────
    if (!resolvedAppURL && appName) {
        NSString *path = [[NSWorkspace sharedWorkspace]
            fullPathForApplication:appName];
        if (!path) {
            dieWithError([NSString stringWithFormat:
                @"Unable to find application named '%@'", appName]);
        }
        resolvedAppURL = [NSURL fileURLWithPath:path];
    }

    // ── Guard: must have something to open ───────────────────────────────────
    if ((!gCancelled || !allURLs.count)
        && !resolvedAppURL
        && !fileArgs.count
        && !allURLs.count) {
        goto usage;
    }

    // ── -R: reveal in Finder ──────────────────────────────────────────────────
    if (gReveal) {
        NSMutableArray *failed = [NSMutableArray array];
        NSWorkspace    *ws     = [NSWorkspace sharedWorkspace];
        NSFileManager  *fm     = [NSFileManager defaultManager];
        for (NSURL *u in allURLs) {
            NSString *path = [u path];
            BOOL isDir     = NO;
            if (![fm fileExistsAtPath:path isDirectory:&isDir]
                || ![ws selectFile:path inFileViewerRootedAtPath:@"/"])
                [failed addObject:u];
        }
        if (!failed.count) exit(0);
        NSString *list = joinArrayWithConjunction(
            mapArrayWithSelector(failed, @selector(path)), @"and");
        dieWithError([NSString stringWithFormat:
            @"Unable to reveal file%s %@.",
            failed.count == 1 ? "" : "s", list]);
    }

    // ── Build LS open options ─────────────────────────────────────────────────
    NSMutableDictionary *lsOpts = [NSMutableDictionary dictionary];
    lsOpts[_kLSOpenOptionWaitForApplicationToCheckInKey] = @NO;
    lsOpts[_kLSOpenOptionHideKey]      = gHideApp     ? @YES : @NO;
    lsOpts[_kLSOpenOptionActivateKey]  = gBackground  ? @NO  : @YES;
    lsOpts[_kLSOpenOptionAddToRecentsKey] = gExcludeFromRecents ? @NO : @YES;

    if (appArgs)
        lsOpts[_kLSOpenOptionArgumentsKey] = appArgs;
    if ([gEnvVars count])
        lsOpts[_kLSOpenOptionEnvironmentVariablesKey] = gEnvVars;

    if (gFresh) {
        lsOpts[_kLSOpenOptionAEParamKeyKey]  =
            [NSNumber numberWithInteger:0x72657661 /* 'reva' */];
        lsOpts[_kLSOpenOptionAEParamDescKey] =
            [NSAppleEventDescriptor descriptorWithEnumCode:0x6E6E6F6E /* 'nnon' */];
    }
    if (gStdinURL)  lsOpts[_kLSOpenOptionLaunchStdInPathKey]  = gStdinURL;
    if (gStdoutURL) lsOpts[_kLSOpenOptionLaunchStdOutPathKey] = gStdoutURL;
    if (gStderrURL) lsOpts[_kLSOpenOptionLaunchStdErrPathKey] = gStderrURL;

    if (gNewInstance || resolvedAppURL) {
        lsOpts[_kLSOpenOptionPreferRunningInstanceKey] =
            [NSNumber numberWithInteger:gNewInstance ? 0 : 2];
    }

    // ── Build app→urls mapping ────────────────────────────────────────────────
    // If an explicit app was specified, map all URLs under it.
    // Otherwise, ask LS what app handles each URL and group by app.
    NSMutableDictionary *appToURLs = [NSMutableDictionary new];

    if (resolvedAppURL) {
        appToURLs[resolvedAppURL] =
            [NSMutableArray arrayWithArray:allURLs];
    } else {
        for (NSURL *url in allURLs) {
            if (!url) continue;
            // Check for symlinks
            id effectiveURL = url;
            id isSymlink = nil;
            if ([url getResourceValue:&isSymlink forKey:NSURLIsSymbolicLinkKey error:nil]
                && [isSymlink boolValue])
                effectiveURL = [url URLByResolvingSymlinksInPath];

            // Check if it's an application bundle
            id isApp = nil;
            if ([effectiveURL getResourceValue:&isApp forKey:NSURLIsApplicationKey error:nil]
                && [isApp boolValue]) {
                if (!appToURLs[url])
                    appToURLs[url] = [NSMutableArray array];
                if (!lsOpts[_kLSOpenOptionPreferRunningInstanceKey])
                    lsOpts[_kLSOpenOptionPreferRunningInstanceKey] =
                        [NSNumber numberWithInteger:2];
                continue;
            }

            // Resolve aliases (up to 16 levels)
            NSURL *resolved = url;
            for (int depth = 16; depth >= 1; --depth) {
                id isAlias = nil;
                if (![resolved getResourceValue:&isAlias
                                         forKey:NSURLIsAliasFileKey
                                          error:nil]
                    || !isAlias || ![isAlias boolValue])
                    break;
                NSURL *target = [NSURL URLByResolvingAliasFileAtURL:resolved
                                                            options:768
                                                              error:nil];
                if (!target) {
                    dieWithError([NSString stringWithFormat:
                        @"Unable to resolve alias file %@ (%@).", resolved, nil]);
                }
                resolved = target;
                if (depth < 2) break;
            }

            char realBuf[PATH_MAX];
            CFErrorRef cfErr = NULL;
            NSURL *appForURL = nil;

            if ([resolved isFileURL]) {
                if (!realpath([resolved fileSystemRepresentation], realBuf)) {
                    appForURL = nil;
                    goto map_url;
                }
                NSURL *canonURL = [[[NSURL alloc]
                    initFileURLWithFileSystemRepresentation:realBuf
                                                isDirectory:NO
                                                relativeToURL:nil] autorelease];
                if (!canonURL) {
                    appForURL = nil;
                    goto map_url;
                }
                LSRolesMask roles = LSGetOpenRoles();
                CFURLRef cf = LSCopyDefaultApplicationURLForURL(
                    (__bridge CFURLRef)canonURL, roles, &cfErr);
                appForURL = [(NSURL *)cf autorelease];

                if (!appForURL) {
                    if (![[NSFileManager defaultManager]
                          fileExistsAtPath:[NSString stringWithCString:realBuf
                                                              encoding:NSUTF8StringEncoding]]) {
                        dieWithError([NSString stringWithFormat:
                            @"The URL %@ does not refer to a file which exists.",
                            resolved]);
                    }
                }
            } else {
                LSRolesMask roles = LSGetOpenRoles();
                CFURLRef cf = LSCopyDefaultApplicationURLForURL(
                    (__bridge CFURLRef)resolved, roles, &cfErr);
                appForURL = [(NSURL *)cf autorelease];
            }

map_url:
            if (!appForURL) {
                dieWithError([NSString stringWithFormat:
                    @"No application knows how to open URL %@ (%@).",
                    resolved,
                    cfErr ? (__bridge id)cfErr : nil]);
            }
            if (appToURLs[appForURL]) {
                [appToURLs[appForURL] addObject:url];
            } else {
                appToURLs[appForURL] =
                    [NSMutableArray arrayWithObject:url];
            }
            if (cfErr) CFRelease(cfErr);
        }
    }

    // ── Dispatch _LSOpenURLsWithCompletionHandler for each app ───────────────
    NSMutableArray *waitList = gWait ? [NSMutableArray new] : nil;
    dispatch_group_t group   = dispatch_group_create();

    [appToURLs enumerateKeysAndObjectsUsingBlock:
        ^(NSURL *key, NSArray *urls, BOOL *stop) {
            dispatch_group_enter(group);
            NSArray *urlsToOpen = urls ?: @[];
            _LSOpenURLsWithCompletionHandler((CFArrayRef)urlsToOpen,
                                             (CFURLRef)key,
                                             (CFDictionaryRef)lsOpts,
                ^(LSASNRef app, Boolean alreadyRunning, CFErrorRef errorRef) {
                    NSError *error = (NSError *)errorRef;
                    if (error) {
                        NSString *forWhat = @"";
                        if ([urlsToOpen count]) {
                            const char *fileOrURL = "file";
                            SEL selector = @selector(path);
                            for (NSURL *url in urlsToOpen) {
                                if (![url isFileURL]) {
                                    fileOrURL = "URL";
                                    selector = @selector(absoluteString);
                                    break;
                                }
                            }

                            NSArray *descs = mapArrayWithSelector(urlsToOpen, selector);
                            forWhat = [NSString stringWithFormat:@" for %@ %@",
                                [NSString stringWithFormat:@"the %s%s",
                                    fileOrURL,
                                    [urlsToOpen count] == 1 ? "" : "s"],
                                joinArrayWithConjunction(descs, @"and")];
                        }

                        NSString *forApp = key
                            ? [@" " stringByAppendingString:[key path]]
                            : @"";

                        if ([error.domain isEqualToString:(__bridge NSString *)kCFErrorDomainOSStatus]) {
                            CFIndex code = CFErrorGetCode((__bridge CFErrorRef)error);
                            switch (code) {
                                case -10827:
                                    dieWithError([NSString stringWithFormat:
                                        @"The application%@ cannot be opened because its executable is missing.",
                                        forApp]);
                                case -10661:
                                    dieWithError([NSString stringWithFormat:
                                        @"The application%@ cannot be opened because it has an incorrect executable format.",
                                        forApp]);
                                case -10660:
                                    dieWithError([NSString stringWithFormat:
                                        @"The application%@ cannot be opened because it is in the Trash.",
                                        forApp]);
                                case -43:
                                    checkFilesExistForArguments(urlsToOpen, fileArgs);
                                    dieWithError([NSString stringWithFormat:
                                        @"Some files were not found%@.", forWhat]);
                                case -35: {
                                    NSString *nfs = @"";
                                    if ([urlsToOpen count] == 1
                                        && ![[[[urlsToOpen objectAtIndex:0] path] lowercaseString]
                                             hasPrefix:@"/dev"]) {
                                        nfs = @" Perhaps it is a stale NFS handle.";
                                    }
                                    dieWithError([NSString stringWithFormat:
                                        @"The volume does not exist%@.%@", forWhat, nfs]);
                                }
                                default: {
                                    NSString *forAppPhrase = [forApp length]
                                        ? [@" for the application" stringByAppendingString:forApp]
                                        : @"";
                                    dieWithError([NSString stringWithFormat:
                                        @"%@() failed%@ with error %ld%@.",
                                        @"_LSOpenURLsWithCompletionHandler",
                                        forAppPhrase,
                                        (long)code,
                                        forWhat]);
                                }
                            }
                        } else if ([error.domain isEqualToString:NSPOSIXErrorDomain]) {
                            dieWithError([NSString stringWithFormat:
                                @"The application%@ cannot be opened, error=%@",
                                forApp, error]);
                        } else {
                            dieWithError([NSString stringWithFormat:
                                @"The application%@ cannot be opened for an unexpected reason, error=%@",
                                forApp, error]);
                        }
                    } else {
                        if (app && waitList) {
                            @synchronized(waitList) { [waitList addObject:(id)app]; }
                        }
                        if (!alreadyRunning) {
                            const char *msg = NULL;
                            if ([gEnvVars count]) {
                                if (gStdinURL || gStdoutURL || gStderrURL) {
                                    msg = [[NSString stringWithFormat:
                                        @"Application %@ was already running and so the additional environment variables and redirected stdin/stdout/stderr provided could not be set.",
                                        [key path]] UTF8String];
                                } else {
                                    msg = [[NSString stringWithFormat:
                                        @"Application %@ was already running and so the additional environment variables could not be set.",
                                        [key path]] UTF8String];
                                }
                            } else if (gStdinURL || gStdoutURL || gStderrURL) {
                                msg = [[NSString stringWithFormat:
                                    @"Application %@ was already running and so the redirected stdin/stdout/stderr provided could not be set",
                                    [key path]] UTF8String];
                            }
                            if (msg) {
                                fputs(msg, stderr);
                                fputc('\n', stderr);
                            }
                        }
                    }
                    dispatch_group_leave(group);
                });
        }];

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    dispatch_release(group);

    // ── -W: wait for all launched applications to exit ───────────────────────
    if (gWait && waitList) {
        if (waitList.count) {
            // Collect unique PSNs
            ProcessSerialNumber *psnArray =
                calloc(waitList.count, sizeof(ProcessSerialNumber));
            __block int psnCount = 0;

            [waitList enumerateObjectsUsingBlock:
                ^(id app, NSUInteger idx, BOOL *stop) {
                    _LSASNExtractHighAndLowParts((LSASNRef)app,
                                                &psnArray[psnCount].highLongOfPSN,
                                                &psnArray[psnCount].lowLongOfPSN);
                    ++psnCount;
                }];

            // Deduplicate and resolve to PIDs
            pid_t *pids    = calloc((size_t)psnCount, sizeof(pid_t));
            NSMutableSet *seen = [[NSMutableSet alloc] init];
            int pidCount = 0;

            for (int k = 0; k < psnCount; ++k) {
                NSNumber *key = [NSNumber numberWithUnsignedLongLong:
                    (uint64_t)psnArray[k].lowLongOfPSN
                    | ((uint64_t)psnArray[k].highLongOfPSN << 32)];
                if ([seen containsObject:key]) continue;
                OSStatus err = GetProcessPID(&psnArray[k], &pids[pidCount]);
                if (err) {
                    const char *msg = [[NSString stringWithFormat:
                        @"Unable to block on application (GetProcessPID() returned %lu)",
                        (unsigned long)err] UTF8String];
                    fputs(msg, stderr); fputc('\n', stderr);
                } else {
                    ++pidCount;
                }
                [seen addObject:key];
            }
            [seen release];
            free(psnArray);

            if (pidCount >= 1) {
                [pool release];
                pool = [[NSAutoreleasePool alloc] init];

                struct kevent *kevents = calloc((size_t)pidCount, sizeof(struct kevent));
                int kq = kqueue();
                if (!kq) {
                    int e = errno;
                    dieWithError([NSString stringWithFormat:
                        @"Unable to block on applications (kqueue() failed: %s)",
                        strerror(e)]);
                }
                for (int k = 0; k < pidCount; ++k) {
                    kevents[k].ident  = (uintptr_t)pids[k];
                    kevents[k].filter = EVFILT_PROC;
                    kevents[k].flags  = EV_ADD | EV_ENABLE;
                    kevents[k].fflags = NOTE_EXIT;
                    kevents[k].data   = 0;
                    kevents[k].udata  = 0;
                }
                if (kevent(kq, kevents, pidCount, NULL, 0, NULL) == -1) {
                    int e = errno;
                    dieWithError([NSString stringWithFormat:
                        @"Unable to block on applications (initial call to kevent() failed: %s)",
                        strerror(e)]);
                }
                int remaining = pidCount;
                while (remaining > 0) {
                    int fired = kevent(kq, NULL, 0, kevents, pidCount, NULL);
                    if (fired == -1) {
                        int e = errno;
                        dieWithError([NSString stringWithFormat:
                            @"Unable to block on applications (call to kevent() failed: %s)",
                            strerror(e)]);
                    }
                    remaining -= fired;
                }
                free(kevents);
                close(kq);
            }
            free(pids);
        }
        [waitList release];
    }

    [appToURLs release];
    [pool release];
    return 0;

usage:
    fprintf(stderr,
        "Usage: %s [-e] [-t] [-f] [-W] [-R] [-n] [-g] [-h] [-s <partial SDK name>]"
        "[-b <bundle identifier>] [-a <application>] [-u URL] [filenames] [--args arguments]\n"
        "Help: Open opens files from a shell.\n"
        "      By default, opens each file using the default application for that file.  \n"
        "      If the file is in the form of a URL, the file will be opened as a URL.\n"
        "Options: \n"
        "      -a                    Opens with the specified application.\n"
        "      -b                    Opens with the specified application bundle identifier.\n"
        "      -e                    Opens with TextEdit.\n"
        "      -t                    Opens with default text editor.\n"
        "      -f                    Reads input from standard input and opens with TextEdit.\n"
        "      -F  --fresh           Launches the app fresh, that is, without restoring windows."
        " Saved persistent state is lost, excluding Untitled documents.\n"
        "      -R, --reveal          Selects in the Finder instead of opening.\n"
        "      -W, --wait-apps       Blocks until the used applications are closed"
        " (even if they were already running).\n"
        "          --args            All remaining arguments are passed in argv to the"
        " application's main() function instead of opened.\n"
        "      -n, --new             Open a new instance of the application even if one"
        " is already running.\n"
        "      -j, --hide            Launches the app hidden.\n"
        "      -g, --background      Does not bring the application to the foreground.\n"
        "      -h, --header          Searches header file locations for headers matching"
        " the given filenames, and opens them.\n"
        "      -s                    For -h, the SDK to use; if supplied, only SDKs whose"
        " names contain the argument value are searched.\n"
        "                            Otherwise the highest versioned SDK in each platform"
        " is used.\n"
        "      -u, --url URL         Open this URL, even if it matches exactly a filepath\n"
        "      -i, --stdin  PATH     Launches the application with stdin connected to PATH;"
        " defaults to /dev/null\n"
        "      -o, --stdout PATH     Launches the application with /dev/stdout connected to PATH; \n"
        "          --stderr PATH     Launches the application with /dev/stderr connected to PATH to\n"
        "          --env    VAR      Add an enviroment variable to the launched process, where VAR"
        " is formatted AAA=foo or just AAA for a null string value.\n",
        "open");
    exit(1);
}
