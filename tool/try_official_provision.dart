// 验证「自建设备身份」这条路径：全新 cdid → 服务端分配 device_id → seed → 正文。
//
//   dart run tool/try_official_provision.dart [bookId] [itemId]
//
// 不读任何缓存，每次运行都是一台"新设备"，用来确认 Dart 侧的
// device_register 请求体与签名能被服务端接受。
//
// 注意：会话层 official_session.dart 依赖 shared_preferences（进而依赖
// Flutter），纯 `dart run` 编译不过，所以这里直接操作 client。
import 'dart:io';

import 'package:novel_reader/services/fanqie/official/official_client.dart';

Future<void> main(List<String> args) async {
  const bookId = '7393543333957618713';
  const itemId = '7393543509208220185'; // 第 1 章
  final book = args.isNotEmpty ? args[0] : bookId;
  final item = args.length > 1 ? args[1] : itemId;

  final sw = Stopwatch()..start();

  final profile = await FanqieDeviceProfile.provision();
  stdout.writeln('# 新身份：did=${profile.deviceId} '
      'iid=${profile.installId} cdid=${profile.cdid}');

  final client = FanqieOfficialClient(profile: profile);
  try {
    await client.register();
    stdout.writeln('# registerkey OK，耗时 ${sw.elapsedMilliseconds} ms');

    final ch = await client.chapter(book, item);
    stdout.writeln('# 正文 ${ch.text.length} 字，总耗时 ${sw.elapsedMilliseconds} ms'
        ' error=${ch.error ?? '-'}');
    stdout.writeln('--------------------------------------------');
    stdout.writeln(ch.text.split('\n').take(6).join('\n'));
    stdout.writeln('--------------------------------------------');
  } finally {
    client.close();
  }
}
