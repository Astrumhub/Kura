import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/media/media_item.dart';
import 'package:kazumi/pages/media/media_detail_page.dart';
import 'package:kazumi/services/metadata/tmdb_source.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:url_launcher/url_launcher.dart';

enum MediaSort { popular, topRated }

/// 影视列表状态：与番剧的 PopularController 同级，但只服务影视。
class MediaGridController extends ChangeNotifier {
  MediaGridController({required this.kind});

  final MediaKind kind;
  final TmdbSource _source = const TmdbSource();

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// 请求返回时控制器可能已被销毁（切换内容类型），这里统一挡一下。
  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  List<MediaItem> items = const [];
  MediaSort sort = MediaSort.popular;
  String keyword = '';
  int page = 1;
  bool loading = false;
  bool loadingMore = false;
  bool error = false;

  Future<void> reload() async {
    loading = true;
    error = false;
    page = 1;
    _notify();
    final result = await _fetch(1);
    items = result.items;
    loading = false;
    error = result.items.isEmpty;
    _notify();
  }

  Future<void> loadMore() async {
    if (loadingMore || loading) {
      return;
    }
    loadingMore = true;
    _notify();
    final next = page + 1;
    final result = await _fetch(next);
    loadingMore = false;
    if (result.items.isNotEmpty) {
      page = next;
      items = [...items, ...result.items];
    }
    _notify();
  }

  void setSort(MediaSort value) {
    if (sort == value && keyword.isEmpty) {
      return;
    }
    sort = value;
    keyword = '';
    reload();
  }

  void search(String value) {
    final next = value.trim();
    if (next == keyword) {
      return;
    }
    keyword = next;
    reload();
  }

  Future<MediaPage> _fetch(int page) {
    if (keyword.isNotEmpty) {
      return _source.search(keyword, kind, page: page);
    }
    return switch (sort) {
      MediaSort.popular => _source.popular(kind, page: page),
      MediaSort.topRated => _source.topRated(kind, page: page),
    };
  }
}

/// 顶部工具条（搜索 + 热门/高分），作为 sliver。
class MediaGridHeaderSliver extends StatelessWidget {
  const MediaGridHeaderSliver({
    super.key,
    required this.controller,
    required this.searchController,
  });

  final MediaGridController controller;
  final TextEditingController searchController;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SliverToBoxAdapter(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: searchController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: controller.search,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '搜索${controller.kind.label}',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: controller.keyword.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              searchController.clear();
                              controller.search('');
                            },
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: scheme.surfaceContainerHighest,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<MediaSort>(
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                segments: const [
                  ButtonSegment(value: MediaSort.popular, label: Text('热门')),
                  ButtonSegment(value: MediaSort.topRated, label: Text('高分')),
                ],
                selected: {controller.sort},
                onSelectionChanged: controller.keyword.isEmpty
                    ? (selection) => controller.setSort(selection.first)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 列表本体（sliver）。
class MediaGridSliver extends StatelessWidget {
  const MediaGridSliver({super.key, required this.controller});

  final MediaGridController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (controller.error &&
            !controller.loading &&
            controller.items.isEmpty) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('没有取到数据，检查网络或代理设置'),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: controller.reload,
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          );
        }
        if (controller.items.isEmpty) {
          // 加载骨架：纯色占位（不引 skeletonizer，避免额外依赖风险）
          return SliverPadding(
            padding: const EdgeInsets.fromLTRB(StyleString.cardSpace, 0, StyleString.cardSpace, 8),
            sliver: SliverGrid(
              gridDelegate: mediaGridDelegate(context),
              delegate: SliverChildBuilderDelegate(
                (context, index) => const _PosterSkeleton(),
                childCount: 10,
              ),
            ),
          );
        }
        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(StyleString.cardSpace, 0, StyleString.cardSpace, 8),
          sliver: SliverGrid(
            gridDelegate: mediaGridDelegate(context),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index >= controller.items.length) {
                  return const Center(child: CircularProgressIndicator());
                }
                return MediaPosterCard(item: controller.items[index]);
              },
              childCount:
                  controller.items.length + (controller.loadingMore ? 4 : 0),
            ),
          ),
        );
      },
    );
  }
}

/// 与番剧列表同一套栅格：列数断点、间距、行高公式都取自原版。
SliverGridDelegate mediaGridDelegate(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  int crossCount = 3;
  if (width > LayoutBreakpoint.compact['width']!) {
    crossCount = 5;
  }
  if (width > LayoutBreakpoint.medium['width']!) {
    crossCount = 6;
  }
  return SliverGridDelegateWithFixedCrossAxisCount(
    mainAxisSpacing: StyleString.cardSpace - 2,
    crossAxisSpacing: StyleString.cardSpace,
    crossAxisCount: crossCount,
    mainAxisExtent: width / crossCount / 0.65 +
        MediaQuery.textScalerOf(context).scale(32.0),
  );
}

class _PosterSkeleton extends StatelessWidget {
  const _PosterSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 12,
          width: 80,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }
}

/// 海报卡片：Hero + NetworkImgLayer（与原版同构），长按出操作菜单。
class MediaPosterCard extends StatelessWidget {
  const MediaPosterCard({super.key, required this.item});

  final MediaItem item;

  void _open(BuildContext context) {
    context.pushNamed('/media/detail', arguments: item);
  }

  void _showHoldMenu(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        children: [
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(dialogContext);
              _open(context);
            },
            child: const Text('查看详情'),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(dialogContext);
              launchUrl(
                Uri.parse(
                  'https://www.themoviedb.org/${item.kind == MediaKind.tv ? 'tv' : 'movie'}/${item.id}',
                ),
                mode: LaunchMode.externalApplication,
              );
            },
            child: const Text('在 TMDB 打开'),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(dialogContext);
              KazumiDialog.showToast(context: context, message: item.title);
            },
            child: const Text('显示标题'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _open(context),
      onLongPress: () => _showHoldMenu(context),
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => Hero(
                tag: MediaDetailPage.heroTagOf(item),
                transitionOnUserGestures: true,
                flightShuttleBuilder:
                    NetworkImgLayer.heroFlightShuttleBuilder,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      NetworkImgLayer(
                        src: item.posterUrl ?? '',
                        width: box.maxWidth,
                        height: box.maxHeight,
                        fadeInDuration: Duration.zero,
                        fadeOutDuration: Duration.zero,
                      ),
                      if (item.rating != null)
                        Positioned(
                          right: 6,
                          top: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              item.rating!.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, height: 1.25),
          ),
        ],
      ),
    );
  }
}
/// 详情页点标签后，把「按类型搜索」的请求传回影视列表。
class MediaSearchBus extends ChangeNotifier {
  MediaKind? kind;
  String? keyword;

  void search(MediaKind kind, String keyword) {
    this.kind = kind;
    this.keyword = keyword;
    notifyListeners();
  }
}

final MediaSearchBus mediaSearchBus = MediaSearchBus();
