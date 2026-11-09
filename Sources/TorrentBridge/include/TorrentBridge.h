#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SWTorrentState) {
    SWTorrentStateCheckingFiles,
    SWTorrentStateDownloadingMetadata,
    SWTorrentStateDownloading,
    SWTorrentStateFinished,
    SWTorrentStateSeeding,
    SWTorrentStateCheckingResumeData,
    SWTorrentStateUnknown
};

typedef NS_ENUM(NSInteger, SWEncryptionMode) {
    SWEncryptionModeRequire,
    SWEncryptionModePrefer,
    SWEncryptionModeAllow
};

typedef NS_ENUM(NSInteger, SWEventKind) {
    SWEventKindFinished,
    SWEventKindMetadataReceived,
    SWEventKindTorrentError,
    SWEventKindListenSucceeded,
    SWEventKindListenFailed,
    SWEventKindPortMapped,
    SWEventKindPortMapFailed,
    /// Peers or trackers told us our public address. `message` holds it.
    SWEventKindExternalAddress
};

typedef NS_ENUM(NSInteger, SWProxyType) {
    SWProxyTypeNone,
    SWProxyTypeSOCKS5,
    SWProxyTypeHTTP
};

/// Settings applied to the libtorrent session. Rates are bytes per second; 0 means unlimited.
@interface SWSessionSettings : NSObject
@property (nonatomic) int listenPort;
/// Network interface name to bind to, e.g. "utun4". Nil means any interface.
@property (nonatomic, copy, nullable) NSString *boundInterface;
@property (nonatomic) int downloadRateLimit;
@property (nonatomic) int uploadRateLimit;
@property (nonatomic) SWEncryptionMode encryption;
@property (nonatomic) BOOL anonymousMode;
@property (nonatomic) BOOL enableDHT;
@property (nonatomic) BOOL enableLSD;
@property (nonatomic) BOOL enablePortMapping;
@property (nonatomic) int activeDownloads;
@property (nonatomic) int activeSeeds;
@property (nonatomic, copy) NSString *clientVersion;
@property (nonatomic) SWProxyType proxyType;
@property (nonatomic, copy) NSString *proxyHost;
@property (nonatomic) int proxyPort;
/// Empty for a proxy without a login.
@property (nonatomic, copy) NSString *proxyUsername;
@property (nonatomic, copy) NSString *proxyPassword;
@property (nonatomic) BOOL proxyPeerConnections;
@property (nonatomic) BOOL proxyTrackerConnections;
@end

@interface SWTorrentStatus : NSObject
@property (nonatomic, copy) NSString *infoHash;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *savePath;
@property (nonatomic) SWTorrentState state;
@property (nonatomic) BOOL paused;
@property (nonatomic) BOOL autoManaged;
@property (nonatomic) BOOL sequential;
@property (nonatomic) BOOL hasMetadata;
@property (nonatomic) double progress;
@property (nonatomic) int64_t totalWanted;
@property (nonatomic) int64_t totalWantedDone;
@property (nonatomic) int64_t allTimeUpload;
@property (nonatomic) int64_t allTimeDownload;
@property (nonatomic) int downloadRate;
@property (nonatomic) int uploadRate;
@property (nonatomic) int numPeers;
@property (nonatomic) int numSeeds;
@property (nonatomic) int listPeers;
@property (nonatomic) int listSeeds;
@property (nonatomic) double availability;
@property (nonatomic) int queuePosition;
@property (nonatomic, strong) NSDate *addedDate;
@property (nonatomic, strong, nullable) NSDate *completedDate;
@property (nonatomic, copy, nullable) NSString *errorMessage;
@end

@interface SWFileEntry : NSObject
@property (nonatomic) int index;
@property (nonatomic, copy) NSString *path;
@property (nonatomic) int64_t size;
@property (nonatomic) int64_t downloaded;
/// 0 = skip, 1 = low, 4 = normal, 7 = high.
@property (nonatomic) int priority;
@end

@interface SWPeerEntry : NSObject
@property (nonatomic, copy) NSString *address;
@property (nonatomic, copy) NSString *client;
@property (nonatomic) int downloadRate;
@property (nonatomic) int uploadRate;
@property (nonatomic) double progress;
@property (nonatomic) BOOL encrypted;
@property (nonatomic) BOOL seed;
@end

@interface SWTrackerEntry : NSObject
@property (nonatomic, copy) NSString *url;
@property (nonatomic) int tier;
@property (nonatomic) BOOL working;
@property (nonatomic) BOOL updating;
@property (nonatomic) int seeds;
@property (nonatomic) int peers;
@property (nonatomic, copy) NSString *message;
@end

@interface SWTorrentDetail : NSObject
@property (nonatomic, copy) NSArray<SWFileEntry *> *files;
@property (nonatomic, copy) NSArray<SWPeerEntry *> *peers;
@property (nonatomic, copy) NSArray<SWTrackerEntry *> *trackers;
/// Downloaded fraction of each bucket of pieces, 0...1. Empty without metadata.
@property (nonatomic, copy) NSArray<NSNumber *> *pieceBuckets;
@property (nonatomic) int pieceCount;
@property (nonatomic) int pieceSize;
@property (nonatomic, copy, nullable) NSString *comment;
@property (nonatomic, copy, nullable) NSString *creator;
@end

@interface SWTorrentFileInfo : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *infoHash;
@property (nonatomic) int64_t totalSize;
@property (nonatomic, copy) NSArray<SWFileEntry *> *files;
@end

@interface SWSessionStats : NSObject
@property (nonatomic) int downloadRate;
@property (nonatomic) int uploadRate;
@property (nonatomic) int64_t totalDownload;
@property (nonatomic) int64_t totalUpload;
@property (nonatomic) int dhtNodes;
@property (nonatomic) int listenPort;
@property (nonatomic) BOOL listening;
@property (nonatomic) BOOL portMapped;
@end

@interface SWEvent : NSObject
@property (nonatomic) SWEventKind kind;
@property (nonatomic, copy, nullable) NSString *infoHash;
@property (nonatomic, copy, nullable) NSString *name;
@property (nonatomic, copy) NSString *message;
@end

@interface SWIPRange : NSObject
@property (nonatomic, copy) NSString *first;
@property (nonatomic, copy) NSString *last;
- (instancetype)initWithFirst:(NSString *)first last:(NSString *)last;
@end

/// Owns one libtorrent session. Methods are thread safe; call them from any thread.
@interface SWSession : NSObject

- (instancetype)initWithSettings:(SWSessionSettings *)settings stateDirectory:(NSString *)directory;
- (instancetype)init NS_UNAVAILABLE;

- (void)applySettings:(SWSessionSettings *)settings;

/// Returns the info hash of the added torrent.
- (nullable NSString *)addMagnet:(NSString *)uri
                        savePath:(NSString *)savePath
                          paused:(BOOL)paused
                      sequential:(BOOL)sequential
                           error:(NSError **)error;

- (nullable NSString *)addTorrentFile:(NSString *)path
                             savePath:(NSString *)savePath
                               paused:(BOOL)paused
                           sequential:(BOOL)sequential
                       filePriorities:(nullable NSArray<NSNumber *> *)priorities
                                error:(NSError **)error;

+ (nullable SWTorrentFileInfo *)inspectTorrentFile:(NSString *)path error:(NSError **)error;

- (NSArray<SWTorrentStatus *> *)allStatuses;
- (nullable SWTorrentDetail *)detailForHash:(NSString *)infoHash bucketCount:(int)bucketCount;
- (SWSessionStats *)sessionStats;
- (NSArray<SWEvent *> *)popEvents;

- (void)pause:(NSString *)infoHash;
- (void)resume:(NSString *)infoHash;
- (void)pauseAll;
- (void)resumeAll;
- (void)remove:(NSString *)infoHash deleteFiles:(BOOL)deleteFiles;
- (void)setSequential:(BOOL)sequential forHash:(NSString *)infoHash;
- (void)setFilePriority:(int)priority fileIndex:(int)index forHash:(NSString *)infoHash;
- (void)queueUp:(NSString *)infoHash;
- (void)queueDown:(NSString *)infoHash;
- (void)queueTop:(NSString *)infoHash;
- (void)queueBottom:(NSString *)infoHash;
- (void)moveStorage:(NSString *)infoHash to:(NSString *)path;
- (void)forceRecheck:(NSString *)infoHash;
- (void)forceReannounce:(NSString *)infoHash;
- (nullable NSString *)magnetLinkForHash:(NSString *)infoHash;

- (void)setBlockedRanges:(NSArray<SWIPRange *> *)ranges;

/// Writes resume data for every torrent plus session state (DHT nodes) to the state directory.
/// Blocks for up to `timeout` seconds. Call before quitting.
- (void)saveStateWithTimeout:(NSTimeInterval)timeout;

@end

NS_ASSUME_NONNULL_END
