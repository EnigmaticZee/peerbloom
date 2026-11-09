#import "TorrentBridge.h"

#include <libtorrent/session.hpp>
#include <libtorrent/session_params.hpp>
#include <libtorrent/session_stats.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/add_torrent_params.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/torrent_handle.hpp>
#include <libtorrent/torrent_status.hpp>
#include <libtorrent/torrent_info.hpp>
#include <libtorrent/alert_types.hpp>
#include <libtorrent/read_resume_data.hpp>
#include <libtorrent/write_resume_data.hpp>
#include <libtorrent/peer_info.hpp>
#include <libtorrent/announce_entry.hpp>
#include <libtorrent/ip_filter.hpp>
#include <libtorrent/fingerprint.hpp>
#include <libtorrent/error_code.hpp>

#include <algorithm>
#include <fstream>
#include <iterator>
#include <map>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <vector>

namespace lt = libtorrent;

static NSString *const SWErrorDomain = @"Peerbloom.TorrentBridge";

static NSString *ToNS(std::string const &s) {
    return [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSUTF8StringEncoding] ?: @"";
}

static std::string ToStd(NSString *s) {
    return s ? std::string(s.UTF8String) : std::string();
}

static NSString *HexOf(lt::torrent_handle const &h) {
    std::ostringstream os;
    os << h.info_hashes().get_best();
    return ToNS(os.str());
}

static void SetError(NSError **error, std::string const &message) {
    if (error) {
        *error = [NSError errorWithDomain:SWErrorDomain code:1
                                 userInfo:@{NSLocalizedDescriptionKey: ToNS(message)}];
    }
}

static bool ReadFile(std::string const &path, std::vector<char> &out) {
    std::ifstream in(path, std::ios::binary);
    if (!in) return false;
    out.assign(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
    return true;
}

static void WriteFile(std::string const &path, std::vector<char> const &data) {
    std::string tmp = path + ".tmp";
    {
        std::ofstream out(tmp, std::ios::binary | std::ios::trunc);
        out.write(data.data(), static_cast<std::streamsize>(data.size()));
    }
    std::rename(tmp.c_str(), path.c_str());
}

static lt::settings_pack MakePack(SWSessionSettings *s) {
    lt::settings_pack p;
    std::string port = std::to_string(s.listenPort);
    std::string iface = ToStd(s.boundInterface);
    if (iface.empty()) {
        p.set_str(lt::settings_pack::listen_interfaces, "0.0.0.0:" + port + ",[::]:" + port);
        p.set_str(lt::settings_pack::outgoing_interfaces, "");
    } else {
        // Listen and connect only through the chosen interface (usually a VPN tunnel).
        p.set_str(lt::settings_pack::listen_interfaces, iface + ":" + port);
        p.set_str(lt::settings_pack::outgoing_interfaces, iface);
    }
    p.set_int(lt::settings_pack::download_rate_limit, s.downloadRateLimit);
    p.set_int(lt::settings_pack::upload_rate_limit, s.uploadRateLimit);

    switch (s.encryption) {
        case SWEncryptionModeRequire:
            p.set_int(lt::settings_pack::out_enc_policy, lt::settings_pack::pe_forced);
            p.set_int(lt::settings_pack::in_enc_policy, lt::settings_pack::pe_forced);
            p.set_int(lt::settings_pack::allowed_enc_level, lt::settings_pack::pe_rc4);
            break;
        case SWEncryptionModePrefer:
            p.set_int(lt::settings_pack::out_enc_policy, lt::settings_pack::pe_enabled);
            p.set_int(lt::settings_pack::in_enc_policy, lt::settings_pack::pe_enabled);
            p.set_int(lt::settings_pack::allowed_enc_level, lt::settings_pack::pe_both);
            p.set_bool(lt::settings_pack::prefer_rc4, true);
            break;
        case SWEncryptionModeAllow:
            p.set_int(lt::settings_pack::out_enc_policy, lt::settings_pack::pe_enabled);
            p.set_int(lt::settings_pack::in_enc_policy, lt::settings_pack::pe_enabled);
            p.set_int(lt::settings_pack::allowed_enc_level, lt::settings_pack::pe_both);
            p.set_bool(lt::settings_pack::prefer_rc4, false);
            break;
    }

    p.set_bool(lt::settings_pack::anonymous_mode, s.anonymousMode);
    p.set_bool(lt::settings_pack::enable_dht, s.enableDHT);
    p.set_bool(lt::settings_pack::enable_lsd, s.enableLSD);
    p.set_bool(lt::settings_pack::enable_upnp, s.enablePortMapping);
    p.set_bool(lt::settings_pack::enable_natpmp, s.enablePortMapping);
    p.set_int(lt::settings_pack::active_downloads, s.activeDownloads);
    p.set_int(lt::settings_pack::active_seeds, s.activeSeeds);
    p.set_int(lt::settings_pack::active_limit, std::max(s.activeDownloads + s.activeSeeds, 1) * 2);

    // Proxy. With a login, libtorrent needs the "_pw" variant of the type.
    bool login = s.proxyUsername.length > 0;
    switch (s.proxyType) {
        case SWProxyTypeNone:
            p.set_int(lt::settings_pack::proxy_type, lt::settings_pack::none);
            break;
        case SWProxyTypeSOCKS5:
            p.set_int(lt::settings_pack::proxy_type, login ? lt::settings_pack::socks5_pw : lt::settings_pack::socks5);
            break;
        case SWProxyTypeHTTP:
            p.set_int(lt::settings_pack::proxy_type, login ? lt::settings_pack::http_pw : lt::settings_pack::http);
            break;
    }
    p.set_str(lt::settings_pack::proxy_hostname, ToStd(s.proxyHost));
    p.set_int(lt::settings_pack::proxy_port, s.proxyPort);
    p.set_str(lt::settings_pack::proxy_username, ToStd(s.proxyUsername));
    p.set_str(lt::settings_pack::proxy_password, ToStd(s.proxyPassword));
    p.set_bool(lt::settings_pack::proxy_peer_connections, s.proxyPeerConnections);
    p.set_bool(lt::settings_pack::proxy_tracker_connections, s.proxyTrackerConnections);
    // Look up tracker names through the proxy too, so DNS doesn't reveal them.
    p.set_bool(lt::settings_pack::proxy_hostnames, s.proxyType != SWProxyTypeNone);

    std::string version = ToStd(s.clientVersion);
    p.set_str(lt::settings_pack::user_agent, "Peerbloom/" + version);
    p.set_str(lt::settings_pack::peer_fingerprint, lt::generate_fingerprint("PE", 1, 0, 0, 0));

    p.set_int(lt::settings_pack::alert_mask,
              lt::alert_category::status | lt::alert_category::error |
              lt::alert_category::storage | lt::alert_category::port_mapping);
    return p;
}

// MARK: - Value objects

@implementation SWSessionSettings
- (instancetype)init {
    if ((self = [super init])) {
        _listenPort = 51413;
        _encryption = SWEncryptionModePrefer;
        _enableDHT = YES;
        _enableLSD = YES;
        _enablePortMapping = YES;
        _proxyHost = @"";
        _proxyUsername = @"";
        _proxyPassword = @"";
        _proxyPort = 1080;
        _proxyPeerConnections = YES;
        _proxyTrackerConnections = YES;
        _activeDownloads = 3;
        _activeSeeds = 5;
        _clientVersion = @"1.0";
    }
    return self;
}
@end

@implementation SWTorrentStatus
@end
@implementation SWFileEntry
@end
@implementation SWPeerEntry
@end
@implementation SWTrackerEntry
@end
@implementation SWTorrentDetail
@end
@implementation SWTorrentFileInfo
@end
@implementation SWSessionStats
@end
@implementation SWEvent
@end

@implementation SWIPRange
- (instancetype)initWithFirst:(NSString *)first last:(NSString *)last {
    if ((self = [super init])) {
        _first = [first copy];
        _last = [last copy];
    }
    return self;
}
@end

// MARK: - Session

@implementation SWSession {
    std::unique_ptr<lt::session> _session;
    std::string _stateDir;
    std::string _resumeDir;
    std::mutex _handlesMutex;
    std::map<std::string, lt::torrent_handle> _handles;
    std::mutex _alertMutex;
    std::vector<SWEvent *> _pendingEvents;
    int _dhtNodes;
    int _listenPort;
    BOOL _listening;
    BOOL _portMapped;
    int64_t _totalDownload;
    int64_t _totalUpload;
    int _dhtNodesIdx;
    int _recvIdx;
    int _sentIdx;
}

- (instancetype)initWithSettings:(SWSessionSettings *)settings stateDirectory:(NSString *)directory {
    if ((self = [super init])) {
        _stateDir = ToStd(directory);
        _resumeDir = _stateDir + "/resume";
        [[NSFileManager defaultManager] createDirectoryAtPath:ToNS(_resumeDir)
                                  withIntermediateDirectories:YES attributes:nil error:nil];
        _dhtNodesIdx = lt::find_metric_idx("dht.dht_nodes");
        _recvIdx = lt::find_metric_idx("net.recv_payload_bytes");
        _sentIdx = lt::find_metric_idx("net.sent_payload_bytes");

        lt::session_params params;
        std::vector<char> stateBuf;
        if (ReadFile(_stateDir + "/session.state", stateBuf) && !stateBuf.empty()) {
            try {
                params = lt::read_session_params(stateBuf, lt::session::save_dht_state);
            } catch (...) {
                params = lt::session_params();
            }
        }
        params.settings = MakePack(settings);
        _session = std::make_unique<lt::session>(std::move(params));
        [self loadResumeFiles];
    }
    return self;
}

- (void)loadResumeFiles {
    NSArray<NSString *> *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:ToNS(_resumeDir) error:nil];
    for (NSString *name in names) {
        if (![name hasSuffix:@".fastresume"]) continue;
        std::string path = _resumeDir + "/" + ToStd(name);
        std::vector<char> buf;
        if (!ReadFile(path, buf)) continue;
        lt::error_code ec;
        lt::add_torrent_params atp = lt::read_resume_data(buf, ec);
        if (ec) continue;
        lt::torrent_handle h = _session->add_torrent(std::move(atp), ec);
        if (!ec) {
            std::lock_guard<std::mutex> lock(_handlesMutex);
            _handles[ToStd(HexOf(h))] = h;
        }
    }
}

- (void)applySettings:(SWSessionSettings *)settings {
    _session->apply_settings(MakePack(settings));
}

- (lt::torrent_handle)handleFor:(NSString *)infoHash {
    std::lock_guard<std::mutex> lock(_handlesMutex);
    auto it = _handles.find(ToStd(infoHash));
    return it == _handles.end() ? lt::torrent_handle() : it->second;
}

- (nullable NSString *)addParams:(lt::add_torrent_params)p
                          paused:(BOOL)paused
                      sequential:(BOOL)sequential
                           error:(NSError **)error {
    if (paused) {
        p.flags |= lt::torrent_flags::paused;
        p.flags &= ~lt::torrent_flags::auto_managed;
    } else {
        p.flags &= ~lt::torrent_flags::paused;
        p.flags |= lt::torrent_flags::auto_managed;
    }
    if (sequential) p.flags |= lt::torrent_flags::sequential_download;

    lt::error_code ec;
    lt::torrent_handle h = _session->add_torrent(std::move(p), ec);
    if (ec) {
        SetError(error, ec == lt::errors::duplicate_torrent ? "This torrent is already in your list." : ec.message());
        return nil;
    }
    NSString *hash = HexOf(h);
    {
        std::lock_guard<std::mutex> lock(_handlesMutex);
        _handles[ToStd(hash)] = h;
    }
    h.save_resume_data(lt::torrent_handle::save_info_dict);
    return hash;
}

- (nullable NSString *)addMagnet:(NSString *)uri savePath:(NSString *)savePath paused:(BOOL)paused
                      sequential:(BOOL)sequential error:(NSError **)error {
    lt::error_code ec;
    lt::add_torrent_params p = lt::parse_magnet_uri(ToStd(uri), ec);
    if (ec) {
        SetError(error, "That magnet link is not valid: " + ec.message());
        return nil;
    }
    p.save_path = ToStd(savePath);
    return [self addParams:std::move(p) paused:paused sequential:sequential error:error];
}

- (nullable NSString *)addTorrentFile:(NSString *)path savePath:(NSString *)savePath paused:(BOOL)paused
                           sequential:(BOOL)sequential filePriorities:(NSArray<NSNumber *> *)priorities
                                error:(NSError **)error {
    lt::error_code ec;
    auto ti = std::make_shared<lt::torrent_info>(ToStd(path), ec);
    if (ec) {
        SetError(error, "Could not read the torrent file: " + ec.message());
        return nil;
    }
    lt::add_torrent_params p;
    p.ti = ti;
    p.save_path = ToStd(savePath);
    if (priorities.count > 0) {
        for (NSNumber *n in priorities) {
            p.file_priorities.push_back(lt::download_priority_t(static_cast<std::uint8_t>(n.intValue)));
        }
    }
    return [self addParams:std::move(p) paused:paused sequential:sequential error:error];
}

+ (nullable SWTorrentFileInfo *)inspectTorrentFile:(NSString *)path error:(NSError **)error {
    lt::error_code ec;
    lt::torrent_info ti(ToStd(path), ec);
    if (ec) {
        SetError(error, "Could not read the torrent file: " + ec.message());
        return nil;
    }
    SWTorrentFileInfo *info = [SWTorrentFileInfo new];
    info.name = ToNS(ti.name());
    std::ostringstream os;
    os << ti.info_hashes().get_best();
    info.infoHash = ToNS(os.str());
    info.totalSize = ti.total_size();
    NSMutableArray *files = [NSMutableArray array];
    lt::file_storage const &fs = ti.files();
    for (lt::file_index_t i : fs.file_range()) {
        if (fs.pad_file_at(i)) continue;
        SWFileEntry *f = [SWFileEntry new];
        f.index = static_cast<int>(i);
        f.path = ToNS(fs.file_path(i));
        f.size = fs.file_size(i);
        f.priority = 4;
        [files addObject:f];
    }
    info.files = files;
    return info;
}

static SWTorrentState MapState(lt::torrent_status::state_t s) {
    switch (s) {
        case lt::torrent_status::checking_files: return SWTorrentStateCheckingFiles;
        case lt::torrent_status::downloading_metadata: return SWTorrentStateDownloadingMetadata;
        case lt::torrent_status::downloading: return SWTorrentStateDownloading;
        case lt::torrent_status::finished: return SWTorrentStateFinished;
        case lt::torrent_status::seeding: return SWTorrentStateSeeding;
        case lt::torrent_status::checking_resume_data: return SWTorrentStateCheckingResumeData;
        default: return SWTorrentStateUnknown;
    }
}

- (NSArray<SWTorrentStatus *> *)allStatuses {
    std::vector<lt::torrent_handle> handles = _session->get_torrents();
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:handles.size()];
    std::map<std::string, lt::torrent_handle> fresh;
    for (lt::torrent_handle const &h : handles) {
        if (!h.is_valid()) continue;
        lt::torrent_status st = h.status();
        SWTorrentStatus *s = [SWTorrentStatus new];
        s.infoHash = HexOf(h);
        fresh[ToStd(s.infoHash)] = h;
        s.name = st.name.empty() ? s.infoHash : ToNS(st.name);
        s.savePath = ToNS(st.save_path);
        s.state = MapState(st.state);
        s.paused = static_cast<bool>(st.flags & lt::torrent_flags::paused);
        s.autoManaged = static_cast<bool>(st.flags & lt::torrent_flags::auto_managed);
        s.sequential = static_cast<bool>(st.flags & lt::torrent_flags::sequential_download);
        s.hasMetadata = st.has_metadata;
        s.progress = st.progress;
        s.totalWanted = st.total_wanted;
        s.totalWantedDone = st.total_wanted_done;
        s.allTimeUpload = st.all_time_upload;
        s.allTimeDownload = st.all_time_download;
        s.downloadRate = st.download_payload_rate;
        s.uploadRate = st.upload_payload_rate;
        s.numPeers = st.num_peers;
        s.numSeeds = st.num_seeds;
        s.listPeers = st.list_peers;
        s.listSeeds = st.list_seeds;
        s.availability = st.distributed_copies;
        s.queuePosition = static_cast<int>(st.queue_position);
        s.addedDate = [NSDate dateWithTimeIntervalSince1970:st.added_time];
        s.completedDate = st.completed_time > 0 ? [NSDate dateWithTimeIntervalSince1970:st.completed_time] : nil;
        s.errorMessage = st.errc ? ToNS(st.errc.message()) : nil;
        [result addObject:s];
    }
    std::lock_guard<std::mutex> lock(_handlesMutex);
    _handles.swap(fresh);
    return result;
}

- (nullable SWTorrentDetail *)detailForHash:(NSString *)infoHash bucketCount:(int)bucketCount {
    lt::torrent_handle h = [self handleFor:infoHash];
    if (!h.is_valid()) return nil;
    SWTorrentDetail *d = [SWTorrentDetail new];
    lt::torrent_status st = h.status(lt::torrent_handle::query_pieces);
    std::shared_ptr<const lt::torrent_info> ti = h.torrent_file();

    NSMutableArray *files = [NSMutableArray array];
    if (ti) {
        lt::file_storage const &fs = ti->files();
        std::vector<std::int64_t> progress;
        h.file_progress(progress, lt::torrent_handle::piece_granularity);
        std::vector<lt::download_priority_t> prios = h.get_file_priorities();
        for (lt::file_index_t i : fs.file_range()) {
            if (fs.pad_file_at(i)) continue;
            int idx = static_cast<int>(i);
            SWFileEntry *f = [SWFileEntry new];
            f.index = idx;
            f.path = ToNS(fs.file_path(i));
            f.size = fs.file_size(i);
            f.downloaded = idx < (int)progress.size() ? progress[idx] : 0;
            f.priority = idx < (int)prios.size() ? static_cast<int>(static_cast<std::uint8_t>(prios[idx])) : 4;
            [files addObject:f];
        }
        d.pieceCount = ti->num_pieces();
        d.pieceSize = ti->piece_length();
        d.comment = ti->comment().empty() ? nil : ToNS(ti->comment());
        d.creator = ti->creator().empty() ? nil : ToNS(ti->creator());
    }
    d.files = files;

    NSMutableArray *buckets = [NSMutableArray array];
    int pieces = st.pieces.size();
    if (pieces > 0 && bucketCount > 0) {
        for (int b = 0; b < bucketCount; ++b) {
            int start = (int)((int64_t)b * pieces / bucketCount);
            int end = std::max(start + 1, (int)((int64_t)(b + 1) * pieces / bucketCount));
            end = std::min(end, pieces);
            int have = 0;
            for (int i = start; i < end; ++i) {
                if (st.pieces.get_bit(lt::piece_index_t(i))) ++have;
            }
            [buckets addObject:@(end > start ? (double)have / (end - start) : 0.0)];
        }
    }
    d.pieceBuckets = buckets;

    NSMutableArray *peers = [NSMutableArray array];
    std::vector<lt::peer_info> pv;
    h.get_peer_info(pv);
    for (lt::peer_info const &p : pv) {
        SWPeerEntry *e = [SWPeerEntry new];
        e.address = ToNS(p.ip.address().to_string());
        e.client = ToNS(p.client);
        e.downloadRate = p.down_speed;
        e.uploadRate = p.up_speed;
        e.progress = p.progress;
        e.encrypted = static_cast<bool>(p.flags & (lt::peer_info::rc4_encrypted | lt::peer_info::plaintext_encrypted));
        e.seed = static_cast<bool>(p.flags & lt::peer_info::seed);
        [peers addObject:e];
    }
    [peers sortUsingComparator:^NSComparisonResult(SWPeerEntry *a, SWPeerEntry *b) {
        int sa = a.downloadRate + a.uploadRate, sb = b.downloadRate + b.uploadRate;
        return sa > sb ? NSOrderedAscending : (sa < sb ? NSOrderedDescending : NSOrderedSame);
    }];
    d.peers = peers;

    NSMutableArray *trackers = [NSMutableArray array];
    for (lt::announce_entry const &ae : h.trackers()) {
        SWTrackerEntry *t = [SWTrackerEntry new];
        t.url = ToNS(ae.url);
        t.tier = ae.tier;
        t.seeds = -1;
        t.peers = -1;
        t.message = @"";
        for (lt::announce_endpoint const &ep : ae.endpoints) {
            lt::announce_infohash const &ih = ep.info_hashes[lt::protocol_version::V1];
            if (ih.start_sent && ih.fails == 0) t.working = YES;
            if (ih.updating) t.updating = YES;
            t.seeds = std::max(t.seeds, ih.scrape_complete);
            t.peers = std::max(t.peers, ih.scrape_incomplete);
            if (!ih.message.empty()) t.message = ToNS(ih.message);
            else if (ih.last_error) t.message = ToNS(ih.last_error.message());
        }
        [trackers addObject:t];
    }
    d.trackers = trackers;
    return d;
}

- (SWSessionStats *)sessionStats {
    _session->post_session_stats();
    SWSessionStats *s = [SWSessionStats new];
    std::lock_guard<std::mutex> lock(_alertMutex);
    s.dhtNodes = _dhtNodes;
    s.listenPort = _listenPort;
    s.listening = _listening;
    s.portMapped = _portMapped;
    s.totalDownload = _totalDownload;
    s.totalUpload = _totalUpload;
    return s;
}

- (void)writeResumeData:(lt::save_resume_data_alert const *)rd {
    std::vector<char> buf = lt::write_resume_data_buf(rd->params);
    WriteFile(_resumeDir + "/" + ToStd(HexOf(rd->handle)) + ".fastresume", buf);
}

/// Handles one alert. Must be called with _alertMutex held. Returns YES for resume-data alerts.
- (BOOL)handleAlert:(lt::alert *)a {
    if (auto *rd = lt::alert_cast<lt::save_resume_data_alert>(a)) {
        [self writeResumeData:rd];
        return YES;
    }
    if (lt::alert_cast<lt::save_resume_data_failed_alert>(a)) {
        return YES;
    }
    SWEvent *e = nil;
    if (auto *fa = lt::alert_cast<lt::torrent_finished_alert>(a)) {
        e = [SWEvent new];
        e.kind = SWEventKindFinished;
        e.infoHash = HexOf(fa->handle);
        e.name = ToNS(fa->torrent_name());
        e.message = @"Download complete";
        fa->handle.save_resume_data(lt::torrent_handle::save_info_dict);
    } else if (auto *ma = lt::alert_cast<lt::metadata_received_alert>(a)) {
        e = [SWEvent new];
        e.kind = SWEventKindMetadataReceived;
        e.infoHash = HexOf(ma->handle);
        e.name = ToNS(ma->torrent_name());
        e.message = @"Metadata received";
        ma->handle.save_resume_data(lt::torrent_handle::save_info_dict);
    } else if (auto *ea = lt::alert_cast<lt::torrent_error_alert>(a)) {
        e = [SWEvent new];
        e.kind = SWEventKindTorrentError;
        e.infoHash = HexOf(ea->handle);
        e.name = ToNS(ea->torrent_name());
        e.message = ToNS(ea->error.message());
    } else if (auto *ls = lt::alert_cast<lt::listen_succeeded_alert>(a)) {
        _listening = YES;
        _listenPort = ls->port;
        e = [SWEvent new];
        e.kind = SWEventKindListenSucceeded;
        e.message = ToNS(ls->message());
    } else if (auto *lf = lt::alert_cast<lt::listen_failed_alert>(a)) {
        _listening = NO;
        e = [SWEvent new];
        e.kind = SWEventKindListenFailed;
        e.message = ToNS(lf->message());
    } else if (lt::alert_cast<lt::portmap_alert>(a)) {
        _portMapped = YES;
        e = [SWEvent new];
        e.kind = SWEventKindPortMapped;
        e.message = ToNS(a->message());
    } else if (lt::alert_cast<lt::portmap_error_alert>(a)) {
        e = [SWEvent new];
        e.kind = SWEventKindPortMapFailed;
        e.message = ToNS(a->message());
    } else if (auto *xa = lt::alert_cast<lt::external_ip_alert>(a)) {
        e = [SWEvent new];
        e.kind = SWEventKindExternalAddress;
        e.message = ToNS(xa->external_address.to_string());
    } else if (auto *ss = lt::alert_cast<lt::session_stats_alert>(a)) {
        lt::span<std::int64_t const> c = ss->counters();
        if (_dhtNodesIdx >= 0) _dhtNodes = static_cast<int>(c[_dhtNodesIdx]);
        if (_recvIdx >= 0) _totalDownload = c[_recvIdx];
        if (_sentIdx >= 0) _totalUpload = c[_sentIdx];
    }
    if (e) _pendingEvents.push_back(e);
    return NO;
}

- (NSArray<SWEvent *> *)popEvents {
    std::lock_guard<std::mutex> lock(_alertMutex);
    std::vector<lt::alert *> alerts;
    _session->pop_alerts(&alerts);
    for (lt::alert *a : alerts) [self handleAlert:a];
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:_pendingEvents.size()];
    for (SWEvent *e : _pendingEvents) [out addObject:e];
    _pendingEvents.clear();
    return out;
}

- (void)pause:(NSString *)infoHash {
    lt::torrent_handle h = [self handleFor:infoHash];
    if (!h.is_valid()) return;
    h.unset_flags(lt::torrent_flags::auto_managed);
    h.pause();
}

- (void)resume:(NSString *)infoHash {
    lt::torrent_handle h = [self handleFor:infoHash];
    if (!h.is_valid()) return;
    h.set_flags(lt::torrent_flags::auto_managed);
    h.resume();
}

- (void)pauseAll {
    for (lt::torrent_handle const &h : _session->get_torrents()) {
        h.unset_flags(lt::torrent_flags::auto_managed);
        h.pause();
    }
}

- (void)resumeAll {
    for (lt::torrent_handle const &h : _session->get_torrents()) {
        h.set_flags(lt::torrent_flags::auto_managed);
        h.resume();
    }
}

- (void)remove:(NSString *)infoHash deleteFiles:(BOOL)deleteFiles {
    lt::torrent_handle h = [self handleFor:infoHash];
    if (!h.is_valid()) return;
    _session->remove_torrent(h, deleteFiles ? lt::session::delete_files : lt::remove_flags_t{});
    {
        std::lock_guard<std::mutex> lock(_handlesMutex);
        _handles.erase(ToStd(infoHash));
    }
    std::remove((_resumeDir + "/" + ToStd(infoHash) + ".fastresume").c_str());
}

- (void)setSequential:(BOOL)sequential forHash:(NSString *)infoHash {
    lt::torrent_handle h = [self handleFor:infoHash];
    if (!h.is_valid()) return;
    if (sequential) h.set_flags(lt::torrent_flags::sequential_download);
    else h.unset_flags(lt::torrent_flags::sequential_download);
}

- (void)setFilePriority:(int)priority fileIndex:(int)index forHash:(NSString *)infoHash {
    lt::torrent_handle h = [self handleFor:infoHash];
    if (!h.is_valid()) return;
    h.file_priority(lt::file_index_t(index), lt::download_priority_t(static_cast<std::uint8_t>(priority)));
}

- (void)queueUp:(NSString *)infoHash { lt::torrent_handle h = [self handleFor:infoHash]; if (h.is_valid()) h.queue_position_up(); }
- (void)queueDown:(NSString *)infoHash { lt::torrent_handle h = [self handleFor:infoHash]; if (h.is_valid()) h.queue_position_down(); }
- (void)queueTop:(NSString *)infoHash { lt::torrent_handle h = [self handleFor:infoHash]; if (h.is_valid()) h.queue_position_top(); }
- (void)queueBottom:(NSString *)infoHash { lt::torrent_handle h = [self handleFor:infoHash]; if (h.is_valid()) h.queue_position_bottom(); }

- (void)moveStorage:(NSString *)infoHash to:(NSString *)path {
    lt::torrent_handle h = [self handleFor:infoHash];
    if (h.is_valid()) h.move_storage(ToStd(path));
}

- (void)forceRecheck:(NSString *)infoHash {
    lt::torrent_handle h = [self handleFor:infoHash];
    if (h.is_valid()) h.force_recheck();
}

- (void)forceReannounce:(NSString *)infoHash {
    lt::torrent_handle h = [self handleFor:infoHash];
    if (h.is_valid()) h.force_reannounce();
}

- (nullable NSString *)magnetLinkForHash:(NSString *)infoHash {
    lt::torrent_handle h = [self handleFor:infoHash];
    if (!h.is_valid()) return nil;
    std::string uri = lt::make_magnet_uri(h);
    return uri.empty() ? nil : ToNS(uri);
}

- (void)setBlockedRanges:(NSArray<SWIPRange *> *)ranges {
    lt::ip_filter filter;
    for (SWIPRange *r in ranges) {
        lt::error_code ec1, ec2;
        lt::address first = lt::make_address(ToStd(r.first), ec1);
        lt::address last = lt::make_address(ToStd(r.last), ec2);
        if (ec1 || ec2 || first.is_v4() != last.is_v4()) continue;
        filter.add_rule(first, last, lt::ip_filter::blocked);
    }
    _session->set_ip_filter(filter);
}

- (void)saveStateWithTimeout:(NSTimeInterval)timeout {
    std::lock_guard<std::mutex> lock(_alertMutex);
    int outstanding = 0;
    for (lt::torrent_handle const &h : _session->get_torrents()) {
        if (!h.is_valid()) continue;
        h.save_resume_data(lt::torrent_handle::save_info_dict);
        ++outstanding;
    }
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (outstanding > 0 && [deadline timeIntervalSinceNow] > 0) {
        if (!_session->wait_for_alert(lt::milliseconds(200))) continue;
        std::vector<lt::alert *> alerts;
        _session->pop_alerts(&alerts);
        for (lt::alert *a : alerts) {
            if ([self handleAlert:a]) --outstanding;
        }
    }
    std::vector<char> state = lt::write_session_params_buf(_session->session_state(lt::session::save_dht_state),
                                                           lt::session::save_dht_state);
    WriteFile(_stateDir + "/session.state", state);
}

@end
