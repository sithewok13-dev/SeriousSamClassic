// The CAMERA button's photos (as the Jedi Knight port's iosPhotos): adds
// the touch overlay to the HUD shot, then saves them to Photos (add-only
// access), or to the app's Files folder (Screenshots) if that access is off
// or saving fails. Built with ARC (ios_app.cmake).

#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <ImageIO/ImageIO.h>
#import <QuartzCore/QuartzCore.h>
#include <mach/mach.h>

#include "IOSCapture.h"
#include "IOSPhotos.h"

// IOSTouch.m
UIView *IOSTouch_OverlayView(void);
void IOSTouch_CameraFeedback(int mode);
int IOSTouch_IsFpsShown(void);

// Encoding and saving, one capture after another in the order they were
// taken (so a burst's photos are saved in order), off the game's thread
static dispatch_queue_t IOSPhotos_Queue(void)
{
  static dispatch_queue_t q = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    q = dispatch_queue_create("serioussam.photos", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0));
  });
  return q;
}

// The app's memory now (what iOS counts against it), in MB; -1 if unknown
static double IOSPhotos_FootprintMB(void)
{
  task_vm_info_data_t info;
  mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
  if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) != KERN_SUCCESS) return -1.0;
  return (double)info.phys_footprint / (1024.0 * 1024.0);
}
static double _peakFootprintMB = 0;

static void IOSPhotos_FreeBytes(void *info, const void *data, size_t size)
{
  free((void *)data);
}

// A CGImage over w x h RGBA bytes (top row first, opaque); it frees them
static CGImageRef IOSPhotos_MakeImage(unsigned char *p, int w, int h)
{
  CGDataProviderRef prov = CGDataProviderCreateWithData(NULL, p, (size_t)w * h * 4, IOSPhotos_FreeBytes);
  if (!prov) {
    free(p);
    return NULL;
  }
  CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGImageRef img = CGImageCreate(w, h, 8, 32, (size_t)w * 4, cs,
                                   kCGBitmapByteOrderDefault | kCGImageAlphaNoneSkipLast,
                                   prov, NULL, false, kCGRenderingIntentDefault);
  CGColorSpaceRelease(cs);
  CGDataProviderRelease(prov);
  return img;
}

static NSData *IOSPhotos_Png(CGImageRef img)
{
  NSMutableData *data = [NSMutableData data];
  CGImageDestinationRef dst = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data, (__bridge CFStringRef)@"public.png", 1, NULL);
  if (!dst) return nil;
  CGImageDestinationAddImage(dst, img, NULL);
  BOOL bOk = CGImageDestinationFinalize(dst);
  CFRelease(dst);
  return bOk ? data : nil;
}

// What the photos are called: "Sam SE 2026-10-11 14.05.09 clean.png"
static NSString *IOSPhotos_BaseName(NSDate *when)
{
  NSDateFormatter *f = [[NSDateFormatter alloc] init];
  f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
  f.dateFormat = @"yyyy-MM-dd HH.mm.ss";
  NSString *app = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];
  if (![app isKindOfClass:[NSString class]] || !app.length) app = @"Serious Sam";
  NSString *base = [NSString stringWithFormat:@"%@ %@", app, [f stringFromDate:when]];
  // A second capture in the same second gets "-2", "-3"... so no file
  // overwrites another (main thread only)
  static NSString *lastBase = nil;
  static int sameSecond = 0;
  if (lastBase && [lastBase isEqualToString:base]) {
    sameSecond++;
  }
  else {
    lastBase = base;
    sameSecond = 1;
  }
  return sameSecond > 1 ? [NSString stringWithFormat:@"%@-%d", base, sameSecond] : base;
}

// One line on the game's message line once nothing more is being saved (and
// no burst is still going), counting everything since the last line: so a
// burst says "10 photos saved" once, not ten times. Main thread only.
static int _numPending = 0;
static int _bBatch = 0;
static int _numToPhotos = 0, _numToFiles = 0, _numFailed = 0;
static int _bPhotosOff = 0;
static int _burstShot = 0; // numbers a burst's photos, so they sort in order

static void IOSPhotos_Report(void)
{
  char msg[128];
  int n = 0;
  if (_numPending > 0 || _bBatch) return;
  msg[0] = 0;
  if (_numToPhotos)
    n += snprintf(msg + n, sizeof(msg) - n, _numToPhotos == 1 ? "1 photo saved" : "%d photos saved", _numToPhotos);
  if (_numToFiles && n < (int)sizeof(msg))
    n += snprintf(msg + n, sizeof(msg) - n, "%s%d saved to Files (%s)", n ? ", " : "", _numToFiles,
                      _bPhotosOff ? "Photos access is off" : "Photos didn't take them");
  if (_numFailed && n < (int)sizeof(msg))
    n += snprintf(msg + n, sizeof(msg) - n, "%s%d couldn't be saved", n ? ", " : "", _numFailed);
  if (!msg[0]) return;
  // (taken whether shown or not, so a later message shows only its own)
  IOSCaptureStats st;
  IOSCapture_TakeStats(&st);
  if (IOSTouch_IsFpsShown() && n < (int)sizeof(msg)) {
    // With the FPS readout on, how the photos went: the frame read back,
    // the save (from the frame read to saved, waiting behind any earlier
    // photos included), the held images and the app's memory at their
    // most, and how long a selfie held the game
    n += snprintf(msg + n, sizeof(msg) - n, " [read %.0f ms, save %.2f s, held %.0f MB, app %.0f MB", st.readSeconds * 1000.0,
                      st.saveSeconds, (double)st.peakBytes / (1024.0 * 1024.0), _peakFootprintMB);
    if (st.freezeSeconds > 0 && n < (int)sizeof(msg))
      n += snprintf(msg + n, sizeof(msg) - n, ", freeze %.2f s", st.freezeSeconds);
    if (n < (int)sizeof(msg)) snprintf(msg + n, sizeof(msg) - n, "]");
  }
  _peakFootprintMB = 0;
  IOS_ShowCameraMessage(msg);
  _numToPhotos = _numToFiles = _numFailed = 0;
  _bPhotosOff = 0;
}

// One capture's photos are saved (toPhotos), or in Files (toFiles), or not;
// the capture held `bytes` of images, taken at t0 (CACurrentMediaTime)
static void IOSPhotos_Finish(int toPhotos, int toFiles, int failed, int bPhotosOff, long bytes, double t0)
{
  const double mb = IOSPhotos_FootprintMB();
  dispatch_async(dispatch_get_main_queue(), ^{
    if (mb > _peakFootprintMB) _peakFootprintMB = mb;
    _numToPhotos += toPhotos;
    _numToFiles += toFiles;
    _numFailed += failed;
    if (bPhotosOff) _bPhotosOff = 1;
    if (_numPending > 0) _numPending--;
    IOSCapture_Done(bytes, CACurrentMediaTime() - t0);
    IOSPhotos_Report();
  });
}

void IOSPhotos_SetBatch(int bOn)
{
  _bBatch = bOn != 0;
  if (bOn) _burstShot = 0;
  IOSPhotos_Report();
}

// The PNGs into Documents/Screenshots (shown in the Files app)
static int IOSPhotos_SaveToFiles(NSArray<NSData *> *aData, NSArray<NSString *> *aName)
{
  NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
  if (!docs) return 0;
  NSString *dir = [docs stringByAppendingPathComponent:@"Screenshots"];
  [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
  int n = 0;
  for (NSUInteger i = 0; i < aData.count; i++) {
    if ([aData[i] writeToFile:[dir stringByAppendingPathComponent:aName[i]] atomically:YES]) n++;
  }
  return n;
}

// (numBad: photos of this capture already lost, counted with the rest)
static void IOSPhotos_Save(NSArray<NSData *> *aData, NSArray<NSString *> *aName, NSDate *when, int numBad, long bytes, double t0)
{
  int n = (int)aData.count;
  PHAuthorizationStatus st = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelAddOnly];
  if (st != PHAuthorizationStatusAuthorized && st != PHAuthorizationStatusLimited) {
    int k = IOSPhotos_SaveToFiles(aData, aName);
    IOSPhotos_Finish(0, k, n - k + numBad, 1, bytes, t0);
    return;
  }
  [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
    for (NSUInteger i = 0; i < aData.count; i++) {
      PHAssetCreationRequest *req = [PHAssetCreationRequest creationRequestForAsset];
      PHAssetResourceCreationOptions *opt = [[PHAssetResourceCreationOptions alloc] init];
      opt.originalFilename = aName[i];
      [req addResourceWithType:PHAssetResourceTypePhoto data:aData[i] options:opt];
      req.creationDate = when;
    }
  } completionHandler:^(BOOL bOk, NSError *err) {
    if (bOk) {
      IOSPhotos_Finish(n, 0, numBad, 0, bytes, t0);
    }
    else {
      int k = IOSPhotos_SaveToFiles(aData, aName);
      IOSPhotos_Finish(0, k, n - k + numBad, 0, bytes, t0);
    }
  }];
}

void IOSPhotos_SaveCapture(unsigned char *pClean, unsigned char *pHud, int w, int h, int kinds, int mode)
{
  const int bBurst = mode == IOSCAPTURE_MODE_BURST;
  // (counted against the capture budget until saved: IOSCapture_Done)
  // (the HUD with the buttons is a third image, made here from the HUD one)
  const long bytes = (long)w * h * 4 * ((pClean ? 1 : 0) + (pHud ? 1 : 0) + ((pHud && (kinds & IOSCAPTURE_HUDBTNS)) ? 1 : 0));
  const double t0 = CACurrentMediaTime();
  @autoreleasepool {
    _numPending++;
    CGImageRef clean = pClean ? IOSPhotos_MakeImage(pClean, w, h) : NULL;
    CGImageRef hud = pHud ? IOSPhotos_MakeImage(pHud, w, h) : NULL;
    CGImageRef hudBtns = NULL;
    if (hud && (kinds & IOSCAPTURE_HUDBTNS)) {
      // The touch overlay on top of the game's frame, as the player sees
      // it, in this same frame. (UIKit views aren't in the GL frame.)
      UIView *overlay = IOSTouch_OverlayView();
      UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
      fmt.scale = 1.0;
      fmt.opaque = YES;
      fmt.preferredRange = UIGraphicsImageRendererFormatRangeStandard; // 8-bit sRGB, as the others
      UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(w, h) format:fmt];
      UIImage *out = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef c = ctx.CGContext;
        [[UIImage imageWithCGImage:hud] drawInRect:CGRectMake(0, 0, w, h)];
        if (overlay && !overlay.hidden && overlay.bounds.size.width > 0 && overlay.bounds.size.height > 0) {
          CGContextSaveGState(c);
          CGContextScaleCTM(c, w / overlay.bounds.size.width, h / overlay.bounds.size.height);
          [overlay.layer renderInContext:c];
          CGContextRestoreGState(c);
        }
      }];
      hudBtns = CGImageRetain(out.CGImage);
    }

    // What to save, in this order: clean, HUD, HUD with the buttons
    CGImageRef aImg[3] = { NULL, NULL, NULL };
    int n = 0, numMissing = 0;
    if (kinds & IOSCAPTURE_CLEAN) { if (clean) aImg[0] = CGImageRetain(clean); else numMissing++; }
    if (kinds & IOSCAPTURE_HUD) { if (hud) aImg[1] = CGImageRetain(hud); else numMissing++; }
    if (kinds & IOSCAPTURE_HUDBTNS) { if (hudBtns) aImg[2] = CGImageRetain(hudBtns); else numMissing++; }
    CGImageRelease(clean);
    CGImageRelease(hud);
    CGImageRelease(hudBtns);
    for (int i = 0; i < 3; i++) n += aImg[i] != NULL;
    if (!n) {
      IOSPhotos_Finish(0, 0, numMissing ? numMissing : 1, 0, bytes, t0);
      return;
    }

    // The flash, the shutter and a tap, now the frame is taken, so none
    // of them is in it (lighter for each shot of a burst)
    IOSTouch_CameraFeedback(mode);

    NSDate *when = [NSDate date];
    NSString *base = IOSPhotos_BaseName(when);
    if (bBurst)
      base = [base stringByAppendingFormat:@" burst %02d", ++_burstShot];
    else if (mode == IOSCAPTURE_MODE_SELFIE && _bBatch)
      base = [base stringByAppendingFormat:@" selfie %d", ++_burstShot]; // (one of several)
    // (Blocks can't take C arrays)
    CGImageRef img0 = aImg[0], img1 = aImg[1], img2 = aImg[2];
    const BOOL bNumbered = bBurst || (mode == IOSCAPTURE_MODE_SELFIE && _bBatch);
    dispatch_async(IOSPhotos_Queue(), ^{
      NSMutableArray<NSData *> *aData = [NSMutableArray array];
      NSMutableArray<NSString *> *aName = [NSMutableArray array];
      int numBad = numMissing;
      CGImageRef aJob[3] = { img0, img1, img2 };
      NSString *aJobSuffix[3] = { @"clean", @"hud", @"hud+buttons" };
      for (int i = 0; i < 3; i++) {
        if (!aJob[i]) continue;
        @autoreleasepool {
          NSData *png = IOSPhotos_Png(aJob[i]);
          if (png) {
            [aData addObject:png];
            [aName addObject:bNumbered ? [base stringByAppendingString:@".png"]
                        : [NSString stringWithFormat:@"%@ %@.png", base, mode == IOSCAPTURE_MODE_SELFIE ? @"selfie" : aJobSuffix[i]]];
          }
          else {
            numBad++;
          }
        }
        CGImageRelease(aJob[i]);
      }
      if (!aData.count) {
        IOSPhotos_Finish(0, 0, numBad, 0, bytes, t0);
        return;
      }
      IOSPhotos_Save(aData, aName, when, numBad, bytes, t0);
    });
  }
}

int IOSPhotos_AskAccess(void (*done)(void))
{
  if ([PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelAddOnly] != PHAuthorizationStatusNotDetermined)
    return 0;
  [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus st) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (done) done();
    });
  }];
  return 1;
}

