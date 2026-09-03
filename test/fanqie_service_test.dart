import 'package:flutter_test/flutter_test.dart';

import 'package:novel_reader/services/fanqie/fanqie_service.dart';

void main() {
  group('FanqieService.parseBookId', () {
    test('空串/空白返回 null', () {
      expect(FanqieService.parseBookId(''), isNull);
      expect(FanqieService.parseBookId('   '), isNull);
    });

    test('无数字返回 null', () {
      expect(FanqieService.parseBookId('这是一本小说'), isNull);
    });

    test('纯书籍链接可解析', () {
      const url = 'https://fanqienovel.com/page/7663339509576125464';
      expect(FanqieService.parseBookId(url), '7663339509576125464');
    });

    test('阅读页链接(带 query)也可解析', () {
      const url = 'fanqienovel.com/reader/7663339731282821656?from=rank';
      expect(FanqieService.parseBookId(url), '7663339731282821656');
    });

    test('纯数字 ID(≥10 位)可解析并去空白', () {
      expect(FanqieService.parseBookId('  7663339509576125464  '),
          '7663339509576125464');
    });

    test('混在文字中的长数字也能提取', () {
      expect(
        FanqieService.parseBookId('看这本 7663339509576125464 很好看'),
        '7663339509576125464',
      );
    });

    test('短数字(<10 位)拒绝,避免误收', () {
      expect(FanqieService.parseBookId('123456789'), isNull);
      expect(FanqieService.parseBookId('1234567890'), '1234567890');
    });
  });

  group('FanqieService.parseChapters(基于实测目录结构)', () {
    Map<String, dynamic> sampleData() => {
          'allItemIds': <Object>[],
          'volumeNameList': ['第一卷：默认', '第二卷：暗涌'],
          'chapterListWithVolume': [
            [
              {
                'itemId': '7663339731282821656',
                'needPay': 0,
                'title': '第1章 装哑十年',
                'isChapterLock': false,
                'isPaidPublication': false,
                'isPaidStory': false,
                'volume_name': '第一卷：默认',
                'realChapterOrder': 1,
              },
              {
                'itemId': '7663339731282821657',
                'needPay': 1,
                'title': '第2章 付费试读',
                'isChapterLock': false,
                'isPaidStory': true,
                'isPaidPublication': false,
                'volume_name': '第一卷：默认',
                'realChapterOrder': 2,
              },
            ],
            [
              {
                'itemId': '7663339731282821658',
                'needPay': 0,
                'title': '第3章 免费章',
                'isChapterLock': false,
                'isPaidPublication': false,
                'isPaidStory': false,
                'volume_name': '第二卷：暗涌',
                'realChapterOrder': 3,
              },
            ],
          ],
        };

    test('按卷拼接,order 连续递增 1-based', () {
      final items = FanqieService.parseChapters(sampleData());
      expect(items, hasLength(3));
      expect(items.map((e) => e.order), [1, 2, 3]);
    });

    test('标题/卷名/itemId 正确透传', () {
      final items = FanqieService.parseChapters(sampleData());
      expect(items[0].title, '第1章 装哑十年');
      expect(items[0].itemId, '7663339731282821656');
      expect(items[2].volumeName, '第二卷：暗涌');
    });

    test('付费/VIP 章被标记 locked', () {
      final items = FanqieService.parseChapters(sampleData());
      expect(items[0].locked, isFalse);
      expect(items[1].locked, isTrue); // isPaidStory=true
      expect(items[2].locked, isFalse);
    });

    test('needPay>0 视为锁定', () {
      final data = sampleData();
      (data['chapterListWithVolume'] as List)[0]
          .add({'itemId': 'x', 'needPay': 3, 'title': '第4章', 'volume_name': 'v'});
      final items = FanqieService.parseChapters(data);
      expect(items, hasLength(4));
      expect(items[2].locked, isTrue); // 追加章(第一卷内,order=3)
    });

    test('字段缺失时容错(标题兜底、不抛异常)', () {
      final data = sampleData();
      (data['chapterListWithVolume'] as List)[0]
          .add({'itemId': 'y'});
      final items = FanqieService.parseChapters(data);
      expect(items, hasLength(4));
      expect(items[2].title, '第3章'); // 兜底命名
      expect(items[2].locked, isFalse);
    });

    test('非列表/空目录返回空列表', () {
      expect(FanqieService.parseChapters({'chapterListWithVolume': null}), isEmpty);
      expect(FanqieService.parseChapters({'chapterListWithVolume': 'bad'}), isEmpty);
      expect(FanqieService.parseChapters(const {}), isEmpty);
    });
  });

  group('FanqieService.extractObjectWithKey / readJsonObject', () {
    test('从 SSR HTML 中定位 page 对象(含 bookName)', () {
      const snippet = '<script id="__NEXT_DATA__">'
          '{"props":{"pageProps":{}},'
          '"page":{"hasFetch":true,"bookName":"万傀之主","authorName":"画三分",'
          '"thumbUri":"https://p6-novel-sign.byteimg.com/x.jpg","wordNumber":238101,'
          '"originalAuthors":[{"AuthorId":1,"AuthorName":"画三分"}]}}'
          '</script>';
      final obj = FanqieService.extractObjectWithKey(snippet, 'page',
          has: 'bookName');
      expect(obj, isNotNull);
      expect(obj!['bookName'], '万傀之主');
      expect(obj['authorName'], '画三分');
    });

    test('首个同键对象不含目标字段时继续找下一个', () {
      const src = '{"page":{"a":1},"x":{"page":{"bookName":"第二本","author":"乙"}}}';
      final obj = FanqieService.extractObjectWithKey(src, 'page',
          has: 'bookName');
      expect(obj, isNotNull);
      expect(obj!['bookName'], '第二本');
    });

    test('找不到目标键返回 null', () {
      expect(FanqieService.extractObjectWithKey('{"other":1}', 'page'), isNull);
    });

    test('readJsonObject:字符串内的花括号不参与配对', () {
      const src = '{"a":"}","b":{"c":1}}';
      final obj = FanqieService.readJsonObject(src, 0);
      expect(obj, isA<Map<String, dynamic>>());
      final map = obj as Map<String, dynamic>;
      expect(map['a'], '}');
      expect((map['b'] as Map)['c'], 1);
    });

    test('readJsonObject:反斜杠转义不破坏字符串扫描', () {
      const src = r'{"k":"a\"b\\c","n":2,"deep":{"x":[1,2]}}';
      final obj = FanqieService.readJsonObject(src, 0);
      expect(obj, isA<Map<String, dynamic>>());
      final map = obj as Map<String, dynamic>;
      expect(map['k'], r'a"b\c');
      expect(((map['deep'] as Map)['x'] as List), [1, 2]);
    });

    test('readJsonObject:非法 JSON 返回 null 而非抛异常', () {
      expect(FanqieService.readJsonObject('{"a": }', 0), isNull);
    });
  });

  group('FanqieBookMeta.lockedCount', () {
    test('只统计目录中 locked 章节数', () {
      const meta = FanqieBookMeta(
        bookId: '7663339509576125464',
        title: '测试书',
        author: '作者',
        coverUrl: null,
        wordCount: 100,
        chapters: [
          FanqieChapterItem(
              itemId: 'a',
              title: '1',
              volumeName: 'v',
              order: 1,
              locked: false),
          FanqieChapterItem(
              itemId: 'b',
              title: '2',
              volumeName: 'v',
              order: 2,
              locked: true),
        ],
      );
      expect(meta.lockedCount, 1);
    });
  });
}
