#import <AppKit/AppKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

static NSString * const LogPath = @"/tmp/vencord-portable-install.log";
static NSFileHandle *LogHandle = nil;

static NSString *DiscordAppPath(void) {
    NSString *overridePath = [NSProcessInfo processInfo].environment[@"DISCORD_APP_PATH"];
    if (overridePath.length > 0) {
        return overridePath;
    }
    return @"/Applications/Discord.app";
}

static NSString *DiscordResourcesPath(void) {
    return [DiscordAppPath() stringByAppendingPathComponent:@"Contents/Resources"];
}

static NSString *AppAsarPath(void) {
    return [DiscordResourcesPath() stringByAppendingPathComponent:@"app.asar"];
}

static NSString *BackupAppAsarPath(void) {
    return [DiscordResourcesPath() stringByAppendingPathComponent:@"_app.asar"];
}

static NSString *BuildDirPath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches/DiscordWithVencordPortable/build"];
}

static NSString *VencordDataDirPath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Vencord"];
}

static NSString *VencordDistDirPath(void) {
    return [VencordDataDirPath() stringByAppendingPathComponent:@"dist"];
}

static NSString *PatcherPath(void) {
    return [VencordDistDirPath() stringByAppendingPathComponent:@"patcher.js"];
}

static BOOL ShouldSkipLaunch(void) {
    NSString *value = [NSProcessInfo processInfo].environment[@"DISCORD_WITH_VENCORD_SKIP_LAUNCH"];
    return [value isEqualToString:@"1"] || [value.lowercaseString isEqualToString:@"true"];
}

static NSError *MakeError(NSString *message) {
    return [NSError errorWithDomain:@"DiscordWithVencordPortable"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static BOOL SetError(NSError **error, NSString *message) {
    if (error != NULL) {
        *error = MakeError(message);
    }
    return NO;
}

static void LogMessage(NSString *level, NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", level, message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (LogHandle != nil) {
        [LogHandle writeData:data];
    } else {
        fputs(line.UTF8String, stderr);
    }
}

static BOOL OpenLog(NSError **error) {
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createFileAtPath:LogPath contents:nil attributes:nil];
    LogHandle = [NSFileHandle fileHandleForWritingAtPath:LogPath];
    if (LogHandle == nil) {
        return SetError(error, [NSString stringWithFormat:@"Could not open %@", LogPath]);
    }
    [LogHandle truncateFileAtOffset:0];
    return YES;
}

static BOOL FileContainsBytes(NSString *path, NSData *needle) {
    if (needle.length == 0) {
        return NO;
    }

    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (data == nil) {
        return NO;
    }

    NSRange range = [data rangeOfData:needle options:0 range:NSMakeRange(0, data.length)];
    return range.location != NSNotFound;
}

static BOOL IsVencordWrapper(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSData *needle = [@"patcher.js" dataUsingEncoding:NSUTF8StringEncoding];
    return [fm fileExistsAtPath:AppAsarPath()] && FileContainsBytes(AppAsarPath(), needle);
}

static BOOL IsDiscordPatched(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSData *needle = [PatcherPath() dataUsingEncoding:NSUTF8StringEncoding];
    return [fm fileExistsAtPath:AppAsarPath()]
        && [fm fileExistsAtPath:BackupAppAsarPath()]
        && FileContainsBytes(AppAsarPath(), needle);
}

static BOOL DownloadURLToPath(NSURL *url, NSString *destination, NSError **error) {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 120;
    [request setValue:@"DiscordWithVencordPortable/1.0" forHTTPHeaderField:@"User-Agent"];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSData *downloadedData = nil;
    __block NSError *downloadError = nil;
    __block NSInteger statusCode = 200;

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *taskError) {
        if (taskError != nil) {
            downloadError = taskError;
        } else {
            NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
            if ([http isKindOfClass:[NSHTTPURLResponse class]]) {
                statusCode = http.statusCode;
            }
            downloadedData = data;
        }
        dispatch_semaphore_signal(semaphore);
    }];

    [task resume];
    long waitResult = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(150 * NSEC_PER_SEC)));
    if (waitResult != 0) {
        [task cancel];
        return SetError(error, [NSString stringWithFormat:@"Timed out downloading %@", url.lastPathComponent]);
    }

    if (downloadError != nil) {
        if (error != NULL) {
            *error = downloadError;
        }
        return NO;
    }

    if (statusCode < 200 || statusCode >= 300) {
        return SetError(error, [NSString stringWithFormat:@"HTTP %ld for %@", (long)statusCode, url.lastPathComponent]);
    }

    if (downloadedData == nil) {
        return SetError(error, [NSString stringWithFormat:@"No data returned for %@", url.lastPathComponent]);
    }

    return [downloadedData writeToFile:destination options:NSDataWritingAtomic error:error];
}

static BOOL DownloadVencordDist(NSError **error) {
    NSArray<NSString *> *assets = @[
        @"patcher.js",
        @"patcher.js.map",
        @"patcher.js.LEGAL.txt",
        @"preload.js",
        @"preload.js.map",
        @"renderer.js",
        @"renderer.js.map",
        @"renderer.js.LEGAL.txt",
        @"renderer.css",
        @"renderer.css.map"
    ];

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *tmpDir = [BuildDirPath() stringByAppendingPathComponent:@"vencord-dist-download"];
    if ([fm fileExistsAtPath:tmpDir] && ![fm removeItemAtPath:tmpDir error:error]) {
        return NO;
    }
    if (![fm createDirectoryAtPath:tmpDir withIntermediateDirectories:YES attributes:nil error:error]) {
        return NO;
    }

    LogMessage(@"info", @"Downloading latest Vencord files");
    for (NSString *asset in assets) {
        NSString *urlString = [NSString stringWithFormat:@"https://github.com/Vendicated/Vencord/releases/latest/download/%@", asset];
        NSURL *url = [NSURL URLWithString:urlString];
        NSError *downloadError = nil;
        NSString *destination = [tmpDir stringByAppendingPathComponent:asset];
        if (!DownloadURLToPath(url, destination, &downloadError)) {
            [fm removeItemAtPath:tmpDir error:nil];
            if ([fm fileExistsAtPath:PatcherPath()]) {
                LogMessage(@"info", @"Could not update Vencord files; using cached dist");
                return YES;
            }
            NSString *message = [NSString stringWithFormat:@"Could not download Vencord files and no cached dist exists: %@", downloadError.localizedDescription];
            return SetError(error, message);
        }
    }

    NSString *packageJSON = @"{}\n";
    NSString *packagePath = [tmpDir stringByAppendingPathComponent:@"package.json"];
    if (![packageJSON writeToFile:packagePath atomically:YES encoding:NSUTF8StringEncoding error:error]) {
        return NO;
    }

    NSArray<NSString *> *allAssets = [assets arrayByAddingObject:@"package.json"];
    for (NSString *asset in allAssets) {
        NSString *source = [tmpDir stringByAppendingPathComponent:asset];
        NSString *destination = [VencordDistDirPath() stringByAppendingPathComponent:asset];
        if ([fm fileExistsAtPath:destination] && ![fm removeItemAtPath:destination error:error]) {
            return NO;
        }
        if (![fm moveItemAtPath:source toPath:destination error:error]) {
            return NO;
        }
    }

    [fm removeItemAtPath:tmpDir error:nil];
    return YES;
}

static NSString *Timestamp(void) {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyyMMddHHmmss";
    return [formatter stringFromDate:[NSDate date]];
}

static BOOL PrepareDiscordForPatch(NSError **error) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:BackupAppAsarPath()] && !IsVencordWrapper()) {
        NSString *staleBackup = [DiscordResourcesPath() stringByAppendingPathComponent:[NSString stringWithFormat:@"_app.asar.stale.%@", Timestamp()]];
        LogMessage(@"info", @"Moving stale _app.asar backup to %@", staleBackup.lastPathComponent);
        if (![fm moveItemAtPath:BackupAppAsarPath() toPath:staleBackup error:error]) {
            return NO;
        }
    }
    return YES;
}

static void AppendInt32(NSMutableData *data, int32_t value) {
    uint32_t littleEndian = CFSwapInt32HostToLittle((uint32_t)value);
    [data appendBytes:&littleEndian length:sizeof(littleEndian)];
}

static NSData *MakeAppAsarWrapper(NSString *patcherPath, NSError **error) {
    NSString *packageJSON = @"{\n\t\"name\": \"discord\",\n\t\"main\": \"index.js\"\n}";
    NSData *patcherJSONData = [NSJSONSerialization dataWithJSONObject:patcherPath options:NSJSONWritingFragmentsAllowed error:error];
    if (patcherJSONData == nil) {
        return nil;
    }

    NSString *patcherJSON = [[NSString alloc] initWithData:patcherJSONData encoding:NSUTF8StringEncoding];
    if (patcherJSON == nil) {
        SetError(error, @"Could not encode patcher path");
        return nil;
    }
    patcherJSON = [patcherJSON stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"];

    NSString *indexJS = [NSString stringWithFormat:@"require(%@)", patcherJSON];
    NSUInteger indexSize = [indexJS lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    NSUInteger packageSize = [packageJSON lengthOfBytesUsingEncoding:NSUTF8StringEncoding];

    NSDictionary *headerObject = @{
        @"files": @{
            @"index.js": @{
                @"size": @(indexSize),
                @"offset": @"0"
            },
            @"package.json": @{
                @"size": @(packageSize),
                @"offset": [NSString stringWithFormat:@"%lu", (unsigned long)indexSize]
            }
        }
    };

    NSData *headerData = [NSJSONSerialization dataWithJSONObject:headerObject options:0 error:error];
    if (headerData == nil) {
        return nil;
    }

    NSString *headerString = [[NSString alloc] initWithData:headerData encoding:NSUTF8StringEncoding];
    if (headerString == nil) {
        SetError(error, @"Could not encode app.asar header");
        return nil;
    }

    NSUInteger headerStringSize = [headerString lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    NSUInteger dataSize = 4;
    NSUInteger alignedSize = (headerStringSize + dataSize - 1) & ~(dataSize - 1);
    NSUInteger headerSize = alignedSize + 8;
    NSUInteger headerObjectSize = alignedSize + dataSize;

    NSMutableString *paddedHeader = [headerString mutableCopy];
    if (alignedSize > headerStringSize) {
        [paddedHeader appendString:[@"" stringByPaddingToLength:alignedSize - headerStringSize withString:@"0" startingAtIndex:0]];
    }

    NSMutableData *output = [NSMutableData data];
    AppendInt32(output, (int32_t)dataSize);
    AppendInt32(output, (int32_t)headerSize);
    AppendInt32(output, (int32_t)headerObjectSize);
    AppendInt32(output, (int32_t)headerStringSize);
    [output appendData:[paddedHeader dataUsingEncoding:NSUTF8StringEncoding]];
    [output appendData:[indexJS dataUsingEncoding:NSUTF8StringEncoding]];
    [output appendData:[packageJSON dataUsingEncoding:NSUTF8StringEncoding]];
    return output;
}

static BOOL PatchDiscord(NSError **error) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:AppAsarPath()]) {
        return SetError(error, @"Discord app.asar not found");
    }

    BOOL movedOriginal = NO;
    NSError *innerError = nil;

    if ([fm fileExistsAtPath:BackupAppAsarPath()]) {
        if (!IsVencordWrapper()) {
            if (!PrepareDiscordForPatch(&innerError)) {
                if (error != NULL) {
                    *error = MakeError([NSString stringWithFormat:@"Failed to patch Discord: %@", innerError.localizedDescription]);
                }
                return NO;
            }
            LogMessage(@"info", @"Moving app.asar to _app.asar");
            if (![fm moveItemAtPath:AppAsarPath() toPath:BackupAppAsarPath() error:&innerError]) {
                if (error != NULL) {
                    *error = MakeError([NSString stringWithFormat:@"Failed to patch Discord: %@", innerError.localizedDescription]);
                }
                return NO;
            }
            movedOriginal = YES;
        }
    } else {
        LogMessage(@"info", @"Moving app.asar to _app.asar");
        if (![fm moveItemAtPath:AppAsarPath() toPath:BackupAppAsarPath() error:&innerError]) {
            if (error != NULL) {
                *error = MakeError([NSString stringWithFormat:@"Failed to patch Discord: %@", innerError.localizedDescription]);
            }
            return NO;
        }
        movedOriginal = YES;
    }

    NSData *wrapper = MakeAppAsarWrapper(PatcherPath(), &innerError);
    if (wrapper == nil || ![wrapper writeToFile:AppAsarPath() options:NSDataWritingAtomic error:&innerError]) {
        if (movedOriginal && ![fm fileExistsAtPath:AppAsarPath()]) {
            [fm moveItemAtPath:BackupAppAsarPath() toPath:AppAsarPath() error:nil];
        }
        if (error != NULL) {
            *error = MakeError([NSString stringWithFormat:@"Failed to patch Discord: %@", innerError.localizedDescription]);
        }
        return NO;
    }

    return YES;
}

static void CloseDiscordIfRunning(void) {
    NSMutableArray<NSRunningApplication *> *runningDiscordApps = [NSMutableArray array];
    NSURL *discordURL = [NSURL fileURLWithPath:DiscordAppPath()].standardizedURL;

    for (NSRunningApplication *app in [NSWorkspace sharedWorkspace].runningApplications) {
        if ([app.bundleIdentifier isEqualToString:@"com.hnc.Discord"]) {
            [runningDiscordApps addObject:app];
            continue;
        }
        if ([app.bundleURL.standardizedURL.path isEqualToString:discordURL.path]) {
            [runningDiscordApps addObject:app];
            continue;
        }
        if ([app.localizedName isEqualToString:@"Discord"]) {
            [runningDiscordApps addObject:app];
        }
    }

    if (runningDiscordApps.count == 0) {
        return;
    }

    LogMessage(@"info", @"Quitting Discord before patching");
    for (NSRunningApplication *app in runningDiscordApps) {
        [app terminate];
    }

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while ([deadline timeIntervalSinceNow] > 0) {
        BOOL allTerminated = YES;
        for (NSRunningApplication *app in runningDiscordApps) {
            if (!app.terminated) {
                allTerminated = NO;
                break;
            }
        }
        if (allTerminated) {
            return;
        }
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }

    for (NSRunningApplication *app in runningDiscordApps) {
        if (!app.terminated) {
            [app forceTerminate];
        }
    }
    [NSThread sleepForTimeInterval:1];
}

static BOOL LaunchDiscord(NSError **error) {
    NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
    configuration.activates = YES;

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSError *launchError = nil;

    [[NSWorkspace sharedWorkspace] openApplicationAtURL:[NSURL fileURLWithPath:DiscordAppPath()]
                                         configuration:configuration
                                     completionHandler:^(NSRunningApplication *app, NSError *openError) {
        launchError = openError;
        dispatch_semaphore_signal(semaphore);
    }];

    long waitResult = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC)));
    if (waitResult != 0) {
        return SetError(error, @"Timed out launching Discord");
    }

    if (launchError != nil) {
        if (error != NULL) {
            *error = MakeError([NSString stringWithFormat:@"Could not launch Discord: %@", launchError.localizedDescription]);
        }
        return NO;
    }

    return YES;
}

static BOOL RunLauncher(NSError **error) {
    NSFileManager *fm = [NSFileManager defaultManager];
    LogMessage(@"info", @"Starting at %@", [NSDate date]);

    BOOL isDirectory = NO;
    if (![fm fileExistsAtPath:DiscordAppPath() isDirectory:&isDirectory] || !isDirectory) {
        return SetError(error, [NSString stringWithFormat:@"Discord not found at %@", DiscordAppPath()]);
    }

    NSArray<NSString *> *directories = @[BuildDirPath(), VencordDataDirPath(), VencordDistDirPath()];
    for (NSString *directory in directories) {
        if (![fm createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:error]) {
            return NO;
        }
    }

    if (!DownloadVencordDist(error)) {
        return NO;
    }

    if (IsDiscordPatched()) {
        LogMessage(@"info", @"Discord is already patched");
    } else {
        CloseDiscordIfRunning();
        if (!PrepareDiscordForPatch(error)) {
            return NO;
        }
        LogMessage(@"info", @"Patching Discord");
        if (!PatchDiscord(error)) {
            return NO;
        }
    }

    if (!IsDiscordPatched()) {
        return SetError(error, @"Discord was not patched successfully");
    }

    if (ShouldSkipLaunch()) {
        LogMessage(@"info", @"Skipping Discord launch because DISCORD_WITH_VENCORD_SKIP_LAUNCH is set");
        return YES;
    }

    LogMessage(@"info", @"Launching Discord");
    return LaunchDiscord(error);
}

static void ShowFailureAlert(NSString *details) {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSApp activateIgnoringOtherApps:YES];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleCritical;
    alert.messageText = @"Vencord install failed";

    BOOL permissionProblem =
        [details rangeOfString:@"Operation not permitted" options:NSCaseInsensitiveSearch].location != NSNotFound
        || [details rangeOfString:@"permission" options:NSCaseInsensitiveSearch].location != NSNotFound;

    if (permissionProblem) {
        NSURL *settingsURL = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_AppManagement"];
        if (settingsURL != nil) {
            [[NSWorkspace sharedWorkspace] openURL:settingsURL];
        }
        alert.informativeText = @"macOS blocked changes to /Applications/Discord.app.\n\nOpen System Settings > Privacy & Security > App Management, enable Discord with Vencord Portable.app, then run it again.\n\nDetails are in /tmp/vencord-portable-install.log.";
    } else {
        alert.informativeText = [NSString stringWithFormat:@"%@\n\nDetails are in /tmp/vencord-portable-install.log.", details];
    }

    [alert runModal];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        NSError *error = nil;
        if (!OpenLog(&error)) {
            ShowFailureAlert(error.localizedDescription);
            return 1;
        }

        if (!RunLauncher(&error)) {
            LogMessage(@"error", @"%@", error.localizedDescription);
            ShowFailureAlert(error.localizedDescription);
            return 1;
        }

        [LogHandle closeFile];
        return 0;
    }
}
