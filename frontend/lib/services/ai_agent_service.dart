import 'package:dio/dio.dart';
import '../core/network/api_client.dart';
import '../core/network/api_enpoints.dart';
import '../models/ai_agent_response.dart';

class AiAgentService {
  final Dio? _customDio;

  AiAgentService({Dio? dio}) : _customDio = dio;

  Future<AiAgentResponse> sendMessage({
    required String message,
    String language = 'en',
    List<double>? coordinates,
    String? addressLine,
    Map<String, dynamic>? conversationState,
    String? userToken,
  }) async {
    final payload = <String, dynamic>{
      'message': message,
      'language': language,
    };
    if (coordinates != null) payload['coordinates'] = coordinates;
    if (addressLine != null) payload['addressLine'] = addressLine;
    if (conversationState != null) {
      payload['conversationState'] = conversationState;
    }

    if (_customDio != null) {
      final response = await _customDio.post(
        ApiEndpoints.aiAgentChat,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            if (userToken != null) 'Authorization': 'Bearer $userToken',
          },
        ),
        data: payload,
      );
      return AiAgentResponse.fromJson(response.data);
    }

    final res = await ApiServices.client.post(
      ApiEndpoints.aiAgentChat,
      data: payload,
    );

    return AiAgentResponse.fromJson(res);
  }
}
