import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/bangumi_tag.dart';
import 'package:kazumi/modules/media/media_item.dart';

/// 把 TMDB 条目适配成 BangumiItem，供播放/历史/收藏等既有链路复用。
///
/// 关键点：id 使用**负数命名空间**（-TMDB id），避免与 Bangumi 的数字 id 冲突，
/// 否则影视条目会污染番剧的收藏与观看历史。
BangumiItem mediaToBangumiItem(MediaItem item) {
  final poster = item.posterUrl ?? '';
  final tmdbId = int.tryParse(item.id) ?? 0;
  return BangumiItem(
    id: -tmdbId,
    type: 6,
    name: item.originalTitle.isNotEmpty ? item.originalTitle : item.title,
    nameCn: item.title,
    summary: item.overview,
    airDate: item.year == null ? '' : '${item.year}-01-01',
    airWeekday: 0,
    rank: 0,
    images: poster.isEmpty ? const {} : {'large': poster, 'common': poster},
    tags: [
      for (final genre in item.genres)
        BangumiTag(name: genre, count: 0, totalCount: 0),
    ],
    alias: const [],
    ratingScore: item.rating ?? 0,
    votes: item.ratingCount ?? 0,
    votesCount: const [],
    info: '',
  );
}