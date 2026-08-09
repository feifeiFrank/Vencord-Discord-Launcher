#import <AppKit/AppKit.h>
#import <CommonCrypto/CommonDigest.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/file.h>
#include <unistd.h>

static NSString * const DefaultLogPath = @"/tmp/vencord-portable-install.log";
static NSFileHandle *LogHandle = nil;
static int LauncherLockFileDescriptor = -1;
static const unsigned long long MaxWrapperSize = 1024 * 1024;
static const NSTimeInterval VencordUpdateCheckInterval = 60 * 60;
static BOOL SetError(NSError **error, NSString *message);

static NSString *DiscordAppPath(void) {
    NSString *overridePath = [NSProcessInfo processInfo].environment[@"DISCORD_APP_PATH"];
    if (overridePath.length > 0) {
        return overridePath;
    }
    return @"/Applications/Discord.app";
}

static NSString *LauncherLogPath(void) {
    NSString *overridePath = [NSProcessInfo processInfo].environment[@"DISCORD_WITH_VENCORD_LOG_PATH"];
    return overridePath.length > 0 ? overridePath : DefaultLogPath;
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

static NSString *VencordDataDirPath(void) {
    NSString *overridePath = [NSProcessInfo processInfo].environment[@"VENCORD_USER_DATA_DIR"];
    if (overridePath.length > 0) {
        return overridePath.stringByExpandingTildeInPath.stringByStandardizingPath;
    }
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

static BOOL EnvironmentFlagIsEnabled(NSString *name) {
    NSString *value = [NSProcessInfo processInfo].environment[name];
    return [value isEqualToString:@"1"] || [value.lowercaseString isEqualToString:@"true"];
}

static BOOL ShouldRunHeadless(void) {
    return EnvironmentFlagIsEnabled(@"DISCORD_WITH_VENCORD_HEADLESS");
}

static BOOL AcquireLauncherLock(NSError **error) {
    NSString *lockPath = [VencordDataDirPath() stringByAppendingPathComponent:@"launcher.lock"];
    int descriptor = open(lockPath.fileSystemRepresentation, O_CREAT | O_RDWR, 0600);
    if (descriptor < 0) {
        NSError *lockError = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        return SetError(error, [NSString stringWithFormat:@"Could not open launcher lock: %@", lockError.localizedDescription]);
    }

    int descriptorFlags = fcntl(descriptor, F_GETFD);
    if (descriptorFlags < 0 || fcntl(descriptor, F_SETFD, descriptorFlags | FD_CLOEXEC) != 0) {
        int lockErrorCode = errno;
        close(descriptor);
        NSError *lockError = [NSError errorWithDomain:NSPOSIXErrorDomain code:lockErrorCode userInfo:nil];
        return SetError(error, [NSString stringWithFormat:@"Could not configure launcher lock: %@", lockError.localizedDescription]);
    }

    if (flock(descriptor, LOCK_EX | LOCK_NB) != 0) {
        int lockErrorCode = errno;
        close(descriptor);
        if (lockErrorCode == EWOULDBLOCK) {
            return SetError(error, @"Another Discord with Vencord Portable launch is already in progress");
        }
        NSError *lockError = [NSError errorWithDomain:NSPOSIXErrorDomain code:lockErrorCode userInfo:nil];
        return SetError(error, [NSString stringWithFormat:@"Could not acquire launcher lock: %@", lockError.localizedDescription]);
    }

    LauncherLockFileDescriptor = descriptor;
    return YES;
}

static void ReleaseLauncherLock(void) {
    if (LauncherLockFileDescriptor < 0) {
        return;
    }
    flock(LauncherLockFileDescriptor, LOCK_UN);
    close(LauncherLockFileDescriptor);
    LauncherLockFileDescriptor = -1;
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
    [fm createFileAtPath:LauncherLogPath() contents:nil attributes:nil];
    LogHandle = [NSFileHandle fileHandleForWritingAtPath:LauncherLogPath()];
    if (LogHandle == nil) {
        return SetError(error, [NSString stringWithFormat:@"Could not open %@", LauncherLogPath()]);
    }
    [LogHandle truncateFileAtOffset:0];
    return YES;
}

static BOOL SmallFileContainsBytes(NSString *path, NSData *needle) {
    if (needle.length == 0) {
        return NO;
    }

    NSDictionary<NSFileAttributeKey, id> *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    NSNumber *fileSize = attributes[NSFileSize];
    if (fileSize == nil || fileSize.unsignedLongLongValue > MaxWrapperSize) {
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
    return [fm fileExistsAtPath:AppAsarPath()] && SmallFileContainsBytes(AppAsarPath(), needle);
}

static BOOL IsDiscordPatched(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSData *needle = [PatcherPath() dataUsingEncoding:NSUTF8StringEncoding];
    return [fm fileExistsAtPath:AppAsarPath()]
        && [fm fileExistsAtPath:BackupAppAsarPath()]
        && SmallFileContainsBytes(AppAsarPath(), needle);
}

static NSArray<NSString *> *VencordDistAssetNames(void) {
    static NSArray<NSString *> *assets = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        assets = @[
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
    });
    return assets;
}

static BOOL HasCompleteVencordDistAtPath(NSString *distPath) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *requiredFiles = [VencordDistAssetNames() arrayByAddingObject:@"package.json"];
    for (NSString *asset in requiredFiles) {
        NSString *path = [distPath stringByAppendingPathComponent:asset];
        BOOL isDirectory = NO;
        if (![fm fileExistsAtPath:path isDirectory:&isDirectory] || isDirectory) {
            return NO;
        }

        NSNumber *fileSize = [[fm attributesOfItemAtPath:path error:nil] objectForKey:NSFileSize];
        if (fileSize == nil || fileSize.unsignedLongLongValue == 0) {
            return NO;
        }
    }
    return YES;
}

static NSString *VencordUpdateMarkerPath(NSString *distPath) {
    return [distPath stringByAppendingPathComponent:@".last-update-check"];
}

static BOOL WriteVencordUpdateMarker(NSString *distPath, NSError **error) {
    NSString *timestamp = [NSString stringWithFormat:@"%@\n", [NSDate date]];
    return [timestamp writeToFile:VencordUpdateMarkerPath(distPath)
                       atomically:YES
                         encoding:NSUTF8StringEncoding
                            error:error];
}

static BOOL ShouldRefreshVencordDist(void) {
    if (EnvironmentFlagIsEnabled(@"VENCORD_FORCE_UPDATE")) {
        return YES;
    }
    if (!HasCompleteVencordDistAtPath(VencordDistDirPath())) {
        return YES;
    }

    NSDate *lastCheck = [[[NSFileManager defaultManager] attributesOfItemAtPath:VencordUpdateMarkerPath(VencordDistDirPath())
                                                                         error:nil] objectForKey:NSFileModificationDate];
    if (lastCheck == nil) {
        return YES;
    }
    NSTimeInterval age = -lastCheck.timeIntervalSinceNow;
    return age < 0 || age >= VencordUpdateCheckInterval;
}

static NSData *DownloadURLData(NSURL *url, NSDictionary<NSString *, NSString *> *headers, NSError **error) {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 120;
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if (version.length == 0) {
        version = @"development";
    }
    [request setValue:[NSString stringWithFormat:@"DiscordWithVencordPortable/%@", version]
   forHTTPHeaderField:@"User-Agent"];
    for (NSString *header in headers) {
        [request setValue:headers[header] forHTTPHeaderField:header];
    }

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
        SetError(error, [NSString stringWithFormat:@"Timed out downloading %@", url.lastPathComponent]);
        return nil;
    }

    if (downloadError != nil) {
        if (error != NULL) {
            *error = downloadError;
        }
        return nil;
    }

    if (statusCode < 200 || statusCode >= 300) {
        SetError(error, [NSString stringWithFormat:@"HTTP %ld for %@", (long)statusCode, url.lastPathComponent]);
        return nil;
    }

    if (downloadedData == nil) {
        SetError(error, [NSString stringWithFormat:@"No data returned for %@", url.lastPathComponent]);
        return nil;
    }

    return downloadedData;
}

static NSDictionary<NSString *, id> *LatestVencordReleaseMetadata(NSError **error) {
    NSURL *releaseURL = [NSURL URLWithString:@"https://api.github.com/repos/Vendicated/Vencord/releases/latest"];
    NSDictionary *headers = @{
        @"Accept": @"application/vnd.github+json",
        @"X-GitHub-Api-Version": @"2022-11-28"
    };
    NSData *releaseData = DownloadURLData(releaseURL, headers, error);
    if (releaseData == nil) {
        return nil;
    }

    id object = [NSJSONSerialization JSONObjectWithData:releaseData options:0 error:error];
    if (![object isKindOfClass:[NSDictionary class]]) {
        SetError(error, @"GitHub returned invalid Vencord release metadata");
        return nil;
    }

    NSDictionary *release = (NSDictionary *)object;
    NSString *tag = release[@"tag_name"];
    NSArray *assets = release[@"assets"];
    if (![tag isKindOfClass:[NSString class]] || tag.length == 0 || ![assets isKindOfClass:[NSArray class]]) {
        SetError(error, @"Vencord release metadata is missing its tag or assets");
        return nil;
    }

    NSSet<NSString *> *requiredNames = [NSSet setWithArray:VencordDistAssetNames()];
    NSMutableDictionary<NSString *, NSDictionary *> *assetsByName = [NSMutableDictionary dictionary];
    for (id candidate in assets) {
        if (![candidate isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSDictionary *asset = (NSDictionary *)candidate;
        NSString *name = asset[@"name"];
        if (![name isKindOfClass:[NSString class]] || ![requiredNames containsObject:name]) {
            continue;
        }

        NSString *urlString = asset[@"url"];
        NSString *digest = asset[@"digest"];
        NSNumber *size = asset[@"size"];
        BOOL validDigest = [digest isKindOfClass:[NSString class]]
            && [digest hasPrefix:@"sha256:"]
            && digest.length == 71;
        if (![urlString isKindOfClass:[NSString class]]
            || !validDigest
            || ![size isKindOfClass:[NSNumber class]]
            || size.unsignedLongLongValue == 0
            || assetsByName[name] != nil) {
            SetError(error, [NSString stringWithFormat:@"Invalid metadata for Vencord asset %@", name]);
            return nil;
        }
        assetsByName[name] = @{
            @"url": urlString,
            @"digest": digest,
            @"size": size
        };
    }

    if (assetsByName.count != requiredNames.count) {
        NSMutableSet<NSString *> *missing = [requiredNames mutableCopy];
        [missing minusSet:[NSSet setWithArray:assetsByName.allKeys]];
        SetError(error, [NSString stringWithFormat:@"Vencord release %@ is missing required assets: %@",
                                                   tag,
                                                   [[missing.allObjects sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@", "]]);
        return nil;
    }

    return @{
        @"tag": tag,
        @"assets": assetsByName
    };
}

static NSString *SHA256HexForData(NSData *data) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);

    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
        [hex appendFormat:@"%02x", digest[index]];
    }
    return hex;
}

static BOOL DownloadVencordAsset(NSString *name, NSDictionary *metadata, NSString *destination, NSError **error) {
    NSURL *url = [NSURL URLWithString:metadata[@"url"]];
    NSDictionary *headers = @{
        @"Accept": @"application/octet-stream",
        @"X-GitHub-Api-Version": @"2022-11-28"
    };
    NSData *data = DownloadURLData(url, headers, error);
    if (data == nil) {
        return NO;
    }

    NSNumber *expectedSize = metadata[@"size"];
    if (data.length != expectedSize.unsignedLongLongValue) {
        return SetError(error, [NSString stringWithFormat:@"Size verification failed for %@", name]);
    }

    NSString *expectedDigest = [metadata[@"digest"] substringFromIndex:7];
    NSString *actualDigest = SHA256HexForData(data);
    if (![actualDigest isEqualToString:expectedDigest.lowercaseString]) {
        return SetError(error, [NSString stringWithFormat:@"SHA-256 verification failed for %@", name]);
    }

    return [data writeToFile:destination options:NSDataWritingAtomic error:error];
}

static void CleanupStaleVencordStagingDirectories(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:VencordDataDirPath() error:nil];
    for (NSString *entry in entries) {
        if (![entry hasPrefix:@".dist-download-"]) {
            continue;
        }
        NSString *path = [VencordDataDirPath() stringByAppendingPathComponent:entry];
        NSDate *modified = [[fm attributesOfItemAtPath:path error:nil] objectForKey:NSFileModificationDate];
        if (modified != nil && -modified.timeIntervalSinceNow >= 24 * 60 * 60) {
            if ([fm removeItemAtPath:path error:nil]) {
                LogMessage(@"info", @"Removed stale Vencord staging directory %@", entry);
            }
        }
    }
}

static BOOL ActivateVencordDist(NSString *stagedPath, NSError **error) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *activePath = VencordDistDirPath();

    if (![fm fileExistsAtPath:activePath]) {
        NSError *moveError = nil;
        if ([fm moveItemAtPath:stagedPath toPath:activePath error:&moveError]) {
            return YES;
        }
        if (![fm fileExistsAtPath:activePath]) {
            if (error != NULL) {
                *error = moveError;
            }
            return NO;
        }
    }

    if (renamex_np(stagedPath.fileSystemRepresentation,
                   activePath.fileSystemRepresentation,
                   RENAME_SWAP) != 0) {
        NSError *swapError = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        return SetError(error, [NSString stringWithFormat:@"Could not atomically activate Vencord files: %@",
                                                          swapError.localizedDescription]);
    }

    NSError *cleanupError = nil;
    if (![fm removeItemAtPath:stagedPath error:&cleanupError]) {
        LogMessage(@"warning", @"Updated Vencord but could not remove the previous dist: %@", cleanupError.localizedDescription);
    }
    return YES;
}

static BOOL FallBackToCachedVencordDist(NSString *stagedPath, NSError *updateError, NSError **error) {
    [[NSFileManager defaultManager] removeItemAtPath:stagedPath error:nil];
    if (HasCompleteVencordDistAtPath(VencordDistDirPath())) {
        WriteVencordUpdateMarker(VencordDistDirPath(), NULL);
        LogMessage(@"info", @"Could not update Vencord files; using complete cached dist: %@", updateError.localizedDescription);
        return YES;
    }
    return SetError(error, [NSString stringWithFormat:@"Could not download Vencord files and no complete cache exists: %@",
                                                      updateError.localizedDescription]);
}

static BOOL DownloadVencordDist(NSError **error) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (!ShouldRefreshVencordDist()) {
        LogMessage(@"info", @"Using recently checked Vencord files");
        return YES;
    }

    CleanupStaleVencordStagingDirectories();
    NSString *tmpDir = [VencordDataDirPath() stringByAppendingPathComponent:
        [NSString stringWithFormat:@".dist-download-%@", NSUUID.UUID.UUIDString]];
    if (![fm createDirectoryAtPath:tmpDir withIntermediateDirectories:YES attributes:nil error:error]) {
        return NO;
    }

    NSError *updateError = nil;
    NSDictionary *release = LatestVencordReleaseMetadata(&updateError);
    if (release == nil) {
        return FallBackToCachedVencordDist(tmpDir, updateError, error);
    }

    LogMessage(@"info", @"Downloading and verifying Vencord release %@", release[@"tag"]);
    NSDictionary<NSString *, NSDictionary *> *assets = release[@"assets"];
    for (NSString *asset in VencordDistAssetNames()) {
        NSString *destination = [tmpDir stringByAppendingPathComponent:asset];
        if (!DownloadVencordAsset(asset, assets[asset], destination, &updateError)) {
            return FallBackToCachedVencordDist(tmpDir, updateError, error);
        }
    }

    NSString *packageJSON = @"{}\n";
    NSString *packagePath = [tmpDir stringByAppendingPathComponent:@"package.json"];
    if (![packageJSON writeToFile:packagePath atomically:YES encoding:NSUTF8StringEncoding error:&updateError]) {
        return FallBackToCachedVencordDist(tmpDir, updateError, error);
    }

    if (!HasCompleteVencordDistAtPath(tmpDir)) {
        updateError = MakeError(@"Downloaded Vencord files were incomplete");
        return FallBackToCachedVencordDist(tmpDir, updateError, error);
    }
    if (!WriteVencordUpdateMarker(tmpDir, &updateError)) {
        return FallBackToCachedVencordDist(tmpDir, updateError, error);
    }

    if (!ActivateVencordDist(tmpDir, &updateError)) {
        return FallBackToCachedVencordDist(tmpDir, updateError, error);
    }
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
    if (ShouldRunHeadless()) {
        return;
    }

    NSMutableArray<NSRunningApplication *> *runningDiscordApps = [NSMutableArray array];
    NSURL *discordURL = [NSURL fileURLWithPath:DiscordAppPath()].standardizedURL;
    BOOL hasPathOverride = [NSProcessInfo processInfo].environment[@"DISCORD_APP_PATH"].length > 0;

    for (NSRunningApplication *app in [NSWorkspace sharedWorkspace].runningApplications) {
        if ([app.bundleURL.standardizedURL.path isEqualToString:discordURL.path]) {
            [runningDiscordApps addObject:app];
            continue;
        }
        if (!hasPathOverride && ([app.bundleIdentifier isEqualToString:@"com.hnc.Discord"] || [app.localizedName isEqualToString:@"Discord"])) {
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
        (void)app;
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
    if (ShouldRunHeadless()) {
        fprintf(stderr, "Vencord install failed: %s\n", details.UTF8String);
        return;
    }

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

int main(void) {
    @autoreleasepool {
        if (!ShouldRunHeadless()) {
            [NSApplication sharedApplication];
        }

        NSError *error = nil;
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm createDirectoryAtPath:VencordDataDirPath() withIntermediateDirectories:YES attributes:nil error:&error]) {
            ShowFailureAlert(error.localizedDescription);
            return 1;
        }

        if (!AcquireLauncherLock(&error)) {
            ShowFailureAlert(error.localizedDescription);
            return 1;
        }

        if (!OpenLog(&error)) {
            ReleaseLauncherLock();
            ShowFailureAlert(error.localizedDescription);
            return 1;
        }

        BOOL launchSucceeded = RunLauncher(&error);
        if (!launchSucceeded) {
            LogMessage(@"error", @"%@", error.localizedDescription);
            ReleaseLauncherLock();
            ShowFailureAlert(error.localizedDescription);
            return 1;
        }

        ReleaseLauncherLock();
        [LogHandle closeFile];
        return 0;
    }
}
