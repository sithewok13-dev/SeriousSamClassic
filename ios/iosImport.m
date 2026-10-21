// Added: entire file. See iosImport.h. Built with ARC (see the CMake file that
// lists the iOS sources), and only for iOS, so no platform #ifdef.

#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include "iosImport.h"

// The staging folder: hidden from the Files app (the name starts with a dot)
#define IOSIMPORT_STAGING ".importing"

// ---- reading files: iCloud Drive files are downloaded first ------------------

static FILE* iosImport_Open(const char* path, void* user)
{
    (void)user;
    __block FILE* f = NULL;
    @autoreleasepool {
        NSURL* url = [NSURL fileURLWithFileSystemRepresentation:path isDirectory:NO relativeToURL:nil];
        NSFileCoordinator* c = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        NSError* err = nil;
        [c coordinateReadingItemAtURL:url options:0 error:&err byAccessor:^(NSURL* u) {
            f = fopen(u.fileSystemRepresentation, "rb");
        }];
    }
    return f ? f : fopen(path, "rb");
}

static void iosImport_Progress(int64_t done, int64_t total, const char* name, void* user);

static NSString* iosImport_Bytes(int64_t n)
{
    return [NSByteCountFormatter stringFromByteCount:n countStyle:NSByteCountFormatterCountStyleFile];
}

static NSString* iosImport_Str(const char* s)
{
    return s ? [NSString stringWithUTF8String:s] : @"";
}

// ---- the screen ----------------------------------------------------------------

@interface IOSImportViewController : UIViewController <UIDocumentPickerDelegate>
@property (nonatomic) const iosImportGame* game;
@property (nonatomic) const iosImportText* text;
@property (nonatomic, copy) NSString* docs;
@property (nonatomic, copy) NSString* dest;
@property (nonatomic) BOOL finished;
@end

@implementation IOSImportViewController {
    UILabel* _title;
    UILabel* _body;
    UILabel* _status;
    UIProgressView* _progress;
    UIButton* _primary;
    UIButton* _help;
    UIActivityIndicatorView* _spinner;
    BOOL _busy;
    BOOL _done;
    BOOL _looked;
    NSArray<NSURL*>* _localFound; // files found in the app's own folder
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskLandscape;
}

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

- (UILabel*)label:(CGFloat)size weight:(UIFontWeight)weight
{
    UILabel* l = [[UILabel alloc] init];
    l.font = [UIFont systemFontOfSize:size weight:weight];
    l.textColor = UIColor.whiteColor;
    l.numberOfLines = 0;
    l.textAlignment = NSTextAlignmentCenter;
    l.adjustsFontForContentSizeCategory = YES;
    return l;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];

    _title = [self label:24 weight:UIFontWeightBold];
    _title.text = iosImport_Str(self.text->title);
    _body = [self label:16 weight:UIFontWeightRegular];
    _body.textColor = [UIColor colorWithWhite:0.85 alpha:1.0];
    _body.text = iosImport_Str(self.text->body);

    UIButtonConfiguration* pc = [UIButtonConfiguration filledButtonConfiguration];
    pc.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    pc.buttonSize = UIButtonConfigurationSizeLarge;
    pc.contentInsets = NSDirectionalEdgeInsetsMake(14, 28, 14, 28);
    _primary = [UIButton buttonWithConfiguration:pc primaryAction:nil];
    [_primary addTarget:self action:@selector(primaryTapped) forControlEvents:UIControlEventTouchUpInside];
    [self setPrimaryTitle:@"Choose Game Files"];

    UIButtonConfiguration* hc = [UIButtonConfiguration plainButtonConfiguration];
    hc.title = [NSString stringWithFormat:@"Where do I find the %@ files?", iosImport_Str(self.text->gameName)];
    _help = [UIButton buttonWithConfiguration:hc primaryAction:nil];
    [_help addTarget:self action:@selector(helpTapped) forControlEvents:UIControlEventTouchUpInside];

    _status = [self label:16 weight:UIFontWeightSemibold];
    _status.hidden = YES;

    _progress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    _progress.hidden = YES;

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _spinner.color = UIColor.whiteColor;
    _spinner.hidesWhenStopped = YES;

    UIStackView* stack = [[UIStackView alloc] initWithArrangedSubviews:@[ _title, _body, _primary, _spinner, _status, _progress, _help ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 14;
    [stack setCustomSpacing:22 afterView:_body];
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    UIScrollView* scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    [self.view addSubview:scroll];
    [scroll addSubview:stack];

    UILayoutGuide* safe = self.view.safeAreaLayoutGuide;
    UILayoutGuide* content = scroll.contentLayoutGuide;
    UILayoutGuide* frame = scroll.frameLayoutGuide;
    NSLayoutConstraint* center = [stack.centerYAnchor constraintEqualToAnchor:frame.centerYAnchor];
    center.priority = UILayoutPriorityDefaultLow;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [stack.topAnchor constraintGreaterThanOrEqualToAnchor:content.topAnchor constant:20],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:content.bottomAnchor constant:-20],
        [content.heightAnchor constraintGreaterThanOrEqualToAnchor:frame.heightAnchor],
        center,
        [stack.centerXAnchor constraintEqualToAnchor:frame.centerXAnchor],
        [stack.widthAnchor constraintLessThanOrEqualToConstant:600],
        [stack.widthAnchor constraintLessThanOrEqualToAnchor:frame.widthAnchor constant:-40],
        [_title.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [_body.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [_status.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [_progress.widthAnchor constraintEqualToAnchor:stack.widthAnchor multiplier:0.8],
    ]];
    NSLayoutConstraint* wide = [stack.widthAnchor constraintEqualToConstant:600];
    wide.priority = UILayoutPriorityDefaultHigh;
    wide.active = YES;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if (!_looked) {
        _looked = YES;
        [self lookInAppFolder];
    }
}

- (void)setPrimaryTitle:(NSString*)t
{
    UIButtonConfiguration* c = _primary.configuration;
    c.title = t;
    _primary.configuration = c;
}

- (void)showStatus:(NSString*)s error:(BOOL)bError
{
    _status.text = s;
    _status.textColor = bError ? [UIColor colorWithRed:1.0 green:0.55 blue:0.5 alpha:1.0] : UIColor.whiteColor;
    _status.hidden = (s.length == 0);
}

- (void)setBusy:(BOOL)busy
{
    _busy = busy;
    _primary.enabled = !busy;
    _help.enabled = !busy;
    if (busy) [_spinner startAnimating]; else [_spinner stopAnimating];
}

// ---- actions ----

- (void)primaryTapped
{
    if (_busy) return;
    if (_done) {
        self.finished = YES;
        return;
    }
    if (_localFound) {
        [self importURLs:_localFound fromAppFolder:YES];
        return;
    }
    NSArray<UTType*>* types = @[ UTTypeFolder, UTTypeData ];
    UIDocumentPickerViewController* p = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:NO];
    p.allowsMultipleSelection = YES;
    p.delegate = self;
    p.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:p animated:YES completion:nil];
}

- (void)helpTapped
{
    UIAlertController* a = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Finding the %@ files", iosImport_Str(self.text->gameName)]
                                                                message:iosImport_Str(self.text->help)
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController*)controller didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls
{
    if (urls.count) [self importURLs:urls fromAppFolder:NO];
}

// ---- finding and importing ----

// Game files the player already put in the app's folder, but not where the
// game looks: offered first, and moved instead of copied.
- (void)lookInAppFolder
{
    [self setBusy:YES];
    NSString* docs = self.docs;
    NSString* dest = self.dest;
    const iosImportGame* game = self.game;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        iosImportIndex* idx = iosImport_NewIndex();
        const char* skip[] = { IOSIMPORT_STAGING, "Screenshots", "Inbox", NULL };
        iosImport_AddFolderContents(idx, docs.fileSystemRepresentation, skip, iosImport_Open, NULL);
        iosImportPlan plan;
        iosImport_Plan(idx, game, dest.fileSystemRepresentation, &plan);
        iosImport_FreeIndex(idx);
        int status = plan.status;
        NSString* where = [NSString stringWithUTF8String:plan.root] ?: @"";
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setBusy:NO];
            if (status != IOSIMPORT_OK) return;
            self->_localFound = @[ [NSURL fileURLWithPath:docs isDirectory:YES] ];
            [self setPrimaryTitle:@"Use These Files"];
            NSString* shown = where.length ? [NSString stringWithFormat:@"“%@”", where] : @"the app's folder";
            [self showStatus:[NSString stringWithFormat:@"Found your %@ files in %@ in the Files app. Tap Use These Files to put them where the game looks.",
                                                        iosImport_Str(self.text->gameName), shown]
                       error:NO];
        });
    });
}

- (void)importURLs:(NSArray<NSURL*>*)urls fromAppFolder:(BOOL)bLocal
{
    [self setBusy:YES];
    [self showStatus:@"Looking at your files…" error:NO];

    NSMutableArray<NSURL*>* scoped = [NSMutableArray array];
    for (NSURL* u in urls) {
        if ([u startAccessingSecurityScopedResource]) [scoped addObject:u];
    }
    NSString* docs = self.docs;
    NSString* dest = self.dest;
    const iosImportGame* game = self.game;
    const iosImportText* text = self.text;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        iosImportIndex* idx = iosImport_NewIndex();
        if (bLocal) {
            const char* skip[] = { IOSIMPORT_STAGING, "Screenshots", "Inbox", NULL };
            iosImport_AddFolderContents(idx, docs.fileSystemRepresentation, skip, iosImport_Open, NULL);
        } else {
            for (NSURL* u in urls) iosImport_AddItem(idx, u.fileSystemRepresentation, iosImport_Open, NULL);
        }
        iosImportPlan plan;
        iosImport_Plan(idx, game, dest.fileSystemRepresentation, &plan);

        NSString* problem = nil;
        if (plan.status == IOSIMPORT_WRONG_GAME) {
            problem = iosImport_Str(text->wrongGame);
        } else if (plan.status == IOSIMPORT_PARTIAL) {
            NSMutableArray* names = [NSMutableArray array];
            for (int i = 0; i < plan.missingCount; i++) {
                NSString* m = iosImport_Str(plan.missing[i]);
                if ([m hasSuffix:@"/"]) m = [NSString stringWithFormat:@"the %@ folder", [m substringToIndex:m.length - 1]];
                [names addObject:m];
            }
            problem = [NSString stringWithFormat:@"That's only part of the game. Missing: %@.\n\n%@",
                                                 [names componentsJoinedByString:@", "], iosImport_Str(text->whatToPick)];
        } else if (plan.status == IOSIMPORT_BAD_ZIP) {
            problem = [NSString stringWithFormat:@"Couldn't open “%@”. It may be damaged or still downloading. Tap it in the Files app to unpack it, then pick the folder it makes.",
                                                 iosImport_Str(plan.badZip)];
        } else if (plan.status == IOSIMPORT_NOTHING) {
            problem = [NSString stringWithFormat:@"No %@ files in what you picked.\n\n%@",
                                                 iosImport_Str(text->gameName), iosImport_Str(text->whatToPick)];
        }

        // Room for the copy (moving needs none)
        BOOL bMove = bLocal && plan.bAllLocal;
        if (!problem && !bMove) {
            NSURL* d = [NSURL fileURLWithPath:docs isDirectory:YES];
            NSNumber* freeSpace = nil;
            [d getResourceValue:&freeSpace forKey:NSURLVolumeAvailableCapacityForImportantUsageKey error:nil];
            int64_t need = plan.totalBytes + (100LL << 20);
            if (freeSpace && freeSpace.longLongValue < need) {
                problem = [NSString stringWithFormat:@"Not enough space: the game needs %@, and this iPhone has %@ free. Free up %@ (Settings > General > iPhone Storage) and try again.",
                                                     iosImport_Bytes(plan.totalBytes), iosImport_Bytes(freeSpace.longLongValue),
                                                     iosImport_Bytes(need - freeSpace.longLongValue)];
            }
        }

        const char* err = NULL;
        if (!problem) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showStatus:bMove ? @"Moving your files into place…" : @"Copying… Keep the app open until it's done." error:NO];
                self->_progress.progress = 0;
                self->_progress.hidden = NO;
            });
            __block UIBackgroundTaskIdentifier bg = UIBackgroundTaskInvalid;
            dispatch_sync(dispatch_get_main_queue(), ^{
                UIApplication.sharedApplication.idleTimerDisabled = YES;
                bg = [UIApplication.sharedApplication beginBackgroundTaskWithExpirationHandler:^{
                    [UIApplication.sharedApplication endBackgroundTask:bg];
                    bg = UIBackgroundTaskInvalid;
                }];
            });
            NSString* staging = [docs stringByAppendingPathComponent:@IOSIMPORT_STAGING];
            err = iosImport_Install(idx, game, &plan, staging.fileSystemRepresentation, dest.fileSystemRepresentation, bMove,
                                    iosImport_Open, iosImport_Progress, (__bridge void*)self);
            dispatch_sync(dispatch_get_main_queue(), ^{
                UIApplication.sharedApplication.idleTimerDisabled = NO;
                if (bg != UIBackgroundTaskInvalid) [UIApplication.sharedApplication endBackgroundTask:bg];
            });
            if (err) problem = [NSString stringWithFormat:@"%s Nothing was changed if the copy didn't finish, so you can just try again.", err];
        }

        NSMutableArray* missingOpt = [NSMutableArray array];
        for (int i = 0; i < plan.missingOptionalCount; i++) [missingOpt addObject:iosImport_Str(plan.missingOptional[i])];
        iosImport_FreeIndex(idx);

        dispatch_async(dispatch_get_main_queue(), ^{
            for (NSURL* u in scoped) [u stopAccessingSecurityScopedResource];
            [self setBusy:NO];
            self->_progress.hidden = YES;
            if (problem) {
                self->_localFound = nil;
                [self setPrimaryTitle:@"Choose Game Files"];
                [self showStatus:problem error:YES];
                return;
            }
            NSString* done = [NSString stringWithFormat:@"All set! %@ is ready to play.", iosImport_Str(text->gameName)];
            if (missingOpt.count) {
                NSString* list = [missingOpt componentsJoinedByString:@" or "];
                done = [done stringByAppendingFormat:@"\n\nNo %@ was found in what you picked, so the game will play without it. You can add it later the same way.", list];
            }
            self->_done = YES;
            [self setPrimaryTitle:@"Start Game"];
            [self showStatus:done error:NO];
        });
    });
}

static void iosImport_Progress(int64_t done, int64_t total, const char* name, void* user)
{
    (void)name;
    IOSImportViewController* vc = (__bridge IOSImportViewController*)user;
    dispatch_async(dispatch_get_main_queue(), ^{
        [vc progressDone:done total:total];
    });
}

- (void)progressDone:(int64_t)done total:(int64_t)total
{
    if (_progress.hidden) return;
    float f = total > 0 ? (float)((double)done / (double)total) : 0.0f;
    _progress.progress = f > 1.0f ? 1.0f : f;
    _status.text = [NSString stringWithFormat:@"Copying… %@ of %@\nKeep the app open until it's done.", iosImport_Bytes(done), iosImport_Bytes(total)];
}

@end

// ---- running it ------------------------------------------------------------------

int iosImport_RunScreen(const iosImportGame* game, const iosImportText* text, const char* pDocs, const char* pDest)
{
    @autoreleasepool {
        UIWindowScene* scene = nil;
        for (UIScene* s in UIApplication.sharedApplication.connectedScenes) {
            if (![s isKindOfClass:[UIWindowScene class]]) continue;
            scene = (UIWindowScene*)s;
            if (s.activationState == UISceneActivationStateForegroundActive) break;
        }
        UIWindow* prevKey = nil;
        if (scene) {
            for (UIWindow* w in scene.windows) {
                if (w.isKeyWindow) prevKey = w;
            }
        }
        UIWindow* window = scene ? [[UIWindow alloc] initWithWindowScene:scene]
                                 : [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        if (!window) return 0;

        IOSImportViewController* vc = [[IOSImportViewController alloc] init];
        vc.game = game;
        vc.text = text;
        vc.docs = [NSString stringWithUTF8String:pDocs];
        vc.dest = [NSString stringWithUTF8String:pDest];
        window.windowLevel = UIWindowLevelNormal + 1;
        window.rootViewController = vc;
        [window makeKeyAndVisible];

        while (!vc.finished) {
            @autoreleasepool {
                CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
            }
        }

        window.hidden = YES;
        window.rootViewController = nil;
        [prevKey makeKeyWindow];
    }
    return 1;
}
