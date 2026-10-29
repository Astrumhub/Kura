import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/appbar/drag_to_move_bar.dart' as dtb;
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/embedded_native_control_area.dart';
import 'package:kazumi/bean/widget/kazumi_menu.dart';
import 'package:kazumi/modules/media/media_credit.dart';
import 'package:kazumi/modules/media/media_item.dart';
import 'package:kazumi/pages/media/media_bangumi_adapter.dart';
import 'package:kazumi/pages/media/media_grid.dart';
import 'package:kazumi/pages/media/media_info_card.dart';
import 'package:kazumi/pages/media/media_source_sheet.dart';
import 'package:kazumi/services/media/media_watch_store.dart';
import 'package:kazumi/services/metadata/tmdb_source.dart';
import 'package:kazumi/services/platform/desktop_window_config.dart';
import 'package:kazumi/utils/device.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

/// 影视详情页。骨架、尺寸、Tab 结构均对齐番剧 `InfoPage`。
class MediaDetailPage extends StatefulWidget {
  const MediaDetailPage({super.key, required this.item});

  final MediaItem item;

  static String heroTagOf(MediaItem item) => 'media-poster-${item.id}';

  @override
  State<MediaDetailPage> createState() => _MediaDetailPageState();
}

class _MediaDetailPageState extends State<MediaDetailPage>
    with SingleTickerProviderStateMixin {
  static const Duration _minimumLoadingDuration = Duration(milliseconds: 600);

  final TmdbSource _source = const TmdbSource();

  late MediaItem _item = widget.item;
  List<MediaSeason> _seasons = const [];
  List<MediaEpisode> _episodes = const [];
  int _seasonNumber = -1;
  bool _loadingEpisodes = false;
  bool _initialLoading = true;
  bool _fullIntro = false;
  bool _fullTag = false;

  List<MediaCredit> _cast = const [];
  List<MediaCredit> _crew = const [];
  List<MediaItem> _related = const [];
  List<String> _keywords = const [];
  bool _loadingCast = false;
  bool _loadingCrew = false;
  bool _loadingRelated = false;
  MediaWatchRecord? _watchRecord;

  bool get _isTv => _item.kind == MediaKind.tv;

  List<String> get _tabNames => <String>[
        '概览',
        if (_isTv) '剧集',
        '吐槽',
        '角色',
        '关联',
        '制作人员',
      ];

  late final TabController _tab =
      TabController(length: _tabNames.length, vsync: this);

  @override
  void initState() {
    super.initState();
    _tab.addListener(_onTabChanged);
    _loadDetail();
  }

  @override
  void dispose() {
    _tab.removeListener(_onTabChanged);
    _tab.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tab.indexIsChanging) return;
    switch (_tabNames[_tab.index]) {
      case '角色':
        _loadCast();
      case '关联':
        _loadRelated();
      case '制作人员':
        _loadCrew();
    }
  }

  Future<void> _loadDetail() async {
    final startedAt = DateTime.now();
    final detail = await _source.detail(_item.id, _item.kind);
    if (!mounted) return;
    if (detail != null) setState(() => _item = detail);

    final keywords = await _source.keywords(_item.id, _item.kind);
    if (mounted && keywords.isNotEmpty) {
      setState(() => _keywords = keywords);
    }

    if (_isTv) {
      final seasons = await _source.seasons(_item.id);
      if (mounted && seasons.isNotEmpty) {
        final initial = seasons.firstWhere(
          (s) => s.seasonNumber == 1,
          orElse: () => seasons.firstWhere(
            (s) => s.seasonNumber > 0,
            orElse: () => seasons.first,
          ),
        );
        setState(() {
          _seasons = seasons;
          _seasonNumber = initial.seasonNumber;
        });
        await _loadEpisodes(initial.seasonNumber);
      }
    }
    final record = await MediaWatchStore.get(int.tryParse(_item.id) ?? 0);
    if (mounted && record != null) {
      setState(() => _watchRecord = record);
    }
    final remaining =
        _minimumLoadingDuration - DateTime.now().difference(startedAt);
    if (remaining > Duration.zero) await Future.delayed(remaining);
    if (mounted) setState(() => _initialLoading = false);
  }

  Future<void> _loadEpisodes(int seasonNumber) async {
    setState(() {
      _loadingEpisodes = true;
      _seasonNumber = seasonNumber;
    });
    final episodes = await _source.episodes(_item.id, seasonNumber);
    if (!mounted) return;
    setState(() {
      _episodes = episodes;
      _loadingEpisodes = false;
    });
  }

  Future<void> _loadCast() async {
    if (_loadingCast || _cast.isNotEmpty) return;
    setState(() => _loadingCast = true);
    final result = await _source.credits(_item.id, _item.kind);
    if (!mounted) return;
    setState(() {
      _cast = result.cast.take(30).toList();
      _crew = result.crew; // 顺手缓存，切到制作人员时不必再请求
      _loadingCast = false;
    });
  }

  Future<void> _loadCrew() async {
    if (_loadingCrew || _crew.isNotEmpty) return;
    setState(() => _loadingCrew = true);
    final result = await _source.credits(_item.id, _item.kind);
    if (!mounted) return;
    setState(() {
      _cast = result.cast.take(30).toList();
      _crew = result.crew;
      _loadingCrew = false;
      _loadingCast = false;
    });
  }

  Future<void> _loadRelated() async {
    if (_loadingRelated || _related.isNotEmpty) return;
    setState(() => _loadingRelated = true);
    final items = await _source.recommendations(_item.id, _item.kind);
    if (!mounted) return;
    setState(() {
      _related = items;
      _loadingRelated = false;
    });
  }

  void _toast(String message) {
    if (mounted) KazumiDialog.showToast(context: context, message: message);
  }

  Future<void> _copyTitle() async {
    await Clipboard.setData(ClipboardData(text: _item.title));
    _toast('标题已复制');
  }

  Future<void> _openOnTmdb() async {
    final path = _isTv ? 'tv' : 'movie';
    if (!await launchUrl(
      Uri.parse('https://www.themoviedb.org/$path/${_item.id}'),
      mode: LaunchMode.externalApplication,
    )) {
      _toast('无法打开浏览器');
    }
  }

  void _startWatching() {
    final adapter = mediaToBangumiItem(_item);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      builder: (_) => MediaSourceSheet(
        title: _item.title,
        bangumiItem: adapter,
        onPlay: (args) {
          final navigator = Navigator.of(context);
          navigator.pop();
          context.pushNamed('/video/', arguments: args);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showWindowButton = DesktopWindowConfig.showWindowButton;
    final topOffset = Platform.isMacOS && showWindowButton ? 22.0 : 0.0;
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerScrolled) => <Widget>[
          SliverOverlapAbsorber(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            sliver: SliverAppBar.medium(
              automaticallyImplyLeading: false,
              scrolledUnderElevation: 0.0,
              leading: EmbeddedNativeControlArea(
                child: IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back),
                ),
              ),
              title: EmbeddedNativeControlArea(
                child: dtb.DragToMoveArea(
                  child: Container(
                    width: double.infinity,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              actions: [
                EmbeddedNativeControlArea(
                  child: KazumiMenuButton(
                    menuChildren: [
                      KazumiMenuItem(onPressed: _copyTitle, label: '复制标题'),
                      KazumiMenuItem(onPressed: _openOnTmdb, label: '外部打开'),
                      KazumiMenuItem(
                        onPressed: () => _toast('保存封面开发中'),
                        label: '保存封面',
                      ),
                    ],
                    builder: (context, toggle) => IconButton(
                      tooltip: '更多操作',
                      icon: const Icon(Icons.more_horiz_rounded),
                      onPressed: toggle,
                    ),
                  ),
                ),
                if (isDesktop() && !showWindowButton)
                  CloseButton(onPressed: () => windowManager.close()),
                const SizedBox(width: 8),
              ],
              toolbarHeight: kToolbarHeight + topOffset,
              stretch: true,
              centerTitle: false,
              expandedHeight:
                  308 + kTextTabBarHeight + kToolbarHeight + topOffset,
              collapsedHeight: kTextTabBarHeight +
                  kToolbarHeight +
                  MediaQuery.paddingOf(context).top +
                  topOffset,
              forceElevated: innerScrolled,
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.pin,
                background: Stack(
                  children: [
                    Positioned.fill(
                      bottom: kTextTabBarHeight,
                      child: IgnorePointer(
                        child: _MediaHeaderBackground(
                          imageUrl: _item.backdropUrl ?? '',
                        ),
                      ),
                    ),
                    SafeArea(
                      bottom: false,
                      child: EmbeddedNativeControlArea(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                                16, kToolbarHeight, 16, 0),
                            child: Skeletonizer(
                              enabled: _initialLoading,
                              child: MediaInfoCardV(
                                item: _initialLoading ? _skeletonItem : _item,
                                heroTag: MediaDetailPage.heroTagOf(_item),
                                onCollectTap: () => _toast('影视收藏开发中'),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              bottom: TabBar(
                controller: _tab,
                isScrollable: true,
                tabAlignment: TabAlignment.center,
                dividerHeight: 0,
                tabs: [for (final name in _tabNames) Tab(text: name)],
              ),
            ),
          ),
        ],
        body: Builder(
          builder: (context) {
            final handle =
                NestedScrollView.sliverOverlapAbsorberHandleFor(context);
            return TabBarView(
              controller: _tab,
              children: [
                for (final name in _tabNames) _buildTab(context, name, handle),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        tooltip: _isTv ? '开始观看' : '播放',
        onPressed: _startWatching,
        label: Text(_isTv ? '开始观看' : '播放'),
        icon: const Icon(Icons.play_arrow_rounded),
      ),
    );
  }

  Widget _buildTab(BuildContext context, String name, SliverOverlapAbsorberHandle handle) {
    switch (name) {
      case '概览':
        return CustomScrollView(
          slivers: [
            SliverOverlapInjector(handle: handle),
            SliverToBoxAdapter(child: _overviewBody(context)),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        );
      case '剧集':
        return CustomScrollView(
          slivers: [
            SliverOverlapInjector(handle: handle),
            ..._episodesSlivers(context),
          ],
        );
      case '角色':
        return _creditsTab(
          context,
          handle,
          loading: _loadingCast,
          credits: _cast,
          emptyText: '暂无角色信息',
          showCharacter: true,
        );
      case '制作人员':
        return _creditsTab(
          context,
          handle,
          loading: _loadingCrew,
          credits: _crew,
          emptyText: '暂无制作人员信息',
          showCharacter: false,
        );
      case '关联':
        return _relatedTab(context, handle);
      default:
        return CustomScrollView(
          slivers: [
            SliverOverlapInjector(handle: handle),
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('暂无')),
            ),
          ],
        );
    }
  }

  Widget _creditsTab(
    BuildContext context,
    SliverOverlapAbsorberHandle handle, {
    required bool loading,
    required List<MediaCredit> credits,
    required String emptyText,
    required bool showCharacter,
  }) {
    if (loading) {
      return CustomScrollView(
        slivers: [
          SliverOverlapInjector(handle: handle),
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }
    if (credits.isEmpty) {
      return CustomScrollView(
        slivers: [
          SliverOverlapInjector(handle: handle),
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text(emptyText)),
          ),
        ],
      );
    }
    return CustomScrollView(
      slivers: [
        SliverOverlapInjector(handle: handle),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          sliver: SliverList.separated(
            itemCount: credits.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final credit = credits[index];
              final subtitle = showCharacter
                  ? (credit.character.isEmpty ? '演员' : '饰 ${credit.character}')
                  : credit.role;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 20,
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: (credit.profileUrl ?? '').isEmpty
                      ? const Icon(Icons.person_outline, size: 20)
                      : ClipOval(
                          child: NetworkImgLayer(
                            src: credit.profileUrl!,
                            width: 40,
                            height: 40,
                          ),
                        ),
                ),
                title: Text(
                  credit.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _relatedTab(BuildContext context, SliverOverlapAbsorberHandle handle) {
    if (_loadingRelated) {
      return CustomScrollView(
        slivers: [
          SliverOverlapInjector(handle: handle),
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }
    if (_related.isEmpty) {
      return CustomScrollView(
        slivers: [
          SliverOverlapInjector(handle: handle),
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('暂无关联作品')),
          ),
        ],
      );
    }
    return CustomScrollView(
      slivers: [
        SliverOverlapInjector(handle: handle),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          sliver: SliverGrid(
            gridDelegate: mediaGridDelegate(context),
            delegate: SliverChildBuilderDelegate(
              (context, index) => MediaPosterCard(item: _related[index]),
              childCount: _related.length,
            ),
          ),
        ),
      ],
    );
  }

  MediaItem get _skeletonItem => MediaItem(
        id: _item.id,
        kind: _item.kind,
        title: _item.title,
        posterUrl: _item.posterUrl,
        backdropUrl: _item.backdropUrl,
        overview: '加载中',
        genres: const ['加载中', '加载中'],
        rating: 0,
        ratingCount: 0,
        year: 2000,
      );

  Widget _resumeCard(BuildContext context) {
    final record = _watchRecord!;
    final scheme = Theme.of(context).colorScheme;
    final label = record.episode > 0
        ? '上次看到 第 ${record.episode} 集 · ${record.progressLabel}'
        : '上次看到 ${record.progressLabel}';
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _startWatching,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.play_circle_fill_rounded, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              Text(
                '继续观看',
                style: TextStyle(fontSize: 12, color: scheme.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _overviewBody(BuildContext context) {
    const maxWidth = 950.0;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final available = screenWidth > maxWidth ? maxWidth : screenWidth - 32;
    final tags = <String>[
      ..._item.genres,
      ..._keywords,
    ];
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SizedBox(
          width: available,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_watchRecord != null) ...[
                _resumeCard(context),
                const SizedBox(height: 16),
              ],
              const Text('简介', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final text =
                      _item.overview.isEmpty ? '暂无简介' : _item.overview;
                  final tp = TextPainter(
                    text: TextSpan(text: text),
                    textDirection: TextDirection.ltr,
                  )..layout(maxWidth: constraints.maxWidth);
                  if (tp.computeLineMetrics().length > 7) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        SizedBox(
                          height: _fullIntro ? null : 120,
                          width: available,
                          child: SelectableText(
                            text,
                            scrollBehavior: const ScrollBehavior().copyWith(
                              scrollbars: false,
                            ),
                            scrollPhysics: const NeverScrollableScrollPhysics(),
                            selectionHeightStyle: ui.BoxHeightStyle.max,
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              setState(() => _fullIntro = !_fullIntro),
                          child: Text(_fullIntro ? '加载更少' : '加载更多'),
                        ),
                      ],
                    );
                  }
                  return SelectableText(
                    text,
                    scrollPhysics: const NeverScrollableScrollPhysics(),
                    selectionHeightStyle: ui.BoxHeightStyle.max,
                  );
                },
              ),
              const SizedBox(height: 16),
              const Text('标签', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8.0,
                runSpacing: isDesktop() ? 8 : 0,
                children: List<Widget>.generate(
                  _fullTag || tags.length < 13 ? tags.length : 13, (index) {
                  if (!_fullTag && index == 12) {
                    return ActionChip(
                      label: Text(
                        '更多 +',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      onPressed: () => setState(() => _fullTag = !_fullTag),
                    );
                  }
                  return ActionChip(
                    label: Text(tags[index]),
                    onPressed: () {
                      mediaSearchBus.search(_item.kind, tags[index]);
                      Navigator.of(context).maybePop();
                    },
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _episodesSlivers(BuildContext context) {
    final theme = Theme.of(context);
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        sliver: SliverToBoxAdapter(child: _seasonsRow(theme)),
      ),
      if (_loadingEpisodes)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        )
      else if (_episodes.isEmpty)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: Text('暂无集数信息')),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          sliver: SliverList.separated(
            itemCount: _episodes.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final episode = _episodes[index];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 16,
                  child: Text(
                    '${episode.episodeNumber}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                title: Text(
                  episode.title.isEmpty
                      ? '第 ${episode.episodeNumber} 集'
                      : episode.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [
                    episode.code,
                    if (episode.airDate != null) episode.airDate!,
                  ].join('  ·  '),
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: const Icon(Icons.play_circle_outline),
                onTap: _startWatching,
              );
            },
          ),
        ),
    ];
  }

  Widget _seasonsRow(ThemeData theme) {
    if (_seasons.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        Text('季', style: theme.textTheme.labelLarge),
        const SizedBox(width: 12),
        DropdownButton<int>(
          value: _seasons.any((s) => s.seasonNumber == _seasonNumber)
              ? _seasonNumber
              : null,
          hint: const Text('选择季'),
          items: [
            for (final season in _seasons)
              DropdownMenuItem(
                value: season.seasonNumber,
                child: Text('${season.name}（${season.episodeCount} 集）'),
              ),
          ],
          onChanged: (value) {
            if (value != null) _loadEpisodes(value);
          },
        ),
      ],
    );
  }
}

/// 背景：照原版 `_InfoHeaderBackground` 参数实现。
class _MediaHeaderBackground extends StatelessWidget {
  const _MediaHeaderBackground({required this.imageUrl});

  static const double _downsample = 0.5;
  static const double _blurSigma = 15.0;
  static const double _opacity = 0.4;
  static const double _edgeBleed = 32.0;
  static const double _bottomFeatherHeight = 48.0;

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        if (width <= 0 || height <= 0) return const SizedBox.shrink();
        final rasterWidth = width * _downsample;
        final rasterHeight = (height + _edgeBleed) * _downsample;
        final backgroundColor = Theme.of(context).scaffoldBackgroundColor;
        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white, Colors.transparent],
                  stops: [0.8, 1],
                ).createShader(bounds),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: RepaintBoundary(
                    child: Transform.scale(
                      scale: 1 / _downsample,
                      alignment: Alignment.topCenter,
                      filterQuality: FilterQuality.low,
                      child: SizedBox(
                        width: rasterWidth,
                        height: rasterHeight,
                        child: ImageFiltered(
                          imageFilter: ui.ImageFilter.blur(
                            sigmaX: _blurSigma * _downsample,
                            sigmaY: _blurSigma * _downsample,
                          ),
                          child: NetworkImgLayer(
                            src: imageUrl,
                            width: rasterWidth,
                            height: rasterHeight,
                            fadeInDuration: Duration.zero,
                            fadeOutDuration: Duration.zero,
                            filterQuality: FilterQuality.low,
                            color: Colors.white.withValues(alpha: _opacity),
                            colorBlendMode: BlendMode.modulate,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: _bottomFeatherHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        backgroundColor.withValues(alpha: 0),
                        backgroundColor.withValues(alpha: 0.55),
                        backgroundColor,
                      ],
                      stops: const [0, 0.72, 1],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
