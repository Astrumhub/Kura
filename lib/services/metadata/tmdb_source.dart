import 'package:kazumi/modules/media/media_credit.dart';
import 'package:kazumi/modules/media/media_item.dart';
import 'package:kazumi/request/apis/tmdb_api.dart';
import 'package:kazumi/services/metadata/metadata_source.dart';

/// TMDB 实现。API Key 缺失时 isConfigured 为 false，调用方据此显示提示。
class TmdbSource implements MetadataSource {
  const TmdbSource();

  @override
  bool get isConfigured => TmdbApi.configured;

  @override
  String get displayName => 'TMDB';

  @override
  Future<MediaPage> search(String keyword, MediaKind kind, {int page = 1}) =>
      TmdbApi.search(keyword, kind, page: page);

  @override
  Future<MediaPage> popular(MediaKind kind, {int page = 1}) =>
      TmdbApi.popular(kind, page: page);

  @override
  Future<MediaPage> topRated(MediaKind kind, {int page = 1}) =>
      TmdbApi.topRated(kind, page: page);

  @override
  Future<MediaItem?> detail(String id, MediaKind kind) =>
      TmdbApi.detail(id, kind);

  @override
  Future<({List<MediaCredit> cast, List<MediaCredit> crew})> credits(
    String id,
    MediaKind kind,
  ) =>
      TmdbApi.credits(id, kind);

  @override
  Future<List<MediaItem>> recommendations(String id, MediaKind kind) =>
      TmdbApi.recommendations(id, kind);

  @override
  Future<List<String>> keywords(String id, MediaKind kind) =>
      TmdbApi.keywords(id, kind);

  @override
  Future<List<MediaSeason>> seasons(String id) => TmdbApi.seasons(id);

  @override
  Future<List<MediaEpisode>> episodes(String id, int seasonNumber) =>
      TmdbApi.episodes(id, seasonNumber);
}