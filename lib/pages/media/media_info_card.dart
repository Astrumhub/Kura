import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/modules/media/media_item.dart';
import 'package:kazumi/utils/constants.dart';

/// 影视信息卡。
///
/// 布局数值逐项对齐番剧页的 `BangumiInfoCardV`：
/// 卡片高 300、最大宽 950、海报 `AspectRatio(0.65)`、标题 headlineSmall、
/// 文字区 `FittedBox(scaleDown)` 防溢出、间距 16/8。
///
/// 与原卡的三处差异（都是必须的）：
/// 1. 原卡用 `votesCount[i]` 画 10 根评分柱，TMDB 没有分布数据，传空会越界崩溃
///    → 这里不画柱状图，第三列改为标签信息；
/// 2. 原卡内嵌 `CollectButton`，会往番剧收藏写入条目 → 这里换成占位按钮；
/// 3. 「Bangumi Ranked」换成类型/片长，避免显示 #0 这种假数据。
class MediaInfoCardV extends StatelessWidget {
  const MediaInfoCardV({
    super.key,
    required this.item,
    required this.heroTag,
    this.onCollectTap,
  });

  final MediaItem item;
  final Object heroTag;
  final VoidCallback? onCollectTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final showThirdColumn =
        MediaQuery.sizeOf(context).width >= LayoutBreakpoint.compact['width']!;

    return Container(
      height: 300,
      constraints: const BoxConstraints(maxWidth: 950),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: AspectRatio(
                    aspectRatio: 0.65,
                    child: LayoutBuilder(
                      builder: (context, boxConstraints) {
                        final maxWidth = boxConstraints.maxWidth;
                        final maxHeight = boxConstraints.maxHeight;
                        return Hero(
                          transitionOnUserGestures: true,
                          flightShuttleBuilder:
                              NetworkImgLayer.heroFlightShuttleBuilder,
                          tag: heroTag,
                          child: NetworkImgLayer(
                            src: item.posterUrl ?? '',
                            width: maxWidth,
                            height: maxHeight,
                            fadeInDuration: const Duration(milliseconds: 0),
                            fadeOutDuration: const Duration(milliseconds: 0),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Flexible(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.only(bottom: 8),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.topLeft,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('上映日期:'),
                                Text(
                                  item.year == null ? '—' : '${item.year}',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: scheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  item.ratingCount != null &&
                                          item.ratingCount! > 0
                                      ? '${item.ratingCount} 人评分:'
                                      : '评分:',
                                ),
                                if (item.rating != null)
                                  Row(
                                    children: [
                                      Text(
                                        item.rating!.toStringAsFixed(1),
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: scheme.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      RatingBarIndicator(
                                        itemCount: 5,
                                        rating: item.rating! / 2,
                                        itemBuilder: (context, index) => Icon(
                                          Icons.star_rounded,
                                          color: scheme.primary,
                                        ),
                                        itemSize: 20.0,
                                      ),
                                    ],
                                  )
                                else
                                  const Text('暂无评分'),
                                const SizedBox(height: 8),
                                const Text('类型:'),
                                Text(
                                  item.genres.isEmpty
                                      ? '—'
                                      : item.genres.take(2).join(' / '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: scheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        height: 40,
                        child: OutlinedButton(
                          onPressed: onCollectTap,
                          child: const Text('收藏'),
                        ),
                      ),
                    ],
                  ),
                ),
                if (showThirdColumn) ...[
                  const SizedBox(width: 16),
                  Flexible(child: _metaPanel(context)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 第三列：代替原卡的评分分布柱状图。
  Widget _metaPanel(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <String, String>{
      if (item.kind == MediaKind.movie && item.runtimeMinutes != null)
        '片长': '${item.runtimeMinutes} 分钟',
      if (item.kind == MediaKind.tv && item.seasonCount != null)
        '季数': '${item.seasonCount} 季',
      if (item.kind == MediaKind.tv && item.episodeCount != null)
        '集数': '${item.episodeCount} 集',
      if (item.originalTitle.isNotEmpty) '原名': item.originalTitle,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('  影片信息:'),
        const SizedBox(height: 16),
        for (final entry in rows.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.key,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  entry.value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
          ),
      ],
    );
  }
}