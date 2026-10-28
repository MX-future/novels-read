// App 通道（官方协议）的会话层：身份持久化 + seed 刷新 + 串行控速 + 限流退避。
//
// 上层（FanqieService）只关心"给我这一章的正文"，其余细节都在这里：
//   • 设备身份首次运行现场注册，之后存 SharedPreferences 复用（8 位数字 ID 很稳定）；
//   • seed 约 30 分钟过期，客户端内部按 25 分钟主动刷新；
//   • batch_full 是滑动窗口软限流：HTTP 200 但 body 0 字节。这里串行 + 1.1s
//     间隔（Python 侧实测安全值），命中限流则 20s/40s/80s/160s 退避重试。
import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'official_client.dart';

class FanqieOfficialSession {
  FanqieOfficialSession._();

  static final FanqieOfficialSession instance = FanqieOfficialSession._();

  static const String _prefKey = 'fanqie_official_identity';

  /// 两次正文请求的最小间隔。串行 1.1s/章是实测安全值，再快会触发限流。
  static const Duration minInterval = Duration(milliseconds: 1100);

  /// 命中限流后的首个退避时长（之后每次翻倍，共 4 轮）。
  static const Duration initialBackoff = Duration(seconds: 20);

  FanqieOfficialClient? _client;
  Future<FanqieOfficialClient>? _pending;
  DateTime _lastRequest = DateTime.fromMillisecondsSinceEpoch(0);

  /// 请求串行队列：所有正文请求排队执行，避免并发冲垮窗口。
  Future<void> _queue = Future<void>.value();

  /// 当前设备身份（未初始化时为 null）。
  FanqieDeviceProfile? get profile => _client?.profile;

  /// 已注册身份 + 已取 seed 的客户端；失败抛 [FanqieOfficialException]。
  Future<FanqieOfficialClient> ensureReady() {
    final c = _client;
    if (c != null) return Future.value(c);
    final pending = _pending;
    if (pending != null) return pending;
    final f = _create();
    _pending = f;
    return f.whenComplete(() => _pending = null);
  }

  Future<FanqieOfficialClient> _create() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      // 纯 Dart 环境(如 tool/ 脚本)没有插件通道:退化为内存身份
      prefs = null;
    }
    FanqieDeviceProfile profile = FanqieDeviceProfile.empty;

    final raw = prefs?.getString(_prefKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          profile = FanqieDeviceProfile.fromJson(decoded.cast<String, dynamic>());
        }
      } catch (_) {
        // 存档损坏则重新注册
      }
    }
    if (profile.isEmpty) {
      profile = await FanqieDeviceProfile.provision();
      await prefs?.setString(_prefKey, jsonEncode(profile.toJson()));
    }

    final client = FanqieOfficialClient(profile: profile);
    await client.register();
    _client = client;
    return client;
  }

  /// 取单章纯文本。返回 null 表示该章确实没有正文（非限流）。
  ///
  /// 抛异常表示通道级失败（签名/身份/网络），由上层决定是否回落到 web 通道。
  Future<String?> chapterText({
    required String bookId,
    required String itemId,
  }) {
    final result = _queue.then((_) => _fetch(bookId, itemId));
    // 队列本身吞掉错误，避免一次失败卡死后续请求
    _queue = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  Future<String?> _fetch(String bookId, String itemId) async {
    var backoff = initialBackoff;
    for (var attempt = 0; attempt < 4; attempt++) {
      await _throttle();
      try {
        final client = await ensureReady();
        final ch = await client.chapter(bookId, itemId);
        if (ch.ok) return ch.text;
        return null;
      } on FanqieOfficialException catch (e) {
        final throttled = e.message.contains('限流');
        // seed 失效（key 过期 / verify fail）时重建一次会话
        if (!throttled && attempt == 0) {
          resetClient();
          continue;
        }
        if (!throttled) rethrow;
      }
      await Future<void>.delayed(backoff);
      backoff *= 2;
    }
    throw const FanqieOfficialException('通道持续限流，请稍后再试');
  }

  Future<void> _throttle() async {
    final elapsed = DateTime.now().difference(_lastRequest);
    if (elapsed < minInterval) {
      await Future<void>.delayed(minInterval - elapsed);
    }
    _lastRequest = DateTime.now();
  }

  /// 丢弃当前客户端（换身份或 seed 异常时用），下次请求会重新注册+取 seed。
  void resetClient() {
    _client?.close();
    _client = null;
  }

  /// 清空本机身份，下次使用会注册一台"新设备"。
  Future<void> forgetIdentity() async {
    resetClient();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKey);
    } catch (_) {
      // 无插件通道时无需清理
    }
  }
}
