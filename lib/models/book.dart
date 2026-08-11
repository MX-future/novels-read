class Chapter {
  final String title;
  final String content;

  const Chapter({required this.title, required this.content});

  Map<String, dynamic> toJson() => {'title': title, 'content': content};

  factory Chapter.fromJson(Map<String, dynamic> json) => Chapter(
        title: json['title'] as String? ?? '',
        content: json['content'] as String? ?? '',
      );
}

class Book {
  final String id;
  final String title;
  final String author;
  final String? coverPath;
  final String sourcePath;
  final List<Chapter> chapters;

  const Book({
    required this.id,
    required this.title,
    required this.author,
    required this.coverPath,
    required this.sourcePath,
    required this.chapters,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'coverPath': coverPath,
        'sourcePath': sourcePath,
        'chapters': chapters.map((c) => c.toJson()).toList(),
      };

  factory Book.fromJson(Map<String, dynamic> json) => Book(
        id: json['id'] as String,
        title: json['title'] as String? ?? '未知书名',
        author: json['author'] as String? ?? '未知作者',
        coverPath: json['coverPath'] as String?,
        sourcePath: json['sourcePath'] as String? ?? '',
        chapters: (json['chapters'] as List<dynamic>? ?? const [])
            .map((c) => Chapter.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}

class BookMeta {
  final String id;
  final String title;
  final String author;
  final String? coverPath;
  final int chapterCount;
  final String sourcePath;

  const BookMeta({
    required this.id,
    required this.title,
    required this.author,
    required this.coverPath,
    required this.chapterCount,
    required this.sourcePath,
  });

  factory BookMeta.fromBook(Book book) => BookMeta(
        id: book.id,
        title: book.title,
        author: book.author,
        coverPath: book.coverPath,
        chapterCount: book.chapters.length,
        sourcePath: book.sourcePath,
      );
}

class ReadingProgress {
  final int chapterIndex;
  final int pageIndex;

  const ReadingProgress({required this.chapterIndex, required this.pageIndex});

  Map<String, dynamic> toJson() => {
        'chapter': chapterIndex,
        'page': pageIndex,
      };

  factory ReadingProgress.fromJson(Map<String, dynamic> json) => ReadingProgress(
        chapterIndex: json['chapter'] as int? ?? 0,
        pageIndex: json['page'] as int? ?? 0,
      );

  static const empty = ReadingProgress(chapterIndex: 0, pageIndex: 0);
}
