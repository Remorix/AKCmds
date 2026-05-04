#import "open_internal.h"

#include <dirent.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

// Fast-path header lookup hints shared by the macOS and iOS backends.
// Each row stores a header-name prefix followed by candidate framework roots.

static NSString *kFastPathTable[][15] = {
    { @"CUI",            @"/System/Library/PrivateFrameworks/CoreUI.framework", nil },
    { @"CR",             @"/System/Library/PrivateFrameworks/CoreRAID.framework", nil },
    { @"IPMI",           @"/System/Library/PrivateFrameworks/PlatformHardwareManagement.framework", nil },
    { @"WK",             @"/System/Library/PrivateFrameworks/WebKit2.framework", nil },
    { @"gpus_",          @"/System/Library/PrivateFrameworks/GPUSupport.framework", nil },
    { @"JS",             @"/System/Library/Frameworks/JavaScriptCore.framework",
                         @"/System/Library/Frameworks/WebKit.framework/Frameworks/WebCore.framework", nil },
    { @"Re",             @"/System/Library/Frameworks/WebKit.framework/Frameworks/WebCore.framework",
                         @"/System/Library/Frameworks/JavaScriptCore.framework",
                         @"/System/Library/Frameworks/Message.framework", nil },
    { @"tcl",            @"/System/Library/Frameworks/Tcl.framework", nil },
    { @"XS",             @"/System/Library/PrivateFrameworks/ServerFoundation.framework",
                         @"/System/Library/PrivateFrameworks/CoreDaemon.framework", nil },
    { @"gl",             @"/System/Library/Frameworks/OpenGL.framework", nil },
    { @"xml",            @"/System/Library/PrivateFrameworks/VCXMPP.framework/Frameworks/libxml.framework", nil },
    { @"We",             @"/System/Library/Frameworks/WebKit.framework",
                         @"/System/Library/Frameworks/WebKit.framework/Frameworks/WebCore.framework",
                         @"/System/Library/Frameworks/JavaScriptCore.framework", nil },
    { @"Bi",             @"/System/Library/Frameworks/Carbon.framework/Frameworks/Ink.framework", nil },
    { @"RF",             @"/System/Library/PrivateFrameworks/CoreMediaAuthoring.framework", nil },
    { @"UIR",            @"/System/Library/PrivateFrameworks/UIRecording.framework", nil },
    { @"Mime",           @"/System/Library/Frameworks/Message.framework",
                         @"/System/Library/PrivateFrameworks/CoreMessage.framework", nil },
    { @"tk",            @"/System/Library/Frameworks/Tk.framework", nil },
    { @"GR",             @"/System/Library/PrivateFrameworks/GraphKit.framework", nil },
    { @"GF",             @"/System/Library/Frameworks/Quartz.framework/Frameworks/QuartzComposer.framework",
                         @"/System/Library/PrivateFrameworks/GraphicsAppSupport.framework/Frameworks/QuartzComposer.framework", nil },
    { @"BK",             @"/System/Library/PrivateFrameworks/BrowserKit.framework", nil },
    { @"GK",             @"/System/Library/Frameworks/GameKit.framework",
                         @"/System/Library/PrivateFrameworks/GameKitServices.framework", nil },
    { @"Dir",            @"/System/Library/Frameworks/DirectoryService.framework", nil },
    { @"Gr",             @"/System/Library/Frameworks/WebKit.framework/Frameworks/WebCore.framework", nil },
    { @"C3D",            @"/System/Library/Frameworks/SceneKit.framework", nil },
    { @"DBC",            @"/System/Library/PrivateFrameworks/DashboardClient.framework", nil },
    { @"Ge",             @"/System/Library/Frameworks/WebKit.framework/Frameworks/WebCore.framework", nil },
    { @"JNF",            @"/System/Library/Frameworks/JavaVM.framework/Frameworks/JavaNativeFoundation.framework", nil },
    { @"APS",            @"/System/Library/PrivateFrameworks/ApplePushService.framework", nil },
    { @"OS",             @"/System/Library/Frameworks/OSAKit.framework",
                         @"/System/Library/PrivateFrameworks/Install.framework/Frameworks/OSInstall.framework", nil },
    { @"Event",          @"/System/Library/Frameworks/WebKit.framework/Frameworks/WebCore.framework", nil },
    { @"BOM",            @"/System/Library/PrivateFrameworks/Bom.framework", nil },
    { @"Pr",             @"/System/Library/PrivateFrameworks/ProKit.framework",
                         @"/System/Library/Frameworks/JavaScriptCore.framework", nil },
    { @"PCP",            @"/System/Library/PrivateFrameworks/PodcastProducerKit.framework", nil },
    { @"WP",             @"/System/Library/PrivateFrameworks/WhitePages.framework", nil },
    { @"HT",             @"/System/Library/Frameworks/WebKit.framework/Frameworks/WebCore.framework", nil },
    { @"HI",             @"/System/Library/Frameworks/Carbon.framework/Frameworks/HIToolbox.framework", nil },
    { @"SU",             @"/System/Library/PrivateFrameworks/SoftwareUpdate.framework", nil },
    { @"LUI",            @"/System/Library/PrivateFrameworks/LoginUIKit.framework", nil },
    { @"PK",             @"/System/Library/PrivateFrameworks/PackageKit.framework", nil },
    { @"Po",             @"/System/Library/Frameworks/WebKit.framework/Frameworks/WebCore.framework", nil },
    { @"Pl",             @"/System/Library/Frameworks/WebKit.framework/Frameworks/WebCore.framework", nil },
    { @"QuartzFilter",   @"/System/Library/Frameworks/Quartz.framework/Frameworks/QuartzFilters.framework", nil },
    { @"PS",             @"/System/Library/Frameworks/PubSub.framework", nil },
    { @"uxmi",           @"/System/Library/PrivateFrameworks/VCXMPP.framework/Frameworks/uxmi.framework", nil },
    { @"AirPort",        @"/System/Library/PrivateFrameworks/CoreWLANKit.framework", nil },
    { @"Auth",           @"/System/Library/Frameworks/Security.framework", nil },
    { @"PB",             @"/System/Library/PrivateFrameworks/ProtocolBuffer.framework",
                         @"/System/Library/PrivateFrameworks/RemoteViewServices.framework", nil },
    { @"PA",             @"/System/Library/PrivateFrameworks/PerformanceAnalysis.framework", nil },
    { @"PI",             @"/System/Library/PrivateFrameworks/ProjectInfo.framework", nil },
    { @"GEO",            @"/System/Library/PrivateFrameworks/GeoServices.framework",
                         @"/System/Library/PrivateFrameworks/GeoKit.framework", nil },
    { @"IS",             @"/System/Library/PrivateFrameworks/CommerceKit.framework",
                         @"/System/Library/Frameworks/SyncServices.framework", nil },
    { @"PM",             @"/System/Library/Frameworks/ApplicationServices.framework/Frameworks/PrintCore.framework", nil },
    { @"Me",             @"/System/Library/Frameworks/Message.framework",
                         @"/System/Library/PrivateFrameworks/MediaUI.framework",
                         @"/System/Library/Frameworks/WebKit.framework/Frameworks/WebCore.framework",
                         @"/System/Library/PrivateFrameworks/CoreMessage.framework", nil },
    { @"Ma",             @"/System/Library/PrivateFrameworks/iLifeSlideshow.framework",
                         @"/System/Library/PrivateFrameworks/Slideshows.framework",
                         @"/System/Library/Frameworks/JavaScriptCore.framework",
                         @"/System/Library/Frameworks/CoreServices.framework/Frameworks/CarbonCore.framework",
                         @"/System/Library/Frameworks/Carbon.framework/Frameworks/HIToolbox.framework", nil },
    { @"EK",             @"/System/Library/Frameworks/EventKit.framework",
                         @"/System/Library/Frameworks/CalendarStore.framework", nil },
    { @"DNSManager",     @"/System/Library/PrivateFrameworks/DNSManager.framework", nil },
    { @"SL",             @"/System/Library/Frameworks/Social.framework",
                         @"/System/Library/PrivateFrameworks/SpeechDictionary.framework",
                         @"/System/Library/PrivateFrameworks/SocialDaemon.framework", nil },
    { @"AIAT",           @"/System/Library/Frameworks/CoreServices.framework/Frameworks/SearchKit.framework", nil },
    { @"EX",             @"/System/Library/PrivateFrameworks/Executioner.framework", nil },
    { @"EWS",            @"/System/Library/PrivateFrameworks/ExchangeWebServices.framework", nil },
    { @"SO",             @"/System/Library/PrivateFrameworks/SocialUI.framework", nil },
    { @"MD",             @"/System/Library/Frameworks/CoreServices.framework/Frameworks/Metadata.framework", nil },
    { @"MF",             @"/System/Library/Frameworks/Message.framework", nil },
    { @"MC",             @"/System/Library/PrivateFrameworks/iLifeSlideshow.framework",
                         @"/System/Library/PrivateFrameworks/Slideshows.framework", nil },
    { @"MB",             @"/System/Library/PrivateFrameworks/SetupAssistantSupport.framework", nil },
    { @"MM",             @"/System/Library/PrivateFrameworks/ISSupport.framework",
                         @"/System/Library/PrivateFrameworks/AOSUI.framework", nil },
    { @"PJC",            @"/System/Library/Frameworks/ApplicationServices.framework/Frameworks/PrintCore.framework", nil },
    { @"MT",             @"/System/Library/PrivateFrameworks/MultitouchSupport.framework", nil },
    { @"XM",             @"/System/Library/PrivateFrameworks/XMPPCore.framework",
                         @"/System/Library/PrivateFrameworks/SystemMigration.framework", nil },
    { @"MP",             @"/System/Library/PrivateFrameworks/iLifeSlideshow.framework",
                         @"/System/Library/PrivateFrameworks/Slideshows.framework", nil },
    { @"MS",             @"/System/Library/PrivateFrameworks/CoreMediaStream.framework", nil },
    { @"MR",             @"/System/Library/PrivateFrameworks/iLifeSlideshow.framework",
                         @"/System/Library/PrivateFrameworks/Slideshows.framework", nil },
    { @"UA",             @"/System/Library/PrivateFrameworks/UniversalAccess.framework/Frameworks/UniversalAccessCore.framework", nil },
    { @"UB",             @"/System/Library/PrivateFrameworks/Ubiquity.framework", nil },
    { @"Fra",            @"/System/Library/Frameworks/WebKit.framework/Frameworks/WebCore.framework", nil },
    { @"GLK",            @"/System/Library/Frameworks/GLKit.framework", nil },
    { @"FT",             @"/System/Library/PrivateFrameworks/FTServices.framework",
                         @"/System/Library/PrivateFrameworks/FTClientServices.framework", nil },
    { @"IO",             @"/System/Library/Frameworks/IOKit.framework",
                         @"/System/Library/Frameworks/IOBluetooth.framework",
                         @"/System/Library/PrivateFrameworks/IOAccelerator.framework", nil },
    { @"DOM",            @"/System/Library/Frameworks/WebKit.framework/Frameworks/WebCore.framework",
                         @"/System/Library/Frameworks/WebKit.framework", nil },
    { @"VT",             @"/System/Library/Frameworks/VideoToolbox.framework", nil },
    { @"TEA",            @"/System/Library/PrivateFrameworks/TrustEvaluationAgent.framework", nil },
    { @"Document",       @"/System/Library/Frameworks/WebKit.framework/Frameworks/WebCore.framework", nil },
    { @"rpc",            @"/System/Library/PrivateFrameworks/oncrpc.framework", nil },
    { @"FC",             @"/System/Library/PrivateFrameworks/FamilyControls.framework", nil },
    { @"ATS",            @"/System/Library/Frameworks/ApplicationServices.framework/Frameworks/ATS.framework",
                         @"/System/Library/Frameworks/ApplicationServices.framework/Frameworks/QD.framework", nil },
    { @"cs",             @"/System/Library/Frameworks/Security.framework", nil },
    { @"xs",             @"/System/Library/PrivateFrameworks/CoreDaemon.framework", nil },
    { @"_AM",            @"/System/Library/Frameworks/Automator.framework", nil },
    { @"SHK",            @"/System/Library/PrivateFrameworks/ShareKit.framework", nil },
    { @"NA",             @"/System/Library/PrivateFrameworks/NetAuth.framework", nil },
    { @"py",             @"/System/Library/Frameworks/Python.framework", nil },
    { @"Pear",           @"/System/Library/PrivateFrameworks/VCXMPP.framework/Frameworks/Pear.framework", nil },
    { @"ASB",            @"/System/Library/PrivateFrameworks/AppContainer.framework", nil },
    { @"Drag",           @"/System/Library/Frameworks/WebKit.framework/Frameworks/WebCore.framework", nil },
    { @"User",           @"/System/Library/Frameworks/WebKit.framework/Frameworks/WebCore.framework", nil },
    { @"ASK",            @"/System/Library/Frameworks/AppleScriptKit.framework", nil },
    { @"NS",             @"/System/Library/Frameworks/AppKit.framework",
                         @"/System/Library/Frameworks/Foundation.framework",
                         @"/System/Library/PrivateFrameworks/ProKit.framework",
                         @"/System/Library/Frameworks/CoreData.framework",
                         @"/System/Library/Frameworks/Scripting.framework",
                         @"/System/Library/PrivateFrameworks/VCXMPP.framework/Frameworks/XMPPToolkit.framework",
                         @"/System/Library/Frameworks/Message.framework",
                         @"/System/Library/PrivateFrameworks/RemoteViewServices.framework",
                         @"/System/Library/Frameworks/PreferencePanes.framework",
                         @"/System/Library/PrivateFrameworks/CoreMessage.framework",
                         @"/System/Library/PrivateFrameworks/vmutils.framework",
                         @"/System/Library/PrivateFrameworks/ServerFoundation.framework",
                         @"/System/Library/PrivateFrameworks/SpeechObjects.framework", nil },
    { @"D2D",            @"/System/Library/PrivateFrameworks/DeviceToDeviceKit.framework", nil },
    { @"Fo",             @"/System/Library/Frameworks/WebKit.framework/Frameworks/WebCore.framework", nil },
    { @"CK",             @"/System/Library/PrivateFrameworks/CommerceKit.framework", nil },
    { @"CI",             @"/System/Library/Frameworks/QuartzCore.framework/Frameworks/CoreImage.framework",
                         @"/System/Library/Frameworks/QuartzCore.framework",
                         @"/System/Library/PrivateFrameworks/CoreChineseEngine.framework", nil },
    { @"CM",             @"/System/Library/PrivateFrameworks/CoreMediaIOServices.framework",
                         @"/System/Library/Frameworks/CoreMediaIO.framework",
                         @"/System/Library/Frameworks/CoreMedia.framework",
                         @"/System/Library/Frameworks/Message.framework",
                         @"/System/Library/PrivateFrameworks/CoreMessage.framework", nil },
    { @"CL",             @"/System/Library/Frameworks/CoreLocation.framework", nil },
    { @"CB",             @"/System/Library/Frameworks/CoreBluetooth.framework", nil },
    { @"CA",             @"/System/Library/Frameworks/QuartzCore.framework",
                         @"/System/Library/Frameworks/CalendarStore.framework",
                         @"/System/Library/Frameworks/SecurityFoundation.framework", nil },
    { @"CG",             @"/System/Library/Frameworks/ApplicationServices.framework/Frameworks/CoreGraphics.framework",
                         @"/System/Library/Frameworks/CoreGraphics.framework",
                         @"/System/Library/Frameworks/OpenGL.framework",
                         @"/System/Library/Frameworks/ApplicationServices.framework/Frameworks/ImageIO.framework",
                         @"/System/Library/Frameworks/ImageIO.framework",
                         @"/System/Library/PrivateFrameworks/GraphicsAppSupport.framework/Frameworks/ImageIO.framework", nil },
    { @"CF",             @"/System/Library/Frameworks/CoreFoundation.framework",
                         @"/System/Library/Frameworks/CFNetwork.framework",
                         @"/System/Library/Frameworks/OpenDirectory.framework/Frameworks/CFOpenDirectory.framework", nil },
    { @"St",             @"/System/Library/Frameworks/WebKit.framework/Frameworks/WebCore.framework",
                         @"/System/Library/Frameworks/JavaScriptCore.framework", nil },
    { @"QuickLite",      @"/System/Library/PrivateFrameworks/WhitePages.framework", nil },
    { @"ADD",            @"/System/Library/PrivateFrameworks/avbdevicedxpc.framework", nil },
    { @"Fi",             @"/System/Library/Frameworks/MediaToolbox.framework",
                         @"/System/Library/Frameworks/CoreMedia.framework",
                         @"/System/Library/PrivateFrameworks/CoreMediaPrivate.framework",
                         @"/System/Library/Frameworks/WebKit.framework/Frameworks/WebCore.framework", nil },
    { @"CS",             @"/System/Library/PrivateFrameworks/CoreSymbolication.framework",
                         @"/System/Library/Frameworks/WebKit.framework/Frameworks/WebCore.framework",
                         @"/System/Library/Frameworks/CoreServices.framework/Frameworks/OSServices.framework", nil },
    { @"PDF",            @"/System/Library/Frameworks/Quartz.framework/Frameworks/PDFKit.framework", nil },
    { @"DFG",            @"/System/Library/Frameworks/JavaScriptCore.framework", nil },
    { @"CP",             @"/System/Library/PrivateFrameworks/CoreProfile.framework",
                         @"/System/Library/PrivateFrameworks/CorePDF.framework",
                         @"/System/Library/PrivateFrameworks/ConfigurationProfiles.framework", nil },
    { @"CW",             @"/System/Library/Frameworks/CoreWLAN.framework",
                         @"/System/Library/PrivateFrameworks/CoreWLANKit.framework", nil },
    { @"CV",             @"/System/Library/Frameworks/CoreVideo.framework",
                         @"/System/Library/Frameworks/QuartzCore.framework", nil },
    { @"Se",             @"/System/Library/Frameworks/Security.framework",
                         @"/System/Library/PrivateFrameworks/MessageProtection.framework",
                         @"/System/Library/Frameworks/WebKit.framework/Frameworks/WebCore.framework", nil },
    { @"CT",             @"/System/Library/Frameworks/ApplicationServices.framework/Frameworks/CoreText.framework",
                         @"/System/Library/Frameworks/CoreText.framework", nil },
    { @"ODC",            @"/System/Library/PrivateFrameworks/OpenDirectoryConfig.framework", nil },
    { @"Co",             @"/System/Library/PrivateFrameworks/CoreDAV.framework",
                         @"/System/Library/PrivateFrameworks/CoreWiFi.framework",
                         @"/System/Library/Frameworks/WebKit.framework/Frameworks/WebCore.framework",
                         @"/System/Library/Frameworks/CalendarStore.framework",
                         @"/System/Library/Frameworks/JavaScriptCore.framework",
                         @"/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework",
                         @"/System/Library/Frameworks/CoreServices.framework/Frameworks/CarbonCore.framework",
                         @"/System/Library/Frameworks/ApplicationServices.framework/Frameworks/ColorSync.framework",
                         @"/System/Library/Frameworks/CoreWLAN.framework",
                         @"/System/Library/Frameworks/QuartzCore.framework",
                         @"/System/Library/Frameworks/SceneKit.framework", nil },
    { @"SS",             @"/System/Library/PrivateFrameworks/CommerceKit.framework",
                         @"/System/Library/PrivateFrameworks/ScreenSharing.framework", nil },
    { @"Text",           @"/System/Library/Frameworks/WebKit.framework/Frameworks/WebCore.framework",
                         @"/System/Library/Frameworks/CoreServices.framework/Frameworks/CarbonCore.framework", nil },
    { @"Ca",             @"/System/Library/Frameworks/CalendarStore.framework",
                         @"/System/Library/PrivateFrameworks/CalDAV.framework",
                         @"/System/Library/PrivateFrameworks/CalendarAgentLink.framework",
                         @"/System/Library/PrivateFrameworks/CalendarFoundation.framework",
                         @"/System/Library/PrivateFrameworks/CalendarDraw.framework",
                         @"/System/Library/Frameworks/WebKit.framework/Frameworks/WebCore.framework",
                         @"/System/Library/Frameworks/JavaScriptCore.framework",
                         @"/System/Library/Frameworks/Carbon.framework/Frameworks/HIToolbox.framework",
                         @"/System/Library/Frameworks/CoreServices.framework/Frameworks/CarbonCore.framework",
                         @"/System/Library/Frameworks/Carbon.framework",
                         @"/System/Library/Frameworks/Carbon.framework/Frameworks/CarbonSound.framework",
                         @"/System/Library/Frameworks/WebKit.framework", nil },
    { @"Library",        @"/System/Library/Frameworks/Message.framework", nil },
    { @"SK",             @"/System/Library/Frameworks/StoreKit.framework", nil },
    { @"CD",             @"/System/Library/PrivateFrameworks/CommsDiagnostics.framework", nil },
    { @"Pa",             @"/System/Library/Frameworks/WebKit.framework/Frameworks/WebCore.framework", nil },
    { @"JRS",            @"/System/Library/Frameworks/JavaVM.framework/Frameworks/JavaRuntimeSupport.framework", nil },
    { @"SM",             @"/System/Library/PrivateFrameworks/SystemMigration.framework", nil },
    { @"SC",             @"/System/Library/PrivateFrameworks/ScreenReader.framework/Frameworks/ScreenReaderCore.framework",
                         @"/System/Library/Frameworks/SceneKit.framework",
                         @"/System/Library/PrivateFrameworks/ScreenReader.framework/Frameworks/ScreenReaderOutputServer.framework",
                         @"/System/Library/Frameworks/SystemConfiguration.framework",
                         @"/System/Library/PrivateFrameworks/ScreenReader.framework",
                         @"/System/Library/PrivateFrameworks/ScreenReader.framework/Frameworks/ScreenReaderBrailleDriver.framework",
                         @"/System/Library/PrivateFrameworks/Shortcut.framework",
                         @"/System/Library/PrivateFrameworks/ScreenReader.framework/Frameworks/ScreenReaderOutput.framework", nil },
    { @"SA",             @"/System/Library/PrivateFrameworks/SAObjects.framework", nil },
    { @"VMU",            @"/System/Library/PrivateFrameworks/Symbolication.framework", nil },
    { @"SF",             @"/System/Library/Frameworks/SecurityInterface.framework",
                         @"/System/Library/Frameworks/SecurityFoundation.framework", nil },
    { @"ImageCo",        @"/System/Library/Frameworks/QuickTime.framework", nil },
    { @"DM",             @"/System/Library/PrivateFrameworks/ISSupport.framework",
                         @"/System/Library/PrivateFrameworks/DiskManagement.framework", nil },
    { @"LLInt",          @"/System/Library/Frameworks/JavaScriptCore.framework", nil },
    { @"La",             @"/System/Library/Frameworks/WebKit.framework/Frameworks/WebCore.framework", nil },
    { @"DD",             @"/System/Library/PrivateFrameworks/DataDetectorsCore.framework",
                         @"/System/Library/PrivateFrameworks/DataDetectors.framework", nil },
    { @"QuickTime",      @"/System/Library/Frameworks/QuickTime.framework", nil },
    { @"Tr",             @"/System/Library/Frameworks/WebKit.framework/Frameworks/WebCore.framework", nil },
    { @"gssapi",         @"/System/Library/Frameworks/GSS.framework", nil },
    { @"MK",             @"/System/Library/PrivateFrameworks/MediaKit.framework",
                         @"/System/Library/PrivateFrameworks/ProKit.framework", nil },
    { @"IF",             @"/System/Library/PrivateFrameworks/Install.framework",
                         @"/System/Library/Frameworks/InstallerPlugins.framework", nil },
    { @"RWI",            @"/System/Library/PrivateFrameworks/WebInspector.framework", nil },
    { @"DR",             @"/System/Library/Frameworks/DiscRecording.framework",
                         @"/System/Library/Frameworks/DiscRecordingUI.framework", nil },
    { @"lib",            @"/System/Library/PrivateFrameworks/AppleProfileFamily.framework", nil },
    { @"Apple",          @"/System/Library/PrivateFrameworks/AppleProfileFamily.framework", nil },
    { @"SGT",            @"/System/Library/PrivateFrameworks/Suggestions.framework", nil },
    { @"AOS",            @"/System/Library/PrivateFrameworks/AOSKit.framework", nil },
    { @"LS",             @"/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework", nil },
    { @"SVG",            @"/System/Library/Frameworks/WebKit.framework/Frameworks/WebCore.framework", nil },
    { @"EAP",            @"/System/Library/PrivateFrameworks/EAP8021X.framework", nil },
    { @"TD",             @"/System/Library/PrivateFrameworks/CoreThemeDefinition.framework", nil },
    { @"AC",             @"/System/Library/PrivateFrameworks/AccountsDaemon.framework",
                         @"/System/Library/Frameworks/Accounts.framework", nil },
    { @"AB",             @"/System/Library/Frameworks/AddressBook.framework", nil },
    { @"AE",             @"/System/Library/Frameworks/CoreServices.framework/Frameworks/AE.framework", nil },
    { @"AF",             @"/System/Library/PrivateFrameworks/AssistantServices.framework",
                         @"/System/Library/PrivateFrameworks/Assistant.framework", nil },
    { @"Edit",           @"/System/Library/Frameworks/WebKit.framework/Frameworks/WebCore.framework", nil },
    { @"HDI_",           @"/System/Library/PrivateFrameworks/DiskImages.framework", nil },
    { @"AM",             @"/System/Library/Frameworks/Automator.framework", nil },
    { @"IA",             @"/System/Library/PrivateFrameworks/InternetAccounts.framework", nil },
    { @"IK",             @"/System/Library/Frameworks/Quartz.framework/Frameworks/ImageKit.framework",
                         @"/System/Library/PrivateFrameworks/GraphicsAppSupport.framework/Frameworks/ImageKit.framework", nil },
    { @"IM",             @"/System/Library/PrivateFrameworks/IMFoundation.framework",
                         @"/System/Library/Frameworks/IMCore.framework",
                         @"/System/Library/PrivateFrameworks/IMCore.framework",
                         @"/System/Library/PrivateFrameworks/IMAVCore.framework",
                         @"/System/Library/Frameworks/Message.framework",
                         @"/System/Library/PrivateFrameworks/IMAP.framework",
                         @"/System/Library/Frameworks/IMServicePlugIn.framework",
                         @"/System/Library/PrivateFrameworks/IMDaemonCore.framework",
                         @"/System/Library/PrivateFrameworks/IMDPersistence.framework",
                         @"/System/Library/PrivateFrameworks/IMDAppleServices.framework",
                         @"/System/Library/Frameworks/InstantMessage.framework", nil },
    { @"IL",             @"/System/Library/PrivateFrameworks/iLifeMediaBrowser.framework", nil },
    { @"kim",            @"/System/Library/Frameworks/Kerberos.framework", nil },
    { @"AV",             @"/System/Library/Frameworks/AudioVideoBridging.framework",
                         @"/System/Library/Frameworks/AVFoundation.framework",
                         @"/System/Library/PrivateFrameworks/AppleGVA.framework",
                         @"/System/Library/PrivateFrameworks/AVFoundationCF.framework",
                         @"/System/Library/PrivateFrameworks/AppleVA.framework",
                         @"/System/Library/PrivateFrameworks/AVConference.framework", nil },
    { @"AX",             @"/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework", nil },
    { @"IC",             @"/System/Library/PrivateFrameworks/iCalendar.framework",
                         @"/System/Library/Frameworks/ImageCaptureCore.framework",
                         @"/System/Library/Frameworks/Carbon.framework/Frameworks/ImageCapture.framework", nil },
    { @"Audio",          @"/System/Library/Frameworks/AudioToolbox.framework",
                         @"/System/Library/Frameworks/AudioUnit.framework",
                         @"/System/Library/Frameworks/CoreAudio.framework", nil },
    { @"DisplayServices",@"/System/Library/PrivateFrameworks/DisplayServices.framework", nil },
    { @"HPD",            @"/System/Library/PrivateFrameworks/HelpData.framework", nil },
    { @"Sc",             @"/System/Library/Frameworks/WebKit.framework/Frameworks/WebCore.framework",
                         @"/System/Library/Frameworks/ScreenSaver.framework", nil },
    { @"Ac",             @"/System/Library/Frameworks/Message.framework", nil },
    { @"QT",             @"/System/Library/Frameworks/QTKit.framework", nil },
    { @"MIDI",           @"/System/Library/Frameworks/CoreMIDI.framework", nil },
    { @"Tundra",         @"/System/Library/PrivateFrameworks/CoreMediaIOServices.framework",
                         @"/System/Library/PrivateFrameworks/CoreMediaIOServicesPrivate.framework", nil },
    { @"st",             @"/System/Library/Frameworks/Kernel.framework", nil },
    { @"QC",             @"/System/Library/Frameworks/Quartz.framework/Frameworks/QuartzComposer.framework",
                         @"/System/Library/PrivateFrameworks/GraphicsAppSupport.framework/Frameworks/QuartzComposer.framework", nil },
    { @"DI",             @"/System/Library/PrivateFrameworks/DiskImages.framework", nil },
    { @"In",             @"/System/Library/Frameworks/WebKit.framework/Frameworks/WebCore.framework",
                         @"/System/Library/Frameworks/Carbon.framework/Frameworks/Ink.framework",
                         @"/System/Library/Frameworks/InstallerPlugins.framework", nil },
    { @"QL",             @"/System/Library/Frameworks/Quartz.framework/Frameworks/QuickLookUI.framework",
                         @"/System/Library/Frameworks/QuickLook.framework", nil },
};

@implementation HeaderOpenState

- (instancetype)initWithRemainingHeaders:(NSArray *)headers {
    self = [super init];
    if (self) {
        self.remainingHeaders = (NSMutableArray *)headers;
        NSMutableDictionary *map = [[NSMutableDictionary alloc]
                                        initWithCapacity:[headers count]];
        for (id header in headers)
            [map setObject:[NSMutableArray array] forKey:header];
        self.headersToHeaderPaths = map;
        [map release];
        self.finished = (self.remainingHeaders.count == 0);
    }
    return self;
}

- (void)dealloc {
    [_remainingHeaders release];
    [_headersToHeaderPaths release];
    [_searchRoots release];
    [super dealloc];
}

// Subclasses may override this hook when they need per-path bookkeeping.
- (void)visitPath:(NSString *)path {}

- (void)visitHeader:(NSString *)name atPath:(NSString *)fullPath {
    NSUInteger count = self.remainingHeaders.count;
    for (NSUInteger i = 0; i < count; ) {
        NSString *remaining = self.remainingHeaders[i];
        if ([remaining caseInsensitiveCompare:name] == NSOrderedSame) {
            NSMutableArray *hits = self.headersToHeaderPaths[remaining];
            [hits removeAllObjects];
            [hits addObject:fullPath];
            [self.remainingHeaders removeObjectAtIndex:i];
            --count;
        } else {
            if ([name rangeOfString:remaining options:NSCaseInsensitiveSearch].location
                    != NSNotFound)
                [self.headersToHeaderPaths[remaining] addObject:fullPath];
            ++i;
        }
    }
    self.finished = (count == 0);
}

- (void)performFastPathSearch {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSUInteger count  = self.remainingHeaders.count;
    if (!count) goto done;

    for (NSUInteger i = 0; i < count; ) {
        NSString *header = self.remainingHeaders[i];
        NSUInteger len   = header.length;

        // Must have a recognised C-header extension (.h .H .i .I .r .R)
        if (len < 3
            || [header characterAtIndex:len - 2] != '.'
            || memchr("hHiIrR", [header characterAtIndex:len - 1], 7) == NULL) {
            ++i;
            continue;
        }

        BOOL found = NO;
        for (NSUInteger row = 0; row < 182; ++row) {
            NSString *pattern = kFastPathTable[row][0];
            // Case-insensitive backward search for prefix pattern
            NSRange r = [header rangeOfString:pattern
                                      options:NSCaseInsensitiveSearch
                                              | NSBackwardsSearch];
            if (r.location == NSNotFound) continue;

            // Walk path candidates for this row
            for (NSUInteger col = 1; col < 15; ++col) {
                NSString *fwPath = kFastPathTable[row][col];
                if (!fwPath) break;
#if TARGET_OS_IPHONE
                NSMutableArray *basePaths = [NSMutableArray arrayWithObject:fwPath];
                if (self.searchRoots.count) {
                    NSString *frameworksSuffix = nil;
                    NSString *rootSuffix = nil;

                    if ([fwPath hasPrefix:@"/System/Library/Frameworks/"]) {
                        frameworksSuffix =
                            [fwPath substringFromIndex:[@"/System/Library/Frameworks/" length]];
                        rootSuffix = @"/System/Library/Frameworks";
                    } else if ([fwPath hasPrefix:@"/System/Library/PrivateFrameworks/"]) {
                        frameworksSuffix =
                            [fwPath substringFromIndex:[@"/System/Library/PrivateFrameworks/" length]];
                        rootSuffix = @"/System/Library/PrivateFrameworks";
                    }

                    if (frameworksSuffix && rootSuffix) {
                        for (NSString *root in self.searchRoots) {
                            NSString *normalizedRoot = [root hasSuffix:@"/"]
                                ? [root substringToIndex:root.length - 1]
                                : root;
                            if (![normalizedRoot hasSuffix:rootSuffix])
                                continue;
                            NSString *mapped =
                                [normalizedRoot stringByAppendingPathComponent:frameworksSuffix];
                            if (![basePaths containsObject:mapped])
                                [basePaths addObject:mapped];
                        }
                    }
                }

                for (NSString *basePath in basePaths) {
                    NSString *candidate = [[basePath stringByAppendingPathComponent:@"Headers"]
                                               stringByAppendingPathComponent:header];
                    if ([fm fileExistsAtPath:candidate]) {
                        [self.headersToHeaderPaths[header] addObject:candidate];
                        [self.remainingHeaders removeObjectAtIndex:i];
                        --count;
                        found = YES;
                        goto next_header;
                    }
                    candidate = [[basePath stringByAppendingPathComponent:@"PrivateHeaders"]
                                     stringByAppendingPathComponent:header];
                    if ([fm fileExistsAtPath:candidate]) {
                        [self.headersToHeaderPaths[header] addObject:candidate];
                        [self.remainingHeaders removeObjectAtIndex:i];
                        --count;
                        found = YES;
                        goto next_header;
                    }
                }
#else
                NSString *candidate = [[fwPath stringByAppendingPathComponent:@"Headers"]
                                           stringByAppendingPathComponent:header];
                if ([fm fileExistsAtPath:candidate]) {
                    [self.headersToHeaderPaths[header] addObject:candidate];
                    [self.remainingHeaders removeObjectAtIndex:i];
                    --count;
                    found = YES;
                    goto next_header;
                }
                candidate = [[fwPath stringByAppendingPathComponent:@"PrivateHeaders"]
                                 stringByAppendingPathComponent:header];
                if ([fm fileExistsAtPath:candidate]) {
                    [self.headersToHeaderPaths[header] addObject:candidate];
                    [self.remainingHeaders removeObjectAtIndex:i];
                    --count;
                    found = YES;
                    goto next_header;
                }
#endif
            }
        }
        if (!found) ++i;
next_header:;
    }
done:
    self.finished = (self.remainingHeaders.count == 0);
}

@end

static NSArray *directoryContents(id path, NSError **outError) {
    if (!path) return nil;
    const char *fsRep = [(id)path fileSystemRepresentation];
    DIR *dir = opendir(fsRep);
    if (!dir) return nil;

    NSMutableArray *entries = [NSMutableArray array];
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    struct dirent entry, *result;
    memset(&entry, 0, sizeof(entry));
    int err = 0;
    while ((err = readdir_r(dir, &entry, &result)) == 0 && result) {
        if (!entry.d_ino) continue;
        if (entry.d_name[0] == '.'
            && (entry.d_namlen == 1
                || (entry.d_namlen == 2 && entry.d_name[1] == '.')))
            continue;
        NSString *name = [[NSString alloc] initWithBytes:entry.d_name
                                                  length:entry.d_namlen
                                                encoding:NSUTF8StringEncoding];
        if (name) {
            NSNumber *isDir = (entry.d_type == DT_DIR)
                ? [NSNumber numberWithBool:YES] : nil;
            NSDictionary *info = [[NSDictionary alloc]
                initWithObjectsAndKeys:name, @"name", isDir, @"dir", nil];
            [entries addObject:info];
            [info release];
            [name release];
        }
    }
    closedir(dir);
    [pool release];

    if (outError && err) {
        int e = errno;
        BOOL isURL = [path isKindOfClass:[NSURL class]];
        NSString *key = isURL ? NSURLErrorKey : NSFilePathErrorKey;
        NSInteger code = (e == 1) ? 257 : (e == 2) ? 260 : (e == 13) ? 257 : 256;
        if (e == 63) code = 258;
        *outError = [NSError errorWithDomain:NSCocoaErrorDomain
                                        code:code
                                    userInfo:@{
            key:              path,
            NSUnderlyingErrorKey: [NSError errorWithDomain:NSPOSIXErrorDomain
                                                       code:e
                                                   userInfo:nil]
        }];
    }
    return entries;
}

void scanHeadersDirectory(id dir, HeaderOpenState *state) {
    NSError *err = nil;
    NSArray *entries = directoryContents(dir, &err);
    if (!entries && err) {
        const char *msg = [[NSString stringWithFormat:@"Unable to read %@ : %@",
                            dir, [err localizedDescription]] UTF8String];
        fputs(msg, stderr);
        fputc('\n', stderr);
        return;
    }
    for (NSDictionary *entry in entries) {
        NSString *name = entry[@"name"];
        NSString *full = [dir stringByAppendingPathComponent:name];
        if ([entry[@"dir"] boolValue])
            scanHeadersDirectory(full, state);
        else
            [state visitHeader:name atPath:full];
        if (state.finished) return;
    }
}

void scanFrameworksDirectory(id dir, HeaderOpenState *state) {
    NSError *err = nil;
    NSArray *entries = directoryContents(dir, &err);
    if (!entries && err) {
        const char *msg = [[NSString stringWithFormat:@"Unable to read %@ : %@",
                            dir, [err localizedDescription]] UTF8String];
        fputs(msg, stderr);
        fputc('\n', stderr);
        return;
    }
    for (NSDictionary *entry in entries) {
        if (![entry[@"dir"] boolValue]) continue;
        NSString *name = entry[@"name"];
        if (![name hasSuffix:@".framework"]) continue;

        NSString *fwPath  = [dir stringByAppendingPathComponent:name];
        NSString *headers = [fwPath stringByAppendingPathComponent:@"Headers"];
        NSString *priv    = [fwPath stringByAppendingPathComponent:@"PrivateHeaders"];
        NSString *nested  = [fwPath stringByAppendingPathComponent:@"Frameworks"];

        scanHeadersDirectory(headers, state);
        if (!state.finished) scanHeadersDirectory(priv, state);
        if (!state.finished) scanFrameworksDirectory(nested, state);
        if (state.finished) return;
    }
}

NSMutableArray *getSDKPathsForPlatform(NSURL *platformURL) {
    NSMutableArray *result = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *platformName = [[[platformURL lastPathComponent]
                                   stringByDeletingPathExtension] retain];

    NSURL *sdksDir = [[platformURL URLByAppendingPathComponent:@"Developer"]
                          URLByAppendingPathComponent:@"SDKs"];
    NSArray *rawSDKs = [fm contentsOfDirectoryAtURL:sdksDir
                         includingPropertiesForKeys:@[]
                                           options:0
                                             error:nil];

    // Filter to SDKs whose name starts with the platform name,
    // excluding Internal unless -H was passed, then sort descending by version.
    NSArray *filtered = [rawSDKs objectsAtIndexes:
        [rawSDKs indexesOfObjectsPassingTest:^BOOL(NSURL *sdk, __unused NSUInteger idx, __unused BOOL *stop) {
            NSString *last = [sdk lastPathComponent];
            if (gHideInternalSDKs
                && [last rangeOfString:@".Internal" options:NSCaseInsensitiveSearch].location
                    != NSNotFound)
                return NO;
            if (gSDKFilter)
                return [last containsString:gSDKFilter];
            return [last hasPrefix:platformName];
        }]];

    NSArray *sorted = [filtered sortedArrayUsingComparator:
        ^NSComparisonResult(NSURL *a, NSURL *b) {
            NSString *nameA = [a lastPathComponent];
            NSString *nameB = [b lastPathComponent];
            BOOL aInternal = NO;
            BOOL bInternal = NO;

            if (!gHideInternalSDKs) {
                NSRange rangeA = [nameA rangeOfString:@".Internal"
                                              options:NSCaseInsensitiveSearch];
                if (rangeA.length) {
                    nameA = [nameA stringByReplacingCharactersInRange:rangeA withString:@""];
                    aInternal = YES;
                }

                NSRange rangeB = [nameB rangeOfString:@".Internal"
                                              options:NSCaseInsensitiveSearch];
                if (rangeB.length) {
                    nameB = [nameB stringByReplacingCharactersInRange:rangeB withString:@""];
                    bInternal = YES;
                }
            }

            NSComparisonResult cmp = [nameA compare:nameB];
            if (cmp == NSOrderedDescending) return NSOrderedAscending;
            if (cmp == NSOrderedAscending) return NSOrderedDescending;
            if (bInternal) return NSOrderedAscending;
            if (aInternal) return NSOrderedDescending;
            return NSOrderedSame;
        }];

    NSURL *chosen = [sorted firstObject];

    if (gVerbose) {
        if (!chosen) {
            const char *msg = [[NSString stringWithFormat:
                @"For platform %@, no SDKs", platformName] UTF8String];
            fputs(msg, stderr);
            fputc('\n', stderr);
            [platformName release];
            return result;
        }
        NSMutableArray *names = [NSMutableArray array];
        for (NSURL *sdk in sorted)
            [names addObject:[sdk lastPathComponent]];
        const char *msg = [[NSString stringWithFormat:
            @"For platform %@, valid SDKs (using first one) = %@",
            platformName, names] UTF8String];
        fputs(msg, stderr);
        fputc('\n', stderr);
    } else if (!chosen) {
        [platformName release];
        return result;
    }

    // Sub-directories to search within the chosen SDK
    NSArray *subdirs = @[
        @"/System/Library/Frameworks/",
        @"/System/Library/PrivateFrameworks/",
        @"/usr/include/",
        @"/usr/local/include/"
    ];
    for (NSString *sub in subdirs) {
        NSURL *u = [chosen URLByAppendingPathComponent:sub];
        if ([u checkResourceIsReachableAndReturnError:nil])
            [result addObject:u];
    }
    [platformName release];
    return result;
}
