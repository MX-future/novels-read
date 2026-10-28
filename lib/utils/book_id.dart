/// 书籍 id 生成。放在独立文件里,便于 txt 解析等纯逻辑复用而不牵连插件依赖。
String makeBookId(String title, String author) {
  final raw = '$title|$author';
  return 'book_${raw.hashCode.toRadixString(16)}_${DateTime.now().millisecondsSinceEpoch}';
}
