import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/modules/media/media_item.dart';
import 'package:kazumi/services/metadata/tmdb_source.dart';

/// 搜索页里的「影视」结果分区。
///
/// 卡片与栅格规格逐项对齐番剧搜索的 `_SearchResultCard` / `_SearchResultGrid`：
/// 圆角 16、封面比例 0.7、标题两行、星级 + 年份、列宽 180 断点、间距 12/20。
class MediaSearchSliver extends StatefulWidget {
  const MediaSearchSliver({super.key, required this.keyword});

  final String keyword;

  @override
  State<MediaSearchSliver> createState() => _MediaSearchSliverState();
}

class _MediaSearchSliverState extends State<MediaSearchSliver> {
  final TmdbSource _source = const TmdbSource();

  List<MediaItem> _movies = const [];
  List<MediaItem> _tvs = const [];
  bool _loading = false;
  String? _error;
  String _loadedKeyword = '';

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void didUpdateWidget(covariant MediaSearchSliver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keyword != widget.keyword) {
      _search();
    }
  }

  Future<void> _search() async {
    final keyword = widget.keyword.trim();
    if (keyword.isEmpty || keyword == _loadedKeyword) {
      return;
    }
    if (!_source.isConfigured) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _loadedKeyword = keyword;
    });
    try {
      final results = await Future.wait([
        _source.search(keyword, MediaKind.movie),
        _source.search(keyword, MediaKind.tv),
      ]);
      if (!mounted || widget.keyword.trim() != keyword) {
        return;
      }
      setState(() {
        _movies = results[0].items;
        _tvs = results[1].items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '影视搜索失败（检查代理与 TMDB Key）';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_source.isConfigured) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final slivers = <Widget>[];
    if (_movies.isNotEmpty) {
      slivers
        ..add(_sectionHeader(context, '电影', _movies.length))
        ..add(_grid(context, _movies));
    }
    if (_tvs.isNotEmpty) {
      slivers
        ..add(_sectionHeader(context, '剧集', _tvs.length))
        ..add(_grid(context, _tvs));
    }
    if (_movies.isEmpty && _tvs.isEmpty && !_loading) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _error ?? '影视暂无结果',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ),
      );
    }
    return SliverMainAxisGroup(slivers: slivers);
  }

  Widget _sectionHeader(BuildContext context, String title, int count) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 10),
        child: Row(
          children: [
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            Text(
              '$count 部',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  /// 栅格规格照抄 `_SearchResultGrid`。
  Widget _grid(BuildContext context, List<MediaItem> items) {
    final textTheme = Theme.of(context).textTheme;
    final titleStyle = textTheme.titleSmall!
        .copyWith(fontWeight: FontWeight.w600, height: 1.4);
    final width = MediaQuery.sizeOf(context).width - 32;

    double textHeight(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
      )..layout();
      final height = painter.height.ceilToDouble();
      painter.dispose();
      return height;
    }

    final titleHeight = textHeight('影视\n影视', titleStyle);
    final metadataHeight = math.max(
      MediaSearchCard.ratingIconSize,
      textHeight('0.0 0000', textTheme.labelMedium!),
    );
    final columns = math.max(2, (width / 180).floor());
    final cardWidth = (width - (columns - 1) * 12) / columns;

    return SliverGrid.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 12,
        mainAxisSpacing: 20,
        mainAxisExtent: cardWidth / MediaSearchCard.coverAspectRatio +
            titleHeight +
            metadataHeight +
            MediaSearchCard.titleSpacing +
            MediaSearchCard.metadataSpacing +
            6,
      ),
      itemCount: items.length,
      itemBuilder: (_, index) => MediaSearchCard(
        item: items[index],
        titleHeight: titleHeight,
        titleStyle: titleStyle,
      ),
    );
  }
}

/// 与 `_SearchResultCard` 同构的影视卡片。
class MediaSearchCard extends StatelessWidget {
  const MediaSearchCard({
    super.key,
    required this.item,
    required this.titleHeight,
    required this.titleStyle,
  });

  static const coverAspectRatio = 0.7;
  static const titleSpacing = 10.0;
  static const metadataSpacing = 4.0;
  static const ratingIconSize = 14.0;

  final MediaItem item;
  final double titleHeight;
  final TextStyle titleStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final year = item.year?.toString() ?? '';
    return Material(
      type: MaterialType.transparency,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => context.pushNamed('/media/detail', arguments: item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: coverAspectRatio,
                child: LayoutBuilder(
                  builder: (_, constraints) => NetworkImgLayer(
                    src: item.posterUrl ?? '',
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                  ),
                ),
              ),
            ),
            const SizedBox(height: titleSpacing),
            SizedBox(
              height: titleHeight,
              child: Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
            ),
            const SizedBox(height: metadataSpacing),
            Row(
              children: [
                if ((item.rating ?? 0) > 0) ...[
                  Icon(
                    Icons.star_rounded,
                    size: ratingIconSize,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    item.rating!.toStringAsFixed(1),
                    style: theme.textTheme.labelMedium,
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    year,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}