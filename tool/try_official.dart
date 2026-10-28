// 试跑脚本：验证 Dart 侧「注册 → 详情 → 目录 → 取正文」全链路。
//
//   dart run tool/try_official.dart [bookId] [章节序号(1-based)]
//
// 身份优先级：本地缓存 → 现场注册新设备。
import 'dart:convert';
import 'dart:io';

import 'package:novel_reader/services/fanqie/official/official_client.dart';

const String _cachePath = '/Users/MX/AppData/Local/fanqie/fanqie_iid_cache.json';
const String _localCache = '.dart_tool/fanqie_identity.json';

Future<FanqieDeviceProfile?> _loadCache() async {
  for (final path in [_localCache, _cachePath]) {
    final f = File(path);
    if (!f.existsSync()) continue;
    try {
      final raw = jsonDecode(f.readAsStringSync());
      if (raw is! Map) continue;
      final Map<String, dynamic> json;
      if (raw.containsKey('device_profile')) {
        // Python 侧的缓存格式：identity 在顶层，profile 在子 map
        final prof = (raw['device_profile'] as Map).cast<String, dynamic>();
        json = {
          'device_id': raw['device_id']?.toString() ?? '0',
          'install_id': raw['install_id']?.toString() ?? '0',
          ...prof,
        };
      } else {
        json = raw.cast<String, dynamic>();
      }
      final p = FanqieDeviceProfile.fromJson(json);
      if (p.isEmpty) continue;
      stdout.writeln('# 复用身份（$path）did=${p.deviceId} iid=${p.installId}');
      return p;
    } catch (e) {
      stdout.writeln('# 缓存 $path 读取失败：$e');
    }
  }
  return null;
}

Future<void> _saveCache(FanqieDeviceProfile p) async {
  final f = File(_localCache);
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(p.toJson()));
  stdout.writeln('# 身份已写入 $_localCache');
}

Future<void> main(List<String> args) async {
  final bookId = args.isNotEmpty ? args[0] : '7393543333957618713';
  final index = args.length > 1 ? int.parse(args[1]) : 1;

  final sw = Stopwatch()..start();

  var profile = await _loadCache();
  if (profile == null) {
    stdout.writeln('# 无可用身份，现场注册新设备…');
    profile = await FanqieDeviceProfile.provision();
    await _saveCache(profile);
  }

  final client = FanqieOfficialClient(profile: profile);

  // 1. registerkey
  await client.register();
  stdout.writeln('# registerkey OK  ${sw.elapsedMilliseconds} ms  did=${client.profile.deviceId}');

  // 2. detail
  final detail = await client.detail(bookId);
  stdout.writeln('# 详情：${detail['book_name']} / ${detail['author']} '
      '/ ${detail['word_number']} 字 / 状态 ${detail['creation_status']}');

  // 3. directory
  final items = await client.directory(bookId);
  stdout.writeln('# 目录：${items.length} 章');
  if (items.isEmpty) {
    stderr.writeln('!! 目录为空');
    exit(1);
  }

  // 4. 正文
  final idx = (index - 1).clamp(0, items.length - 1);
  final count = args.length > 2 ? int.parse(args[2]) : 1;
  stdout.writeln('# 目录项字段：${items[idx].keys.join(", ")}');

  // 连续取 count 章（保守节流，等价于会话层的串行 1.1s/章）
  final total = count <= 1 ? 1 : count;
  var okCount = 0;
  var chars = 0;
  for (var i = 0; i < total; i++) {
    final pos = (idx + i).clamp(0, items.length - 1);
    final target = items[pos];
    final itemId = target['item_id'].toString();
    if (i > 0) {
      await Future<void>.delayed(const Duration(milliseconds: 1100));
    }
    final ch = await client.chapter(bookId, itemId);
    if (ch.ok) {
      okCount += 1;
      chars += ch.text.length;
    }
    stdout.writeln('# [${i + 1}/$total] ${target['title']} → ${ch.text.length} 字'
        '${ch.error == null ? '' : ' error=${ch.error}'}');

    if (i == 0) {
      stdout.writeln('--------------------------------------------');
      stdout.writeln(ch.text.isEmpty ? '(空)' : ch.text.split('\n').take(4).join('\n'));
      stdout.writeln('--------------------------------------------');
      final out = File('/tmp/fanqie_chapter_$itemId.txt');
      out.writeAsStringSync(ch.text);
      stdout.writeln('# 已写出 ${out.path}');
    }
  }
  if (total > 1) {
    stdout.writeln('# 合计 $okCount/$total 章成功，$chars 字，'
        '总耗时 ${sw.elapsedMilliseconds} ms');
  }

  // 顺带验证 VIP 章节（取最后一章，通常是 VIP）
  if (items.length > 1 && index == 1 && total == 1) {
    final last = items[items.length - 1];
    final lastId = last['item_id'].toString();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final vip = await client.chapter(bookId, lastId);
    stdout.writeln('# 末章 ($lastId) 字数=${vip.text.length} error=${vip.error ?? '-'}');
    stdout.writeln('# 末章开头：${vip.text.split('\n').take(2).join(' / ')}');
  }

  client.close();
}
