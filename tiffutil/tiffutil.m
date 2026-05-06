#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>

#include <fcntl.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include <tiffio.h>

extern void tiffdump_file(int fd, uint64_t diroff);

#define DEFAULT_DPI 72.0
#define HIDPI_DPI 144.0
#define POINTS_MATCH_TOLERANCE 0.1
#define ALL_IMAGES (-1)
#define NO_COMPRESSION_OVERRIDE (-1)

typedef NS_ENUM(NSInteger, TIFFUtilOperation) {
    TIFFUtilOperationConvert,
    TIFFUtilOperationConcatenate,
    TIFFUtilOperationConcatenateHiDPI,
    TIFFUtilOperationExtract,
    TIFFUtilOperationInfo,
    TIFFUtilOperationVerboseInfo,
    TIFFUtilOperationFix,
    TIFFUtilOperationDump,
};

typedef NS_ENUM(NSInteger, TIFFUtilValidationMode) {
    TIFFUtilValidationNone,
    TIFFUtilValidationSameLogicalSize,
    TIFFUtilValidationAquaHiDPI,
    TIFFUtilValidationReport,
};

static void usageAndExit(const char *message) __attribute__((noreturn));

static void
usageAndExit(const char *message)
{
    if (message != NULL) {
        fprintf(stderr, "Error: %s", message);
    }

    fputs("Usage: tiffutil -none           infile                  [-out outfile]\n"
          "                -lzw            infile                  [-out outfile]\n"
          "                -packbits       infile                  [-out outfile]\n"
          "                -cat            infile1 [infile2 ...]   [-out outfile]\n"
          "                -catnosizecheck infile1 [infile2 ...]   [-out outfile]\n"
          "                -cathidpicheck  infile1 [infile2 ...]   [-out outfile]\n"
          "                -extract        num infile              [-out outfile]\n"
          "                -info           infile1 [infile2 ...]\n"
          "                -verboseinfo    infile1 [infile2 ...]\n"
          "                -dump           infile1 [infile2 ...]\n"
          "\n",
          stderr);
    exit(1);
}

static void
reconcileDpiWithPixelsPerMeter(double *dpi, double pixelsPerMeter)
{
    double pointsPerMeter;
    double roundedPointScale;
    double correctedDpi;
    double roundedPixelsPerMeter;

    if (pixelsPerMeter <= 0.0) {
        NSLog((NSString *)CFSTR("Invalid Given PPM (%g)"), pixelsPerMeter);
        return;
    }

    pointsPerMeter = pixelsPerMeter / 2834.645669291339;
    roundedPointScale = roundf((float)pointsPerMeter);
    correctedDpi = roundedPointScale * DEFAULT_DPI;
    roundedPixelsPerMeter = roundf((float)(correctedDpi / 0.0254));
    if (roundedPixelsPerMeter != pixelsPerMeter) {
        return;
    }

    if (*dpi - correctedDpi <= 0.05) {
        *dpi = correctedDpi;
    } else {
        NSLog((NSString *)CFSTR("The Given DPI is wildly inconsistent from the Given PPM (correctionDelta: %g DPI)"),
              *dpi - correctedDpi);
    }
}

static void
updateDpiFromPngPixelsPerMeter(double *dpi, NSDictionary *pngProperties, CFStringRef key)
{
    NSNumber *value;

    if (pngProperties == nil) {
        return;
    }

    value = pngProperties[(__bridge NSString *)key];
    if (value != nil) {
        reconcileDpiWithPixelsPerMeter(dpi, [value doubleValue]);
    }
}

static void
extractImageMetricsAtIndex(CGImageSourceRef imageSource,
                           size_t index,
                           NSInteger *pixelHeight,
                           NSInteger *pixelWidth,
                           double *dpiHeight,
                           double *dpiWidth)
{
    NSDictionary *properties;
    NSNumber *value;
    NSDictionary *pngProperties;

    properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(imageSource, index, NULL));
    if (properties == nil) {
        *pixelHeight = 0;
        *pixelWidth = 0;
        *dpiHeight = DEFAULT_DPI;
        *dpiWidth = DEFAULT_DPI;
        return;
    }

    value = properties[(NSString *)kCGImagePropertyPixelHeight];
    *pixelHeight = value != nil ? [value integerValue] : 0;

    value = properties[(NSString *)kCGImagePropertyPixelWidth];
    *pixelWidth = value != nil ? [value integerValue] : 0;

    value = properties[(NSString *)kCGImagePropertyDPIHeight];
    *dpiHeight = value != nil ? [value doubleValue] : 0.0;

    value = properties[(NSString *)kCGImagePropertyDPIWidth];
    *dpiWidth = value != nil ? [value doubleValue] : 0.0;

    if (*dpiHeight == 0.0) {
        *dpiHeight = DEFAULT_DPI;
    }
    if (*dpiWidth == 0.0) {
        *dpiWidth = DEFAULT_DPI;
    }

    pngProperties = properties[(NSString *)kCGImagePropertyPNGDictionary];
    updateDpiFromPngPixelsPerMeter(dpiHeight, pngProperties, kCGImagePropertyPNGXPixelsPerMeter);
    updateDpiFromPngPixelsPerMeter(dpiWidth, pngProperties, kCGImagePropertyPNGYPixelsPerMeter);
}

static void
validateConcatenatedImageSourceSizes(NSArray *imageSources,
                                     const char **paths,
                                     TIFFUtilValidationMode validationMode)
{
    NSInteger baselinePixelHeight;
    NSInteger baselinePixelWidth;
    double baselineDpiHeight;
    double baselineDpiWidth;
    double baselinePointHeight;
    double baselinePointWidth;
    NSInteger sourceIndex;
    NSInteger totalFrameIndex;
    BOOL warned;

    if (validationMode == TIFFUtilValidationNone) {
        return;
    }

    baselinePixelHeight = 0;
    baselinePixelWidth = 0;
    baselineDpiHeight = 0.0;
    baselineDpiWidth = 0.0;
    baselinePointHeight = 0.0;
    baselinePointWidth = 0.0;
    totalFrameIndex = 0;
    warned = NO;

    for (sourceIndex = 0; sourceIndex < (NSInteger)[imageSources count]; sourceIndex++) {
        CGImageSourceRef imageSource;
        size_t frameCount;
        size_t frameIndex;

        imageSource = (__bridge CGImageSourceRef)[imageSources objectAtIndex:(NSUInteger)sourceIndex];
        frameCount = CGImageSourceGetCount(imageSource);
        if (frameCount == 0) {
            continue;
        }

        for (frameIndex = 0; frameIndex < frameCount; frameIndex++) {
            NSInteger pixelHeight;
            NSInteger pixelWidth;
            double dpiHeight;
            double dpiWidth;
            double pointHeight;
            double pointWidth;

            if (validationMode != TIFFUtilValidationReport &&
                frameIndex == 0 &&
                sourceIndex == 0) {
                extractImageMetricsAtIndex(imageSource,
                                           0,
                                           &baselinePixelHeight,
                                           &baselinePixelWidth,
                                           &baselineDpiHeight,
                                           &baselineDpiWidth);
                baselinePointHeight = (DEFAULT_DPI * (double)baselinePixelHeight) / baselineDpiHeight;
                baselinePointWidth = (DEFAULT_DPI * (double)baselinePixelWidth) / baselineDpiWidth;
                continue;
            }

            extractImageMetricsAtIndex(imageSource,
                                       frameIndex,
                                       &pixelHeight,
                                       &pixelWidth,
                                       &dpiHeight,
                                       &dpiWidth);
            pointHeight = (DEFAULT_DPI * (double)pixelHeight) / dpiHeight;
            pointWidth = (DEFAULT_DPI * (double)pixelWidth) / dpiWidth;

            switch (validationMode) {
            case TIFFUtilValidationNone:
                break;

            case TIFFUtilValidationSameLogicalSize:
                if (!warned &&
                    !(fabs(pointHeight - baselinePointHeight) <= POINTS_MATCH_TOLERANCE &&
                      pointWidth == baselinePointWidth)) {
                    warned = YES;
                    fputs("Warning: Sizes of concatenated images are not the same; this will lead to problems in choosing the appropriate image in some cases.\n",
                          stderr);
                }
                break;

            case TIFFUtilValidationAquaHiDPI:
                if (!warned) {
                    if (totalFrameIndex + (NSInteger)frameIndex <= 1 &&
                        dpiHeight == dpiWidth &&
                        baselineDpiHeight == baselineDpiWidth) {
                        if (dpiHeight == DEFAULT_DPI && baselineDpiHeight == DEFAULT_DPI) {
                            if (baselinePointHeight <= pointHeight) {
                                dpiHeight = HIDPI_DPI;
                                dpiWidth = HIDPI_DPI;
                                pointHeight = (DEFAULT_DPI * (double)pixelHeight) / HIDPI_DPI;
                                pointWidth = (DEFAULT_DPI * (double)pixelWidth) / HIDPI_DPI;
                            } else {
                                baselineDpiHeight = HIDPI_DPI;
                                baselineDpiWidth = HIDPI_DPI;
                                baselinePointHeight = (DEFAULT_DPI * (double)baselinePixelHeight) / HIDPI_DPI;
                                baselinePointWidth = (DEFAULT_DPI * (double)baselinePixelWidth) / HIDPI_DPI;
                            }
                        }

                        if (fabs(pointHeight - baselinePointHeight) <= POINTS_MATCH_TOLERANCE &&
                            fabs(pointWidth - baselinePointWidth) <= POINTS_MATCH_TOLERANCE) {
                            if (baselineDpiHeight == DEFAULT_DPI && dpiHeight == HIDPI_DPI) {
                                baselineDpiHeight = DEFAULT_DPI;
                                baselineDpiWidth = DEFAULT_DPI;
                                break;
                            }
                            if (baselineDpiHeight == HIDPI_DPI && dpiHeight == DEFAULT_DPI) {
                                baselineDpiHeight = HIDPI_DPI;
                                baselineDpiWidth = HIDPI_DPI;
                                break;
                            }
                        }
                    }

                    warned = YES;
                    fputs("Warning: Sizes of concatenated images do not follow Aqua guidelines for resolution independent multi-image TIFFs.\n",
                          stderr);
                    fputs("         Please provide two images, one with exactly twice the pixel width as the other.\n",
                          stderr);
                }
                break;

            case TIFFUtilValidationReport:
                fprintf(stderr,
                        " Image %ld in file %s: %gx%g points (%ldx%ld pixels, %gx%g dpi)\n",
                        (long)(frameIndex + 1),
                        paths[sourceIndex],
                        pointHeight,
                        pointWidth,
                        (long)pixelHeight,
                        (long)pixelWidth,
                        dpiHeight,
                        dpiWidth);
                break;
            }
        }

        totalFrameIndex += (NSInteger)frameCount;
    }

    if (warned) {
        validateConcatenatedImageSourceSizes(imageSources, paths, TIFFUtilValidationReport);
    }
}

static BOOL
imageIsSRGBCompatible(CGImageRef image)
{
    CGColorSpaceRef colorSpace;
    CGColorSpaceRef sRGBSpace;
    BOOL compatible;

    colorSpace = CGImageGetColorSpace(image);
    sRGBSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    compatible = YES;
    if (colorSpace != NULL && sRGBSpace != NULL) {
        compatible = CFEqual(colorSpace, sRGBSpace);
    }
    if (sRGBSpace != NULL) {
        CGColorSpaceRelease(sRGBSpace);
    }
    return compatible;
}

static void
copyImageSourceResolutionProperties(CGImageSourceRef imageSource, size_t index, NSMutableDictionary *properties)
{
    NSInteger pixelHeight;
    NSInteger pixelWidth;
    double dpiHeight;
    double dpiWidth;

    (void)pixelHeight;
    (void)pixelWidth;

    extractImageMetricsAtIndex(imageSource, index, &pixelHeight, &pixelWidth, &dpiHeight, &dpiWidth);
    [properties setObject:[NSNumber numberWithInteger:(NSInteger)dpiWidth] forKey:(id)kCGImagePropertyDPIWidth];
    [properties setObject:[NSNumber numberWithInteger:(NSInteger)dpiHeight] forKey:(id)kCGImagePropertyDPIHeight];
}

static NSInteger
appendImageSourceFramesToDestination(CGImageDestinationRef destination,
                                     CGImageSourceRef imageSource,
                                     const char *path,
                                     NSInteger compression,
                                     NSInteger selectedIndex,
                                     TIFFUtilOperation operation)
{
    NSMutableDictionary *properties;
    NSInteger imageCount;
    NSInteger writtenCount;

    properties = [NSMutableDictionary dictionary];
    imageCount = (NSInteger)CGImageSourceGetCount(imageSource);
    if (imageCount <= 0) {
        fprintf(stderr,
                "Error: Can't open %s. Either it isn't a TIFF file, or there are unrecognized tags; try tiffutil -dump for more info.\n",
                path);
    } else if (selectedIndex >= 0 && imageCount <= selectedIndex) {
        const char *plural;

        plural = imageCount >= 2 ? "s" : "";
        fprintf(stderr, "Error: %s has only %ld image%s.\n", path, (long)imageCount, plural);
    }

    if (compression != NO_COMPRESSION_OVERRIDE) {
        NSDictionary *tiffProperties;

        tiffProperties = [NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:compression]
                                                     forKey:(id)kCGImagePropertyTIFFCompression];
        [properties setObject:tiffProperties forKey:(id)kCGImagePropertyTIFFDictionary];
    }

    if (operation == TIFFUtilOperationConcatenateHiDPI) {
        const char *slash;
        const char *leafName;
        NSInteger dpi;
        NSString *imageDescription;
        NSString *software;
        NSMutableDictionary *tiffProperties;
        NSDictionary *hidpiProperties;

        slash = strrchr(path, '/');
        leafName = slash != NULL ? slash + 1 : path;
        dpi = strstr(leafName, "@2x") != NULL ? HIDPI_DPI : DEFAULT_DPI;

        imageDescription = [NSString stringWithFormat:@"%s", leafName];
        software = [NSString stringWithFormat:@"tiffutil v%.1f", TIFFUTIL_VERSION];
        tiffProperties = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                          [NSNumber numberWithInteger:COMPRESSION_LZW],
                          (id)kCGImagePropertyTIFFCompression,
                          nil];
        [tiffProperties setObject:imageDescription forKey:(id)kCGImagePropertyTIFFImageDescription];
        [tiffProperties setObject:software forKey:(id)kCGImagePropertyTIFFSoftware];

        hidpiProperties = [NSDictionary dictionaryWithObjectsAndKeys:
                           [NSNumber numberWithInteger:dpi],
                           (id)kCGImagePropertyDPIHeight,
                           [NSNumber numberWithInteger:dpi],
                           (id)kCGImagePropertyDPIWidth,
                           tiffProperties,
                           (id)kCGImagePropertyTIFFDictionary,
                           nil];
        [properties addEntriesFromDictionary:hidpiProperties];
    }

    writtenCount = 0;
    if (imageCount > 0) {
        NSInteger frameIndex;

        for (frameIndex = 0; frameIndex < imageCount; frameIndex++) {
            CGImageRef image;

            if (selectedIndex != ALL_IMAGES && selectedIndex != frameIndex) {
                continue;
            }

            image = CGImageSourceCreateImageAtIndex(imageSource, (size_t)frameIndex, NULL);
            if (operation != TIFFUtilOperationConcatenateHiDPI) {
                copyImageSourceResolutionProperties(imageSource, (size_t)frameIndex, properties);
            }
            CGImageDestinationAddImageFromSource(destination,
                                                 imageSource,
                                                 (size_t)frameIndex,
                                                 (__bridge CFDictionaryRef)properties);
            if (image != NULL) {
                (void)imageIsSRGBCompatible(image);
                CGImageRelease(image);
            }
            writtenCount++;
        }
    }

    return writtenCount;
}

static NSInteger
appendImageSourcesToDestination(CGImageDestinationRef destination,
                                NSArray *imageSources,
                                const char **paths,
                                NSInteger pathCount,
                                TIFFUtilOperation operation)
{
    NSInteger sourceIndex;
    NSInteger writtenCount;

    writtenCount = 0;
    for (sourceIndex = 0; sourceIndex < pathCount; sourceIndex++) {
        writtenCount += appendImageSourceFramesToDestination(destination,
                                                             (__bridge CGImageSourceRef)[imageSources objectAtIndex:(NSUInteger)sourceIndex],
                                                             paths[sourceIndex],
                                                             NO_COMPRESSION_OVERRIDE,
                                                             ALL_IMAGES,
                                                             operation);
    }
    return writtenCount;
}

static NSArray *
createImageSourcesFromPaths(const char **paths, NSInteger pathCount, size_t *countOut)
{
    NSMutableArray *imageSources;
    size_t totalCount;
    NSInteger pathIndex;

    imageSources = [NSMutableArray array];
    totalCount = 0;
    for (pathIndex = 0; pathIndex < pathCount; pathIndex++) {
        NSString *pathString;
        NSURL *fileURL;
        CGImageSourceRef imageSource;

        pathString = [NSString stringWithUTF8String:paths[pathIndex]];
        fileURL = [NSURL fileURLWithPath:pathString];
        if (fileURL == nil) {
            continue;
        }

        imageSource = CGImageSourceCreateWithURL((__bridge CFURLRef)fileURL, NULL);
        if (imageSource != NULL) {
            totalCount += CGImageSourceGetCount(imageSource);
            [imageSources addObject:(__bridge_transfer id)imageSource];
        } else {
            fprintf(stderr,
                    "Error: Failed to create image source for file %s. Either it isn't a TIFF file, or there are unrecognized tags; try tiffutil -dump for more info.\n",
                    paths[pathIndex]);
        }
    }

    if (countOut != NULL) {
        *countOut = totalCount;
    }
    return imageSources;
}

static int
printTiffInfoForPaths(const char **paths, NSInteger pathCount, BOOL verbose)
{
    NSInteger pathIndex;

    for (pathIndex = 0; pathIndex < pathCount; pathIndex++) {
        TIFF *tif;
        uint16_t directoryCount;
        uint16_t directoryIndex;

        if (pathCount >= 2) {
            fprintf(stdout, "*** %s\n", paths[pathIndex]);
        }

        tif = TIFFOpen(paths[pathIndex], "r");
        if (tif == NULL) {
            fprintf(stderr,
                    "Error: Can't open %s. Either it isn't readable, it isn't a TIFF file, or there are unrecognized tags; try tiffutil -dump for more info.\n",
                    paths[pathIndex]);
        } else {
            directoryCount = TIFFNumberOfDirectories(tif);
            for (directoryIndex = 0; directoryIndex < directoryCount; directoryIndex++) {
                if (directoryIndex != 0) {
                    TIFFSetDirectory(tif, directoryIndex);
                }
                TIFFPrintDirectory(tif, stdout, verbose ? 1 : 0);
            }
            TIFFClose(tif);
        }

        if (pathIndex + 1 != pathCount) {
            fputc('\n', stdout);
        }
    }

    return 1;
}

static int
dumpTiffFiles(const char **paths, NSInteger pathCount)
{
    NSInteger pathIndex;

    for (pathIndex = 0; pathIndex < pathCount; pathIndex++) {
        int fd;

        if (pathCount >= 2) {
            fprintf(stdout, "*** %s\n", paths[pathIndex]);
        }

        fd = open(paths[pathIndex], O_RDONLY, 0);
        if (fd < 0) {
            perror(paths[pathIndex]);
        } else {
            tiffdump_file(fd, 0);
            close(fd);
        }

        if (pathIndex + 1 != pathCount) {
            fputc('\n', stdout);
        }
    }

    return 1;
}

int
main(int argc, const char **argv)
{
    const char *command;
    NSInteger inputCount;
    const char **inputPaths;
    const char *outputPath;
    TIFFUtilOperation operation;
    NSInteger compression;
    NSInteger selectedImageIndex;
    NSInteger writtenCount;
    NSInteger failed;
    size_t totalImageCount;
    TIFFUtilValidationMode validationMode;
    NSArray *imageSources;
    NSMutableData *outputData;
    CGImageDestinationRef destination;

    inputCount = 0;
    selectedImageIndex = 0;
    if (argc <= 2) {
        usageAndExit(NULL);
    }

    @autoreleasepool {
        command = argv[1];
        inputCount = argc - 2;
        outputPath = "out.tiff";
        if (argc >= 5) {
            const char *tailOption;

            tailOption = argv[inputCount];
            if (strcmp(tailOption, "-out") == 0 || strcmp(tailOption, "-o") == 0) {
                outputPath = argv[argc - 1];
                inputCount = argc - 4;
            }
        }

        inputPaths = argv + 2;
        compression = COMPRESSION_NONE;
        operation = TIFFUtilOperationConvert;
        validationMode = TIFFUtilValidationNone;
        if (strcmp(command, "-none") == 0) {
            compression = COMPRESSION_NONE;
        } else if (strcmp(command, "-packbits") == 0) {
            compression = COMPRESSION_PACKBITS;
        } else if (strcmp(command, "-lzw") == 0) {
            compression = COMPRESSION_LZW;
        } else if (strcmp(command, "-jpeg") == 0) {
            fputs("TIFF Error: JPEG-compressed TIFF output is no longer supported.\n"
                  "No output file created due to errors.\n",
                  stderr);
            return 5;
        } else if (strcmp(command, "-g3") == 0) {
            compression = COMPRESSION_CCITTFAX3;
        } else if (strcmp(command, "-g4") == 0) {
            compression = COMPRESSION_CCITTFAX4;
        } else if (strcmp(command, "-catnosizecheck") == 0) {
            operation = TIFFUtilOperationConcatenate;
        } else if (strcmp(command, "-cat") == 0) {
            operation = TIFFUtilOperationConcatenate;
            validationMode = TIFFUtilValidationSameLogicalSize;
        } else if (strcmp(command, "-cathidpicheck") == 0) {
            operation = TIFFUtilOperationConcatenateHiDPI;
            validationMode = TIFFUtilValidationAquaHiDPI;
        } else if (strcmp(command, "-fix") == 0) {
            operation = TIFFUtilOperationFix;
        } else if (strcmp(command, "-extract") == 0) {
            long extractedIndex;

            operation = TIFFUtilOperationExtract;
            extractedIndex = 0;
            if (sscanf(inputPaths[0], "%ld", &extractedIndex) != 1) {
                usageAndExit("Image number to be extracted expected.\n");
            }
            selectedImageIndex = (NSInteger)extractedIndex;
            inputCount -= 1;
            if (inputCount == 0) {
                usageAndExit("Input file name expected.\n");
            }
            inputPaths = argv + 3;
        } else if (strcmp(command, "-dump") == 0) {
            operation = TIFFUtilOperationDump;
        } else if (strcmp(command, "-verboseinfo") == 0) {
            operation = TIFFUtilOperationVerboseInfo;
        } else if (strcmp(command, "-info") == 0 || strcmp(command, "-i") == 0) {
            operation = TIFFUtilOperationInfo;
        } else {
            usageAndExit("No valid command provided.\n");
        }

        if ((compression == COMPRESSION_NONE ||
             compression == COMPRESSION_CCITTFAX3 ||
             compression == COMPRESSION_CCITTFAX4 ||
             compression == COMPRESSION_LZW ||
             compression == COMPRESSION_PACKBITS) &&
            strncmp(inputPaths[0], "-f", 2) == 0) {
            long factor;

            factor = 0;
            if (sscanf(inputPaths[0] + 2, "%ld", &factor) != 1) {
                usageAndExit("Compression factor expected.\n");
            }
            inputCount -= 1;
            if (inputCount == 0) {
                usageAndExit("Input file name expected.\n");
            }
            inputPaths = argv + 3;
        }

        if (operation != TIFFUtilOperationConcatenate &&
            operation != TIFFUtilOperationConcatenateHiDPI &&
            operation != TIFFUtilOperationInfo &&
            operation != TIFFUtilOperationVerboseInfo &&
            operation != TIFFUtilOperationDump &&
            inputCount != 1) {
            usageAndExit("One input file name expected.\n");
        }

        if (operation == TIFFUtilOperationInfo ||
            operation == TIFFUtilOperationVerboseInfo ||
            operation == TIFFUtilOperationDump) {
            if (outputPath != NULL && strcmp(outputPath, "out.tiff") != 0) {
                usageAndExit("Can't specify output file name for -info, -verboseinfo, or -dump.\n");
            }
            outputPath = NULL;
        }

        imageSources = nil;
        outputData = nil;
        destination = NULL;
        totalImageCount = 0;
        if (outputPath != NULL) {
            imageSources = createImageSourcesFromPaths(inputPaths, inputCount, &totalImageCount);
            if ((operation == TIFFUtilOperationConcatenate ||
                 operation == TIFFUtilOperationConcatenateHiDPI) &&
                validationMode != TIFFUtilValidationNone) {
                validateConcatenatedImageSourceSizes(imageSources, inputPaths, validationMode);
            } else if (operation == TIFFUtilOperationExtract) {
                totalImageCount = 1;
            }

            outputData = CFBridgingRelease(CFDataCreateMutable(NULL, 0));
            if (outputData == nil) {
                fputs("Error: Failed to create output buffer.\n", stderr);
                exit(5);
            }

            destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)outputData,
                                                           CFSTR("public.tiff"),
                                                           totalImageCount,
                                                           NULL);
            if (destination == NULL) {
                fputs("Error: Failed to create CGImageDestination.\n", stderr);
                exit(5);
            }
        }

        writtenCount = 0;
        failed = 0;
        switch (operation) {
        case TIFFUtilOperationConvert:
            writtenCount = appendImageSourceFramesToDestination(destination,
                                                                (__bridge CGImageSourceRef)[imageSources objectAtIndex:0],
                                                                inputPaths[0],
                                                                compression,
                                                                ALL_IMAGES,
                                                                TIFFUtilOperationConvert);
            failed = writtenCount == 0;
            break;

        case TIFFUtilOperationConcatenate:
        case TIFFUtilOperationConcatenateHiDPI:
            writtenCount = appendImageSourcesToDestination(destination, imageSources, inputPaths, inputCount, operation);
            failed = writtenCount == 0;
            break;

        case TIFFUtilOperationExtract:
            writtenCount = appendImageSourceFramesToDestination(destination,
                                                                (__bridge CGImageSourceRef)[imageSources objectAtIndex:0],
                                                                inputPaths[0],
                                                                NO_COMPRESSION_OVERRIDE,
                                                                selectedImageIndex,
                                                                TIFFUtilOperationExtract);
            failed = writtenCount == 0;
            break;

        case TIFFUtilOperationInfo:
            printTiffInfoForPaths(inputPaths, inputCount, NO);
            break;

        case TIFFUtilOperationVerboseInfo:
            printTiffInfoForPaths(inputPaths, inputCount, YES);
            break;

        case TIFFUtilOperationFix:
            writtenCount = appendImageSourceFramesToDestination(destination,
                                                                (__bridge CGImageSourceRef)[imageSources objectAtIndex:0],
                                                                inputPaths[0],
                                                                NO_COMPRESSION_OVERRIDE,
                                                                ALL_IMAGES,
                                                                TIFFUtilOperationFix);
            failed = writtenCount == 0;
            break;

        case TIFFUtilOperationDump:
            dumpTiffFiles(inputPaths, inputCount);
            break;
        }

        if (outputPath != NULL) {
            if (failed) {
                fputs("No output file created due to errors.\n", stderr);
            } else {
                NSString *outputPathString;
                const char *plural;

                CGImageDestinationFinalize(destination);
                outputPathString = [NSString stringWithUTF8String:outputPath];
                if ([outputData writeToFile:outputPathString atomically:YES]) {
                    plural = writtenCount == 1 ? "" : "s";
                    fprintf(stderr, "%ld image%s written to %s.\n", (long)writtenCount, plural, outputPath);
                } else {
                    fprintf(stderr, "Error writing data to file %s.\n", outputPath);
                    failed = 1;
                }
            }

            CFRelease(destination);
        }
    }

    return failed ? 5 : 0;
}
