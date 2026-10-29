// TMDB API 凭证。
//
// 构建时通过 --dart-define-from-file 注入，源码里不留明文：
//   flutter build windows --release --dart-define-from-file=local/credentials.json
// 对应 JSON： { "TMDB_API_KEY": "..." }
//
// 支持两种 Key 形式：
//   - v3 API Key（32 位十六进制）→ 作为 api_key 查询参数
//   - v4 Read Access Token（以 eyJ 开头的 JWT）→ 作为 Authorization: Bearer
const String tmdbApiKey = String.fromEnvironment('TMDB_API_KEY');

bool get hasTmdbCredentials => tmdbApiKey.trim().isNotEmpty;

bool get tmdbKeyIsBearer => tmdbApiKey.trim().startsWith('eyJ');