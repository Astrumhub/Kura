/// 影视内容的种类。电影与剧集走两套完全不同的接口和数据形态，所以从模型层就分开。
enum MediaKind {
  movie,
  tv;

  String get label => switch (this) {
        MediaKind.movie => '电影',
        MediaKind.tv => '剧集',
      };
}

/// 一部影视作品（列表与详情共用）。
///
/// 字段来源为 TMDB，但类型本身与数据源无关：将来若换成别的元数据源，
/// 只要产出同样的模型即可，UI 不用改。
class MediaItem {
  const MediaItem({
    required this.id,
    required this.kind,
    required this.title,
    this.originalTitle = '',
    this.posterUrl,
    this.backdropUrl,
    this.year,
    this.rating,
    this.ratingCount,
    this.overview = '',
    this.genres = const [],
    this.runtimeMinutes,
    this.seasonCount,
    this.episodeCount,
  });

  /// 数据源内的唯一标识（TMDB 为数字 id 的字符串形式）。
  final String id;

  final MediaKind kind;

  /// 中文标题（数据源没有中文时回退原名）。
  final String title;

  final String originalTitle;

  /// 完整可用的海报地址（已拼好尺寸前缀）。
  final String? posterUrl;

  /// 完整可用的背景图地址。
  final String? backdropUrl;

  final int? year;

  final double? rating;

  /// 评分人数（TMDB vote_count）。没有分布数据，所以信息卡不画柱状图。
  final int? ratingCount;

  final String overview;

  final List<String> genres;

  /// 电影片长（分钟）。
  final int? runtimeMinutes;

  /// 剧集季数。
  final int? seasonCount;

  /// 剧集总集数。
  final int? episodeCount;

  bool get hasPoster => posterUrl != null && posterUrl!.isNotEmpty;
}

/// 一页列表结果。
class MediaPage {
  const MediaPage({
    required this.items,
    this.page = 1,
    this.totalPages = 1,
    this.totalResults = 0,
  });

  final List<MediaItem> items;
  final int page;
  final int totalPages;
  final int totalResults;

  bool get hasMore => page < totalPages;
}

/// 剧集的一季。
class MediaSeason {
  const MediaSeason({
    required this.seasonNumber,
    required this.name,
    this.episodeCount = 0,
    this.posterUrl,
    this.airDate,
  });

  final int seasonNumber;
  final String name;
  final int episodeCount;
  final String? posterUrl;
  final String? airDate;
}

/// 剧集的一集。
class MediaEpisode {
  const MediaEpisode({
    required this.seasonNumber,
    required this.episodeNumber,
    required this.title,
    this.overview = '',
    this.airDate,
    this.stillUrl,
    this.runtimeMinutes,
  });

  final int seasonNumber;
  final int episodeNumber;
  final String title;
  final String overview;
  final String? airDate;
  final String? stillUrl;
  final int? runtimeMinutes;

  /// 「S01E03」形式，用于匹配播放源与文件命名。
  String get code =>
      'S${seasonNumber.toString().padLeft(2, '0')}E${episodeNumber.toString().padLeft(2, '0')}';
}