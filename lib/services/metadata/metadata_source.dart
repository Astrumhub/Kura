import 'package:kazumi/modules/media/media_credit.dart';
import 'package:kazumi/modules/media/media_item.dart';

/// 影视元数据源的统一接口。
///
/// 现在只有 TMDB 一个实现。之所以先抽出接口，是为了以后想换数据源
/// （例如改用 Bangumi 三次元条目）时只写一个新的实现，UI 与播放流程不用动。
abstract class MetadataSource {
  /// 数据源是否已配置（例如 API Key 是否注入）。
  bool get isConfigured;

  /// 数据源名称，用于「关于」页与错误提示。
  String get displayName;

  Future<MediaPage> search(String keyword, MediaKind kind, {int page = 1});

  /// 首页推荐（热门）。
  Future<MediaPage> popular(MediaKind kind, {int page = 1});

  /// 高分榜。
  Future<MediaPage> topRated(MediaKind kind, {int page = 1});

  Future<MediaItem?> detail(String id, MediaKind kind);

  /// 演职员（演员 + 制作人员）。
  Future<({List<MediaCredit> cast, List<MediaCredit> crew})> credits(
    String id,
    MediaKind kind,
  );

  /// 关联作品。
  Future<List<MediaItem>> recommendations(String id, MediaKind kind);

  /// 关键词标签。
  Future<List<String>> keywords(String id, MediaKind kind);

  /// 剧集的季列表；电影返回空列表。
  Future<List<MediaSeason>> seasons(String id);

  /// 某一季的集列表。
  Future<List<MediaEpisode>> episodes(String id, int seasonNumber);
}