import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/widget/bangumi_mirror_error_widget.dart';
import 'package:kazumi/bean/widget/kazumi_menu.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/popular/popular_controller.dart';
import 'package:kazumi/bean/card/bangumi_card.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:window_manager/window_manager.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/platform/desktop_window_config.dart';
import 'package:kazumi/bean/appbar/drag_to_move_bar.dart' as dtb;
import 'package:kazumi/modules/media/media_item.dart';
import 'package:kazumi/pages/media/media_grid.dart';
import 'package:kazumi/utils/device.dart';

class PopularPage extends StatefulWidget {
  const PopularPage({
    super.key,
    required this.controller,
  });

  final PopularController controller;

  @override
  State<PopularPage> createState() => _PopularPageState();
}

class _PopularPageState extends State<PopularPage> {
  late final ScrollController scrollController;
  PopularController get popularController => widget.controller;

  /// 当前浏览的内容类型。null 表示番剧（沿用原有逻辑）。
  MediaKind? _mediaKind;
  MediaSort _mediaSort = MediaSort.popular;
  MediaGridController? _gridController;
  final TextEditingController _mediaSearchController = TextEditingController();
  final ScrollController _mediaScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    scrollController = ScrollController(
      initialScrollOffset: popularController.scrollOffset,
    );
    scrollController.addListener(scrollListener);
    if (popularController.trendList.isEmpty) {
      popularController.queryBangumiByTrend();
    }
    mediaSearchBus.addListener(_onMediaSearchRequest);
  }

  @override
  void dispose() {
    scrollController.removeListener(scrollListener);
    scrollController.dispose();
    super.dispose();
  }

  void _onMediaSearchRequest() {
    final kind = mediaSearchBus.kind;
    final keyword = mediaSearchBus.keyword;
    if (kind == null || keyword == null || keyword.isEmpty) return;
    _openMedia(kind, MediaSort.popular);
    _gridController?.search(keyword);
    _mediaSearchController.text = keyword;
  }

  void scrollListener() {
    popularController.scrollOffset = scrollController.offset;
    if (scrollController.position.pixels >=
            scrollController.position.maxScrollExtent - 200 &&
        !popularController.isLoadingMore) {
      KazumiLogger()
          .i('PopularPageController: Fetching next recommendation batch');
      if (popularController.currentTag != '') {
        popularController.queryBangumiByTag();
      } else {
        popularController.queryBangumiByTrend();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 影视模式：与番剧同一套 SliverAppBar（标题折叠/拉伸一致），列表是 sliver。
    if (_mediaKind != null) {
      final controller = _gridController!;
      // 影视模式：与番剧完全同一套 SliverAppBar 参数（actions/背景/拖动区/FAB）。
      return Scaffold(
        floatingActionButton: FloatingActionButton(
          onPressed: () => _mediaScrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
          ),
          child: const Icon(Icons.arrow_upward),
        ),
        body: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.pixels >=
                notification.metrics.maxScrollExtent - 600) {
              controller.loadMore();
            }
            return false;
          },
          child: CustomScrollView(
            controller: _mediaScrollController,
            slivers: [
              SliverAppBar(
                pinned: true,
                stretch: true,
                expandedHeight: 120,
                elevation: 0,
                titleSpacing: 0,
                centerTitle: false,
                backgroundColor: Theme.of(context).colorScheme.surface,
                title: null,
                actions: _mediaActions(),
                flexibleSpace: SafeArea(
                  child: dtb.DragToMoveArea(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final double maxExtent =
                            120 - MediaQuery.of(context).padding.top;
                        final t = (1 -
                                ((constraints.maxHeight - kToolbarHeight) /
                                        (maxExtent - kToolbarHeight))
                                    .clamp(0.0, 1.0));
                        final fontWeight =
                            t < 0.5 ? FontWeight.w700 : FontWeight.w500;
                        final fontSize = lerpDouble(28, 20, t)!;
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(
                                left: 16, top: 8, bottom: 8, right: 60),
                            child: SizedBox(
                              height: 44,
                              child: _buildTitleMenu(
                                fontSize: fontSize,
                                fontWeight: fontWeight,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              MediaGridHeaderSliver(
                controller: controller,
                searchController: _mediaSearchController,
              ),
              if (controller.loading && controller.items.isNotEmpty)
                const SliverToBoxAdapter(
                  child: LinearProgressIndicator(minHeight: 4),
                ),
              MediaGridSliver(controller: controller),
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      body: CustomScrollView(
        controller: scrollController,
        slivers: [
          buildSliverAppBar(),
          SliverToBoxAdapter(
            child: Observer(
              builder: (_) => AnimatedOpacity(
                opacity: popularController.isLoadingMore ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: popularController.isLoadingMore
                    ? const LinearProgressIndicator(minHeight: 4)
                    : const SizedBox(height: 4),
              ),
            ),
          ),
          SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                  StyleString.cardSpace, 0, StyleString.cardSpace, 0),
              sliver: Observer(builder: (_) {
                if (popularController.isTimeOut) {
                  return SliverToBoxAdapter(
                    child: SizedBox(
                      height: 400,
                      child: BangumiMirrorErrorWidget(
                        onRetry: () {
                          if (popularController.trendList.isEmpty) {
                            popularController.queryBangumiByTrend();
                          } else {
                            popularController.queryBangumiByTag();
                          }
                        },
                        onSettingsReturned: () {
                          if (mounted) {
                            setState(() {});
                          }
                        },
                      ),
                    ),
                  );
                }
                return contentGrid(
                  (popularController.currentTag == '')
                      ? popularController.trendList
                      : popularController.bangumiList,
                );
              })),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => scrollController.animateTo(0,
            duration: const Duration(milliseconds: 350), curve: Curves.easeOut),
        child: const Icon(Icons.arrow_upward),
      ),
    );
  }

  /// 顶部标题即内容/分类选择器：番剧、电影、剧集各带自己的分类。
  Widget _buildTitleMenu({
    required double fontSize,
    required FontWeight fontWeight,
  }) {
    final theme = Theme.of(context);
    final bool isAnime = _mediaKind == null;
    final String title = isAnime
        ? (popularController.currentTag == ''
            ? '热门番组'
            : popularController.currentTag)
        : '${_mediaKind!.label} · ${_mediaSort == MediaSort.popular ? '热门' : '高分'}';

    List<Widget> mediaItems(MediaKind kind) => [
          KazumiMenuItem(
            label: '热门',
            selected:
                _mediaKind == kind && _mediaSort == MediaSort.popular,
            onPressed: () => _openMedia(kind, MediaSort.popular),
          ),
          KazumiMenuItem(
            label: '高分',
            selected:
                _mediaKind == kind && _mediaSort == MediaSort.topRated,
            onPressed: () => _openMedia(kind, MediaSort.topRated),
          ),
        ];

    return KazumiMenuButton(
      animated: true,
      style: const MenuStyle(
        maximumSize: WidgetStatePropertyAll(Size(240, 400)),
      ),
      menuChildren: [
        SubmenuButton(
          menuChildren: [
            for (final tag in ['', ...defaultAnimeTags])
              KazumiMenuItem(
                label: tag.isEmpty ? '热门番组' : tag,
                selected: isAnime && tag == popularController.currentTag,
                onPressed: () => _selectTag(tag),
              ),
          ],
          child: const Text('番剧'),
        ),
        SubmenuButton(
          menuChildren: mediaItems(MediaKind.movie),
          child: const Text('电影'),
        ),
        SubmenuButton(
          menuChildren: mediaItems(MediaKind.tv),
          child: const Text('剧集'),
        ),
      ],
      builder: (context, toggle) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: toggle,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineMedium!.copyWith(
                  fontWeight: fontWeight,
                  fontSize: fontSize,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down,
                size: fontSize, color: theme.iconTheme.color),
          ],
        ),
      ),
    );
  }

  List<Widget> _mediaActions() => <Widget>[
        IconButton(
          tooltip: '历史记录',
          onPressed: () => context.pushNamed('/settings/history/'),
          icon: const Icon(Icons.history),
        ),
        if (isDesktop() && !DesktopWindowConfig.showWindowButton)
          IconButton(
            tooltip: '退出',
            onPressed: () => windowManager.close(),
            icon: const Icon(Icons.close),
          ),
      ];

  void _openMedia(MediaKind kind, MediaSort sort) {
    _gridController?.dispose();
    final controller = MediaGridController(kind: kind)..sort = sort;
    controller.reload();
    setState(() {
      _mediaKind = kind;
      _mediaSort = sort;
      _gridController = controller;
      _mediaSearchController.clear();
    });
  }

  Widget contentGrid(List<BangumiItem> bangumiList) {
    int crossCount = 3;
    if (MediaQuery.sizeOf(context).width > LayoutBreakpoint.compact['width']!) {
      crossCount = 5;
    }
    if (MediaQuery.sizeOf(context).width > LayoutBreakpoint.medium['width']!) {
      crossCount = 6;
    }
    return SliverPadding(
      padding: const EdgeInsets.all(8),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          // 行间距
          mainAxisSpacing: StyleString.cardSpace - 2,
          // 列间距
          crossAxisSpacing: StyleString.cardSpace,
          // 列数
          crossAxisCount: crossCount,
          mainAxisExtent:
              MediaQuery.of(context).size.width / crossCount / 0.65 +
                  MediaQuery.textScalerOf(context).scale(32.0),
        ),
        delegate: SliverChildBuilderDelegate(
          (BuildContext context, int index) {
            return bangumiList.isNotEmpty
                ? BangumiCardV(bangumiItem: bangumiList[index])
                : null;
          },
          childCount: bangumiList.isNotEmpty ? bangumiList.length : 10,
        ),
      ),
    );
  }

  Widget buildSliverAppBar() {
    return SliverAppBar(
      pinned: true,
      stretch: true,
      expandedHeight: 120,
      elevation: 0,
      titleSpacing: 0,
      centerTitle: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      actions: buildActions(),
      title: null,
      flexibleSpace: SafeArea(
        child: dtb.DragToMoveArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double maxExtent = 120 - MediaQuery.of(context).padding.top;
              final t = (1 -
                  ((constraints.maxHeight - kToolbarHeight) /
                          (maxExtent - kToolbarHeight))
                      .clamp(0.0, 1.0));
              // 字重收缩后为 w500，展开时为 w700
              final fontWeight = t < 0.5 ? FontWeight.w700 : FontWeight.w500;
              final fontSize = lerpDouble(28, 20, t)!;
              return Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(
                      left: 16, top: 8, bottom: 8, right: 60),
                  child: SizedBox(
                    height: 44,
                    child: Observer(
                      builder: (_) => _buildTitleMenu(
                        fontSize: fontSize,
                        fontWeight: fontWeight,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> buildActions() {
    return <Widget>[
      if (MediaQuery.of(context).orientation == Orientation.portrait)
        IconButton(
          tooltip: '搜索',
          onPressed: () => context.pushNamed('/search/'),
          icon: const Icon(Icons.search),
        ),
      IconButton(
        tooltip: '历史记录',
        onPressed: () => context.pushNamed('/settings/history/'),
        icon: const Icon(Icons.history),
      ),
      if (isDesktop() && !DesktopWindowConfig.showWindowButton)
        IconButton(
          tooltip: '退出',
          onPressed: () => windowManager.close(),
          icon: const Icon(Icons.close),
        ),
    ];
  }

  Future<void> _selectTag(String selected) async {
    // 从影视切回番剧时，先退出影视模式。
    if (_mediaKind != null) {
      setState(() => _mediaKind = null);
    }
    if (!mounted || selected == popularController.currentTag) return;
    scrollController.animateTo(0,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    popularController.setCurrentTag(selected);
    if (selected.isEmpty) {
      popularController.clearBangumiList();
      if (popularController.trendList.isEmpty) {
        await popularController.queryBangumiByTrend();
      }
    } else {
      await popularController.queryBangumiByTag(type: 'init');
    }
  }
}
