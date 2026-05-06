#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>

extern CFStringRef CGColorSpaceCopyICCProfileDescription(CGColorSpaceRef space);

static void
tiffutil_TIFFPrintDirectory(TIFF *tif, FILE *fd, long flags)
{
	TIFFDirectory *td = &tif->tif_dir;
	const char *sep;
	uint16_t shortv;
	uint32_t longv;
	char *stringv;

	fprintf(fd, "Directory at 0x%llx\n", (unsigned long long)tif->tif_diroff);
	if (TIFFFieldSet(tif, FIELD_SUBFILETYPE)) {
		fprintf(fd, "  Subfile Type:");
		sep = " ";
		if (td->td_subfiletype & FILETYPE_REDUCEDIMAGE) {
			fprintf(fd, "%sreduced-resolution image", sep);
			sep = "/";
		}
		if (td->td_subfiletype & FILETYPE_PAGE) {
			fprintf(fd, "%smulti-page document", sep);
			sep = "/";
		}
		if (td->td_subfiletype & FILETYPE_MASK)
			fprintf(fd, "%stransparency mask", sep);
		fprintf(fd, " (%" PRIu32 " = 0x%" PRIx32 ")\n",
		    td->td_subfiletype, td->td_subfiletype);
	}
	if (TIFFFieldSet(tif, FIELD_IMAGEDIMENSIONS))
		fprintf(fd, "  Image Width: %" PRIu32 " Image Length: %" PRIu32 "\n",
		    td->td_imagewidth, td->td_imagelength);
	if (TIFFFieldSet(tif, FIELD_TILEDIMENSIONS)) {
		fprintf(fd, "  Tile Width: %" PRIu32 " Tile Length: %" PRIu32,
		    td->td_tilewidth, td->td_tilelength);
		if (TIFFFieldSet(tif, FIELD_TILEDEPTH))
			fprintf(fd, " Tile Depth: %" PRIu32, td->td_tiledepth);
		fputc('\n', fd);
	}
	if (TIFFFieldSet(tif, FIELD_RESOLUTION))
		fprintf(fd, "  Resolution: %g, %g\n",
		    td->td_xresolution, td->td_yresolution);
	if (TIFFFieldSet(tif, FIELD_RESOLUTIONUNIT)) {
		fputs("  Resolution Unit: ", fd);
		switch (td->td_resolutionunit) {
		case RESUNIT_NONE:
			fputs("none\n", fd);
			break;
		case RESUNIT_INCH:
			fputs("pixels/inch\n", fd);
			break;
		case RESUNIT_CENTIMETER:
			fputs("pixels/cm\n", fd);
			break;
		default:
			fprintf(fd, "%" PRIu16 " (0x%" PRIx16 ")\n",
			    td->td_resolutionunit, td->td_resolutionunit);
			break;
		}
	}
	if (TIFFFieldSet(tif, FIELD_POSITION))
		fprintf(fd, "  Position: %g, %g\n",
		    td->td_xposition, td->td_yposition);
	if (TIFFFieldSet(tif, FIELD_BITSPERSAMPLE))
		fprintf(fd, "  Bits/Sample: %" PRIu16 "\n", td->td_bitspersample);
	if (TIFFFieldSet(tif, FIELD_SAMPLEFORMAT)) {
		fputs("  Sample Format: ", fd);
		switch (td->td_sampleformat) {
		case SAMPLEFORMAT_UINT:
			fputs("unsigned integer\n", fd);
			break;
		case SAMPLEFORMAT_INT:
			fputs("signed integer\n", fd);
			break;
		case SAMPLEFORMAT_IEEEFP:
			fputs("IEEE floating point\n", fd);
			break;
		case SAMPLEFORMAT_VOID:
			fputs("void\n", fd);
			break;
		default:
			fprintf(fd, "%" PRIu16 " (0x%" PRIx16 ")\n",
			    td->td_sampleformat, td->td_sampleformat);
			break;
		}
	}
	if (TIFFFieldSet(tif, FIELD_COMPRESSION)) {
		fputs("  Compression Scheme: ", fd);
		switch (td->td_compression) {
		case COMPRESSION_NONE:
			fputs("none\n", fd);
			break;
		case COMPRESSION_CCITTRLE:
			fputs("CCITT modified Huffman encoding\n", fd);
			break;
		case COMPRESSION_CCITTFAX3:
			fputs("CCITT Group 3 facsimile encoding\n", fd);
			break;
		case COMPRESSION_CCITTFAX4:
			fputs("CCITT Group 4 facsimile encoding\n", fd);
			break;
		case COMPRESSION_LZW:
			fputs("Lempel-Ziv & Welch encoding\n", fd);
			break;
		case COMPRESSION_OJPEG:
			fputs("Old-style JPEG encoding\n", fd);
			break;
		case COMPRESSION_JPEG:
			fputs("JPEG encoding\n", fd);
			break;
		case COMPRESSION_ADOBE_DEFLATE:
		case COMPRESSION_DEFLATE:
			fputs("ZIP/Deflate encoding\n", fd);
			break;
		case 32766:
			fputs("NeXTstep 1.0 2-bit encoding\n", fd);
			break;
		case 32771:
			fprintf(fd, "CCITT modified Huffman encoding %s\n",
			    "w/ word alignment");
			break;
		case 32773:
			fputs("PackBits encoding\n", fd);
			break;
		case 32809:
			fputs("ThunderScan 4-bit encoding\n", fd);
			break;
		case 32865:
			fputs("NeXTstep 2.0 JPEG encoding\n", fd);
			break;
		default:
			fprintf(fd, "%" PRIu16 " (0x%" PRIx16 ")\n",
			    td->td_compression, td->td_compression);
			break;
		}
	}
	if (TIFFFieldSet(tif, FIELD_PHOTOMETRIC)) {
		fputs("  Photometric Interpretation: ", fd);
		switch (td->td_photometric) {
		case PHOTOMETRIC_MINISWHITE:
			fputs("\"min-is-white\"\n", fd);
			break;
		case PHOTOMETRIC_MINISBLACK:
			fputs("\"min-is-black\"\n", fd);
			break;
		case PHOTOMETRIC_RGB:
			fputs("RGB color\n", fd);
			break;
		case PHOTOMETRIC_PALETTE:
			fputs("palette color (RGB from colormap)\n", fd);
			break;
		case PHOTOMETRIC_MASK:
			fputs("transparency mask\n", fd);
			break;
		case PHOTOMETRIC_SEPARATED:
			if (td->td_samplesperpixel == 2)
				fputs("5 (NeXT alpha, used in 1.0)\n", fd);
			else
				fputs("5 (CMYK color)\n", fd);
			break;
		default:
			fprintf(fd, "%" PRIu16 " (0x%" PRIx16 ")\n",
			    td->td_photometric, td->td_photometric);
			break;
		}
	}
	{
		uint16_t extraCount = 0;
		uint16_t *extraInfo = NULL;
		if (TIFFGetField(tif, TIFFTAG_EXTRASAMPLES, &extraCount, &extraInfo) &&
		    extraCount != 0) {
			const char *alpha = "Not present";
			if (extraInfo != NULL && (uint16_t)(extraInfo[0] - 1) < 2)
				alpha = "Present";
			else if (extraCount == 1)
				alpha = "Present";
			fprintf(fd, "  Alpha: %s\n", alpha);
		}
	}
	if (TIFFFieldSet(tif, FIELD_THRESHHOLDING)) {
		fputs("  Thresholding: ", fd);
		switch (td->td_threshholding) {
		case THRESHHOLD_BILEVEL:
			fputs("bilevel art scan\n", fd);
			break;
		case THRESHHOLD_HALFTONE:
			fputs("halftone or dithered scan\n", fd);
			break;
		case THRESHHOLD_ERRORDIFFUSE:
			fputs("error diffused\n", fd);
			break;
		default:
			fprintf(fd, "%" PRIu16 " (0x%" PRIx16 ")\n",
			    td->td_threshholding, td->td_threshholding);
			break;
		}
	}
	if (TIFFFieldSet(tif, FIELD_FILLORDER)) {
		fputs("  FillOrder: ", fd);
		switch (td->td_fillorder) {
		case FILLORDER_MSB2LSB:
			fputs("msb-to-lsb\n", fd);
			break;
		case FILLORDER_LSB2MSB:
			fputs("lsb-to-msb\n", fd);
			break;
		default:
			fprintf(fd, "%" PRIu16 " (0x%" PRIx16 ")\n",
			    td->td_fillorder, td->td_fillorder);
			break;
		}
	}
	if (TIFFGetField(tif, TIFFTAG_PREDICTOR, &shortv)) {
		fputs("  Predictor: ", fd);
		switch (shortv) {
		case 1:
			fputs("none\n", fd);
			break;
		case 2:
			fputs("horizontal differencing\n", fd);
			break;
		case 3:
			fputs("floating-point\n", fd);
			break;
		default:
			fprintf(fd, "%" PRIu16 " (0x%" PRIx16 ")\n", shortv, shortv);
			break;
		}
	}
	if (TIFFGetField(tif, TIFFTAG_ARTIST, &stringv))
		fprintf(fd, "  Artist: \"%s\"\n", stringv);
	if (TIFFGetField(tif, TIFFTAG_DATETIME, &stringv))
		fprintf(fd, "  Date & Time: \"%s\"\n", stringv);
	if (TIFFGetField(tif, TIFFTAG_HOSTCOMPUTER, &stringv))
		fprintf(fd, "  Host Computer: \"%s\"\n", stringv);
	if (TIFFGetField(tif, TIFFTAG_SOFTWARE, &stringv))
		fprintf(fd, "  Software: \"%s\"\n", stringv);
	if (TIFFGetField(tif, TIFFTAG_DOCUMENTNAME, &stringv))
		fprintf(fd, "  Document Name: \"%s\"\n", stringv);
	if (TIFFGetField(tif, TIFFTAG_IMAGEDESCRIPTION, &stringv))
		fprintf(fd, "  Image Description: \"%s\"\n", stringv);
	if (TIFFGetField(tif, TIFFTAG_MAKE, &stringv))
		fprintf(fd, "  Make: \"%s\"\n", stringv);
	if (TIFFGetField(tif, TIFFTAG_MODEL, &stringv))
		fprintf(fd, "  Model: \"%s\"\n", stringv);
	if (TIFFGetField(tif, TIFFTAG_ORIENTATION, &shortv)) {
		fputs("  Orientation: ", fd);
		if (shortv < NORIENTNAMES)
			fprintf(fd, "%s\n", orientNames[shortv]);
		else
			fprintf(fd, "%" PRIu16 " (0x%" PRIx16 ")\n", shortv, shortv);
	}
	if (TIFFFieldSet(tif, FIELD_SAMPLESPERPIXEL))
		fprintf(fd, "  Samples/Pixel: %" PRIu16 "\n", td->td_samplesperpixel);
	if (TIFFFieldSet(tif, FIELD_ROWSPERSTRIP)) {
		fputs("  Rows/Strip: ", fd);
		if (td->td_rowsperstrip == (uint32_t)-1)
			fputs("(infinite)\n", fd);
		else
			fprintf(fd, "%" PRIu32 "\n", td->td_rowsperstrip);
	}
	if (td->td_nstrips != 0) {
		const char *itemName = TIFFIsTiled(tif) ? "Tiles" : "Strips";
		fprintf(fd, "  Number of %s: %" PRIu32 "\n", itemName, td->td_nstrips);
		if (flags) {
			uint32_t i;
			fprintf(fd, "  %s (Offset, ByteCount):\n", itemName);
			for (i = 0; i < td->td_nstrips; ++i) {
				fprintf(fd, "     %" PRIu64 ", %" PRIu64 "\n",
				    TIFFGetStrileOffset(tif, i),
				    TIFFGetStrileByteCount(tif, i));
			}
		}
	}
	if (TIFFFieldSet(tif, FIELD_MINSAMPLEVALUE))
		fprintf(fd, "  Min Sample Value: %" PRIu16 "\n", td->td_minsamplevalue);
	if (TIFFFieldSet(tif, FIELD_MAXSAMPLEVALUE))
		fprintf(fd, "  Max Sample Value: %" PRIu16 "\n", td->td_maxsamplevalue);
	if (TIFFFieldSet(tif, FIELD_PLANARCONFIG)) {
		fputs("  Planar Configuration: ", fd);
		switch (td->td_planarconfig) {
		case PLANARCONFIG_CONTIG:
			fputs("Not planar\n", fd);
			break;
		case PLANARCONFIG_SEPARATE:
			fputs("Planar\n", fd);
			break;
		default:
			fprintf(fd, "%" PRIu16 " (0x%" PRIx16 ")\n",
			    td->td_planarconfig, td->td_planarconfig);
			break;
		}
	}
	if (TIFFGetField(tif, TIFFTAG_PAGENAME, &stringv))
		fprintf(fd, "  Page Name: \"%s\"\n", stringv);
	if (TIFFGetField(tif, TIFFTAG_GROUP3OPTIONS, &longv)) {
		fprintf(fd, "  Group 3 Options:");
		sep = " ";
		if (longv & GROUP3OPT_2DENCODING) {
			fprintf(fd, "%s2-d encoding", sep);
			sep = "+";
		}
		if (longv & GROUP3OPT_FILLBITS) {
			fprintf(fd, "%sEOL padding", sep);
			sep = "+";
		}
		if (longv & GROUP3OPT_UNCOMPRESSED)
			fprintf(fd, "%sno compression", sep);
		fprintf(fd, " (%" PRIu32 " = 0x%" PRIx32 ")\n", longv, longv);
	}
	if (TIFFGetField(tif, TIFFTAG_CLEANFAXDATA, &shortv)) {
		fputs("  Fax Data: ", fd);
		switch (shortv) {
		case CLEANFAXDATA_CLEAN:
			fputs("clean\n", fd);
			break;
		case CLEANFAXDATA_REGENERATED:
			fputs("receiver regenerated\n", fd);
			break;
		case CLEANFAXDATA_UNCLEAN:
			fputs("uncorrected errors\n", fd);
			break;
		default:
			fprintf(fd, "(%" PRIu16 " = 0x%" PRIx16 ")\n", shortv, shortv);
			break;
		}
	}
	if (TIFFGetField(tif, TIFFTAG_BADFAXLINES, &longv))
		fprintf(fd, "  Bad Fax Lines: %" PRIu32 "\n", longv);
	if (TIFFGetField(tif, TIFFTAG_CONSECUTIVEBADFAXLINES, &longv))
		fprintf(fd, "  Consecutive Bad Fax Lines: %" PRIu32 "\n", longv);
	if (TIFFGetField(tif, TIFFTAG_GROUP4OPTIONS, &longv)) {
		fprintf(fd, "  Group 4 Options:");
		if (longv & GROUP4OPT_UNCOMPRESSED)
			fputs("uncompressed data", fd);
		fprintf(fd, " (%" PRIu32 " = 0x%" PRIx32 ")\n", longv, longv);
	}
	if (TIFFFieldSet(tif, FIELD_PAGENUMBER))
		fprintf(fd, "  Page Number: %" PRIu16 "-%" PRIu16 "\n",
		    td->td_pagenumber[0], td->td_pagenumber[1]);
	if (TIFFFieldSet(tif, FIELD_COLORMAP)) {
		uint32_t i;
		fputs("  Color Map: ", fd);
		if (flags) {
			fputc('\n', fd);
			for (i = 0; i < (1UL << td->td_bitspersample); ++i) {
				fprintf(fd, "    %" PRIu32 ": %" PRIu16 " %" PRIu16 " %" PRIu16 "\n",
				    i,
				    td->td_colormap[0][i],
				    td->td_colormap[1][i],
				    td->td_colormap[2][i]);
			}
		} else {
			fputs("(present)\n", fd);
		}
	}
	{
		uint32_t iccLength = 0;
		void *iccData = NULL;
		if (TIFFGetField(tif, TIFFTAG_ICCPROFILE, &iccLength, &iccData) &&
		    iccData != NULL && iccLength >= 0xFB) {
			CFDataRef profileData =
			    CFDataCreate(NULL, (const UInt8 *)iccData, (CFIndex)iccLength);
			if (profileData != NULL) {
				CGColorSpaceRef colorSpace =
				    CGColorSpaceCreateWithICCData(profileData);
				if (colorSpace != NULL) {
					CFStringRef description =
					    CGColorSpaceCopyICCProfileDescription(colorSpace);
					if (description != NULL) {
						const char *profileName =
						    CFStringGetCStringPtr(description,
						        CFStringGetSystemEncoding());
						if (profileName != NULL)
							fprintf(fd, "  Profile Name: %s\n", profileName);
						CFRelease(description);
					}
					CGColorSpaceRelease(colorSpace);
				}
				CFRelease(profileData);
			}
		}
	}
}
