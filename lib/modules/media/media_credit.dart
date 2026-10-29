/// 演职员条目（角色 / 制作人员通用）。
class MediaCredit {
  const MediaCredit({
    required this.name,
    required this.role,
    this.character = '',
    this.profileUrl,
    this.order = 0,
  });

  /// 姓名。
  final String name;

  /// 职务：演员填「演员」，制作人员填具体职位（导演/编剧/音乐…）。
  final String role;

  /// 饰演角色（仅演员有）。
  final String character;

  final String? profileUrl;

  /// 排序权重（TMDB order 字段，越小越靠前）。
  final int order;
}