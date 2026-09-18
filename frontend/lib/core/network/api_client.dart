import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../auth/device_id.dart';
import '../auth/token_storage.dart';
import '../preferences/app_preferences.dart';
import 'api_config.dart';
import 'api_enpoints.dart';
import 'api_exception.dart';

/// Shared Dio client: single-flight GET, short TTL GET cache, one refresh lock.
class ApiClient {
  ApiClient({
    required TokenStorage tokenStorage,
    required DeviceId deviceId,
    Dio? dio,
  }) : _tokens = tokenStorage,
       _deviceId = deviceId,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: ApiConfig.baseUrl,
               connectTimeout: const Duration(seconds: 5),
               sendTimeout: const Duration(seconds: 30),
               receiveTimeout: const Duration(seconds: 30),
               headers: {
                 'Accept': 'application/json',
                 'Content-Type': 'application/json',
               },
             ),
           ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          debugPrint('🌐 [HTTP REQ] ${options.method} ${options.baseUrl}${options.path}');
          if (!_isAuthPath(options.path)) {
            var access = await _tokens.accessToken;
            if (access == null || access.isEmpty) {
              final refresh = await _tokens.refreshToken;
              if (refresh != null && refresh.isNotEmpty) {
                // Proactively refresh before sending to avoid "token missing" rejection
                final ok = await _tryRefresh();
                if (ok) {
                  access = await _tokens.accessToken;
                }
              }
            }
            if (access != null && access.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $access';
            }
          }
          final device = await _deviceId.getOrCreate();
          options.headers['x-device-id'] = device;
          final locale = AppPreferences.instance.locale;
          if (locale.isNotEmpty) {
            options.headers['Accept-Language'] = locale;
            options.queryParameters.putIfAbsent('lang', () => locale);
          }
          handler.next(options);
        },
        onResponse: (response, handler) {
          debugPrint('✅ [HTTP RES] ${response.statusCode} ${response.requestOptions.path}');
          handler.next(response);
        },
        onError: (error, handler) async {
          debugPrint('❌ [HTTP ERR] ${error.response?.statusCode} ${error.requestOptions.path}: ${error.message}');
          // 1. 401 Unauthorized -> Refresh token
          if (error.response?.statusCode == 401 &&
              !_isAuthPath(error.requestOptions.path) &&
              error.requestOptions.extra['retried'] != true) {
            final refreshed = await _tryRefresh();
            if (refreshed) {
              final req = error.requestOptions;
              req.extra['retried'] = true;
              final access = await _tokens.accessToken;
              if (access != null && access.isNotEmpty) {
                req.headers['Authorization'] = 'Bearer $access';
              }
              try {
                final response = await _dio.fetch(req);
                return handler.resolve(response);
              } on DioException catch (retryErr) {
                if (retryErr.response?.statusCode == 401 ||
                    retryErr.response?.statusCode == 403) {
                  await _tokens.clearSession();
                  clearGetCache();
                }
                return handler.next(retryErr);
              } catch (_) {
                return handler.next(error);
              }
            }
            if (_sessionInvalidated) {
              await _tokens.clearSession();
              clearGetCache();
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  static const _getTtl = Duration(seconds: 20);

  final Dio _dio;
  final TokenStorage _tokens;
  final DeviceId _deviceId;
  Future<bool>? _refreshInFlight;
  bool _sessionInvalidated = false;

  final Map<String, Future<Map<String, dynamic>>> _getInFlight = {};
  final Map<String, _CachedGet> _getCache = {};

  Dio get dio => _dio;

  void clearGetCache() {
    _getCache.clear();
    _getInFlight.clear();
  }

  static bool _isAuthPath(String path) => ApiEndpoints.isAuthPath(path);

  Future<bool> _tryRefresh() {
    final inflight = _refreshInFlight;
    if (inflight != null) return inflight;
    final next = _doRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
    _refreshInFlight = next;
    return next;
  }

  Future<bool> _doRefresh() async {
    final refresh = await _tokens.refreshToken;
    final userId = await _tokens.userId;
    final device = await _deviceId.getOrCreate();
    if (refresh == null ||
        refresh.isEmpty ||
        userId == null ||
        userId.isEmpty) {
      return false;
    }
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        ApiEndpoints.refreshToken,
        data: {'userId': userId, 'deviceId': device, 'refreshToken': refresh},
        options: Options(extra: {'retried': true}),
      );
      final data = res.data;
      if (data == null || data['success'] != true) return false;
      final access = data['accessToken'] as String?;
      if (access == null || access.isEmpty) return false;
      final newRefresh = data['refreshToken'] as String?;
      await _tokens.saveTokens(accessToken: access, refreshToken: newRefresh);
      _sessionInvalidated = false;
      return true;
    } on DioException catch (dioErr) {
      final status = dioErr.response?.statusCode;
      if (status == 401 || status == 403) {
        _sessionInvalidated = true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  String _getKey(String path, Map<String, dynamic>? query) {
    final lang = AppPreferences.instance.locale;
    final base = 'GET [$lang] $path';
    if (query == null || query.isEmpty) return base;
    final keys = query.keys.toList()..sort();
    final q = keys.map((k) => '$k=${query[k]}').join('&');
    return '$base?$q';
  }

  void clearCache() {
    _getCache.clear();
  }

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    bool forceNetwork = false,
  }) async {
    final key = _getKey(path, query);
    if (!forceNetwork) {
      final cached = _getCache[key];
      if (cached != null && !cached.isExpired) {
        return Map<String, dynamic>.from(cached.body);
      }
      final inflight = _getInFlight[key];
      if (inflight != null) {
        return Map<String, dynamic>.from(await inflight);
      }
    }

    final future = _getNetwork(path, query);
    _getInFlight[key] = future;
    try {
      final body = await future;
      _getCache[key] = _CachedGet(
        Map<String, dynamic>.from(body),
        DateTime.now().add(_getTtl),
      );
      return Map<String, dynamic>.from(body);
    } finally {
      _getInFlight.remove(key);
    }
  }

  Future<Map<String, dynamic>> _getNetwork(
    String path,
    Map<String, dynamic>? query,
  ) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        path,
        queryParameters: query,
      );
      return res.data ?? {};
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Object? data,
    Options? options,
  }) async {
    clearGetCache();
    try {
      final opts = options ?? Options();
      if (data is FormData) {
        final headers = Map<String, dynamic>.from(opts.headers ?? {});
        headers.remove('Content-Type');
        opts.headers = headers;
        opts.contentType = Headers.multipartFormDataContentType;
      }
      final res = await _dio.post<dynamic>(path, data: data, options: opts);
      final body = res.data;
      if (body is Map<String, dynamic>) return body;
      if (body is Map) return Map<String, dynamic>.from(body);
      return {};
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<Map<String, dynamic>> patch(String path, {Object? data}) async {
    clearGetCache();
    try {
      final res = await _dio.patch<Map<String, dynamic>>(path, data: data);
      return res.data ?? {};
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<Map<String, dynamic>> delete(String path, {Object? data}) async {
    clearGetCache();
    try {
      final res = await _dio.delete<Map<String, dynamic>>(path, data: data);
      return res.data ?? {};
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<Map<String, dynamic>> put(String path, {Object? data}) async {
    clearGetCache();
    try {
      final res = await _dio.put<Map<String, dynamic>>(path, data: data);
      return res.data ?? {};
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  ApiException _mapError(DioException e) {
    final data = e.response?.data;
    String message = e.message ?? 'Network error';
    final lower = message.toLowerCase();
    if (data is Map && data['message'] != null) {
      message = data['message'].toString();
    } else if (data is String &&
        (data.contains('Cloudflare Tunnel error') ||
            data.contains('Error 1033'))) {
      message =
          'API tunnel is down. Ask host to restart cloudflared + backend.';
    } else if (data is String &&
        (data.contains('Cannot POST') ||
            data.contains('Cannot GET') ||
            data.contains('<!DOCTYPE html>'))) {
      // Express default HTML 404 — keep short for UI + fallbacks.
      final match = RegExp(r'Cannot (POST|GET|PUT|PATCH|DELETE) [^\s<]+')
          .firstMatch(data);
      message = match?.group(0) ?? 'Not found';
    } else if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection refused') ||
        lower.contains('network is unreachable') ||
        lower.contains('no internet') ||
        lower.contains('connection errored')) {
      final host = ApiConfig.baseUrl;
      message =
          'Cannot reach API ($host). Check Wi‑Fi/data and that the server is online.';
    }
    return ApiException(message, statusCode: e.response?.statusCode);
  }
}

class _CachedGet {
  _CachedGet(this.body, this.expiresAt);

  final Map<String, dynamic> body;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// App-wide singletons bootstrapped in [main].
class ApiServices {
  ApiServices._();

  static late final TokenStorage tokens;
  static late final DeviceId deviceId;
  static late final ApiClient client;

  static Future<void> init() async {
    tokens = TokenStorage();
    deviceId = DeviceId(tokens);
    await deviceId.getOrCreate();
    client = ApiClient(tokenStorage: tokens, deviceId: deviceId);
    // ignore: avoid_print — intentional boot diagnostic
    print('Fixly API_BASE_URL=${ApiConfig.baseUrl}');
  }
}
