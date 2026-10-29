import 'package:dio/dio.dart';
import 'package:kazumi/modules/media/media_credit.dart';
import 'package:kazumi/modules/media/media_item.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/utils/tmdb_credentials.dart';

/// TMDB 原始接口封装：只负责发请求与把 JSON 转成项目内模型。
///
/// 语言固定 zh-CN（TMDB 支持中文标题与简介，缺翻译时回退原名）。
/// 支持 v3 API Key 与 v4 Read Access Token 两种凭证形式。
class TmdbApi {
  TmdbApi._();

  static const String _base = 'https://api.themoviedb.org/3';
  static const String _imageBase = 'https://image.tmdb.org/t/p';
  static const String _lang = 'zh-CN';

  static bool get configured => hasTmdbCredentials;

  // 简单的内存缓存：详情/演职员/关联/关键词十分钟内不重复请求。
  static final Map<String, ({Map<String, dynamic>? data, DateTime at})> _cache =
      <String, ({Map<String, dynamic>? data, DateTime at})>{};
  static const Duration _cacheTtl = Duration(minutes: 10);

  static Dio get _dio => DioFactory.tmdbDio;

  static Map<String, dynamic> _query(Map<String, dynamic> extra) => <String, dynamic>{
        'language': _lang,
        if (!tmdbKeyIsBearer) 'api_key': tmdbApiKey,
        ...extra,
      };

  static Options get _options => Options(
        headers: <String, dynamic>{
          if (tmdbKeyIsBearer) 'authorization': 'Bearer $tmdbApiKey',
        },
      );

  /// 拼出完整图片地址。size 可用 w92 / w185 / w342 / w500 / w780 / original。
  static String imageUrl(String? path, {String size = 'w500'}) {
    if (path == null || path.isEmpty) {
      return '';
    }
    return '$_imageBase/$size$path';
  }

  static Future<Map<String, dynamic>?> _get(
    String path, [
    Map<String, dynamic> query = const {},
  ]) async {
    if (!configured) {
      return null;
    }
    final cacheKey = path + query.toString();
    final cached = _cache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.at) < _cacheTtl) {
      return cached.data;
    }
    try {
      final response = await _dio.get(
        '$_base$path',
        queryParameters: _query(query),
        options: _options,
      );
      final data = response.data;
      final result = data is Map<String, dynamic> ? data : null;
      _cache[cacheKey] = (data: result, at: DateTime.now());
      return result;
    } catch (e) {
      KazumiLogger().w('TMDB: 请求失败 $path', error: e);
      return null;
    }
  }

  // ── 列表 ────────────────────────────────────────────────────────────────

  /// 搜索。TMDB 的相关性一般：调用方要允许用户从结果里挑，不要默认取第一条。
  static Future<MediaPage> search(
    String keyword,
    MediaKind kind, {
    int page = 1,
  }) async {
    final data = await _get(
      '/search/${_pathOf(kind)}',
      {'query': keyword, 'page': '$page', 'include_adult': 'false'},
    );
    return _toPage(data, kind);
  }

  /// 热门（电影用 popular，剧集用 trending/week，后者更接近「最近在播」）。
  static Future<MediaPage> popular(MediaKind kind, {int page = 1}) async {
    final path = kind == MediaKind.movie ? '/movie/popular' : '/trending/tv/week';
    final data = await _get(path, {'page': '$page'});
    return _toPage(data, kind);
  }

  /// 高分。
  static Future<MediaPage> topRated(MediaKind kind, {int page = 1}) async {
    final data = await _get('/${_pathOf(kind)}/top_rated', {'page': '$page'});
    return _toPage(data, kind);
  }

  /// 正在上映（仅电影；剧集返回空页）。
  static Future<MediaPage> nowPlaying({int page = 1}) async {
    final data = await _get('/movie/now_playing', {'page': '$page'});
    return _toPage(data, MediaKind.movie);
  }

  // ── 详情 ────────────────────────────────────────────────────────────────

  static Future<MediaItem?> detail(String id, MediaKind kind) async {
    final data = await _get('/${_pathOf(kind)}/$id');
    if (data == null) {
      return null;
    }
    return _parseItem(data, kind);
  }

  /// 剧集的季列表（含特别篇，seasonNumber 可能为 0）。
  static Future<List<MediaSeason>> seasons(String id) async {
    final data = await _get('/tv/$id');
    if (data == null) {
      return const [];
    }
    final raw = data['seasons'];
    if (raw is! List) {
      return const [];
    }
    return raw.whereType<Map<String, dynamic>>().map((json) {
      return MediaSeason(
        seasonNumber: _asInt(json['season_number']) ?? 0,
        name: _localized(json['name'], json['name']) ?? '第 ${json['season_number']} 季',
        episodeCount: _asInt(json['episode_count']) ?? 0,
        posterUrl: imageUrl(json['poster_path'] as String?),
        airDate: json['air_date'] as String?,
      );
    }).toList();
  }

  /// 某一季的集列表。
  static Future<List<MediaEpisode>> episodes(String id, int seasonNumber) async {
    final data = await _get('/tv/$id/season/$seasonNumber');
    if (data == null) {
      return const [];
    }
    final raw = data['episodes'];
    if (raw is! List) {
      return const [];
    }
    return raw.whereType<Map<String, dynamic>>().map((json) {
      return MediaEpisode(
        seasonNumber: _asInt(json['season_number']) ?? seasonNumber,
        episodeNumber: _asInt(json['episode_number']) ?? 0,
        title: _localized(json['name'], json['name']) ?? '',
        overview: _localized(json['overview'], '') ?? '',
        airDate: json['air_date'] as String?,
        stillUrl: imageUrl(json['still_path'] as String?, size: 'w300'),
        runtimeMinutes: _asInt(json['runtime']),
      );
    }).toList();
  }


  // ── 演职员 / 关联 / 标签 ────────────────────────────────────────────────

  /// 演职员：演员（cast）+ 制作人员（crew）。
  static Future<({List<MediaCredit> cast, List<MediaCredit> crew})> credits(
    String id,
    MediaKind kind,
  ) async {
    final data = await _get('/${_pathOf(kind)}/$id/credits');
    final cast = <MediaCredit>[];
    final crew = <MediaCredit>[];
    if (data == null) {
      return (cast: cast, crew: crew);
    }
    final rawCast = data['cast'];
    if (rawCast is List) {
      for (final json in rawCast.whereType<Map<String, dynamic>>()) {
        final name = (json['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        cast.add(MediaCredit(
          name: name,
          role: '演员',
          character: (json['character'] ?? '').toString(),
          profileUrl: imageUrl(json['profile_path'] as String?, size: 'w185'),
          order: _asInt(json['order']) ?? 0,
        ));
      }
      cast.sort((a, b) => a.order.compareTo(b.order));
    }
    final rawCrew = data['crew'];
    if (rawCrew is List) {
      for (final json in rawCrew.whereType<Map<String, dynamic>>()) {
        final name = (json['name'] ?? '').toString().trim();
        final job = (json['job'] ?? '').toString().trim();
        if (name.isEmpty || job.isEmpty) continue;
        crew.add(MediaCredit(
          name: name,
          role: job,
          profileUrl: imageUrl(json['profile_path'] as String?, size: 'w185'),
        ));
      }
    }
    return (cast: cast, crew: crew);
  }

  /// 关联作品（TMDB 推荐列表）。
  static Future<List<MediaItem>> recommendations(
    String id,
    MediaKind kind,
  ) async {
    final data = await _get('/${_pathOf(kind)}/$id/recommendations');
    if (data == null) {
      return const [];
    }
    final raw = data['results'];
    if (raw is! List) {
      return const [];
    }
    return raw
        .whereType<Map<String, dynamic>>()
        .map((json) => _parseItem(json, kind))
        .where((item) => item.title.isNotEmpty)
        .toList();
  }

  /// 关键词标签。
  static Future<List<String>> keywords(String id, MediaKind kind) async {
    final data = await _get('/${_pathOf(kind)}/$id/keywords');
    if (data == null) {
      return const [];
    }
    final raw = kind == MediaKind.movie ? data['keywords'] : data['results'];
    if (raw is! List) {
      return const [];
    }
    return raw
        .whereType<Map<String, dynamic>>()
        .map((json) => (json['name'] ?? '').toString())
        .where((name) => name.isNotEmpty)
        .toList();
  }

  // ── 解析 ────────────────────────────────────────────────────────────────

  static String _pathOf(MediaKind kind) =>
      kind == MediaKind.movie ? 'movie' : 'tv';

  static MediaPage _toPage(Map<String, dynamic>? data, MediaKind kind) {
    if (data == null) {
      return MediaPage(items: const []);
    }
    final raw = data['results'];
    final items = <MediaItem>[];
    if (raw is List) {
      for (final json in raw.whereType<Map<String, dynamic>>()) {
        final item = _parseItem(json, kind);
        if (item.title.isNotEmpty) {
          items.add(item);
        }
      }
    }
    return MediaPage(
      items: items,
      page: _asInt(data['page']) ?? 1,
      totalPages: _asInt(data['total_pages']) ?? 1,
      totalResults: _asInt(data['total_results']) ?? items.length,
    );
  }

  static MediaItem _parseItem(Map<String, dynamic> json, MediaKind kind) {
    final title = _localized(json['title'], json['name']) ??
        _localized(json['original_title'], json['original_name']) ??
        '';
    final original =
        (json['original_title'] ?? json['original_name'] ?? '').toString();
    final date = (json['release_date'] ?? json['first_air_date'] ?? '').toString();
    final genres = <String>[];
    final rawGenres = json['genres'];
    if (rawGenres is List) {
      for (final g in rawGenres.whereType<Map<String, dynamic>>()) {
        final name = (g['name'] ?? '').toString();
        if (name.isNotEmpty) {
          genres.add(name);
        }
      }
    }
    final vote = json['vote_average'];
    return MediaItem(
      id: (json['id'] ?? '').toString(),
      kind: kind,
      title: title,
      originalTitle: original,
      posterUrl: imageUrl(json['poster_path'] as String?),
      backdropUrl: imageUrl(json['backdrop_path'] as String?, size: 'w780'),
      year: date.length >= 4 ? int.tryParse(date.substring(0, 4)) : null,
      rating: vote is num ? vote.toDouble() : null,
      ratingCount: _asInt(json['vote_count']),
      overview: _localized(json['overview'], '') ?? '',
      genres: genres,
      runtimeMinutes: _asInt(json['runtime']),
      seasonCount: _asInt(json['number_of_seasons']),
      episodeCount: _asInt(json['number_of_episodes']),
    );
  }

  /// TMDB 的 localized 字段：优先中文，空则回退原值。
  static String? _localized(dynamic primary, dynamic fallback) {
    final first = (primary ?? '').toString().trim();
    if (first.isNotEmpty) {
      return first;
    }
    final second = (fallback ?? '').toString().trim();
    return second.isEmpty ? null : second;
  }

  static int? _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }
}