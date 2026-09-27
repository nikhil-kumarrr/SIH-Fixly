import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/api_exception.dart';
import '../../data/support_api_repository.dart';
import '../../../../core/network/media_upload_api.dart';
import '../../../../shared/data/mock/mock_repository.dart';

part 'support_state.dart';

class SupportCubit extends Cubit<SupportState> {
  SupportCubit({SupportApiRepository? repository, MediaUploadApi? mediaUploadApi})
      : _repo = repository ?? SupportApiRepository(),
        _mediaUpload = mediaUploadApi ?? MediaUploadApi(),
        super(const SupportState());

  final SupportApiRepository _repo;
  final MediaUploadApi _mediaUpload;
  Timer? _pollTimer;

  @override
  Future<void> close() {
    _pollTimer?.cancel();
    return super.close();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      loadChat(silent: true);
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> loadChat({bool silent = false}) async {
    if (!silent) {
      emit(state.copyWith(status: SupportStatus.loading));
    }

    final ticket = await _repo.getActiveTicket();
    if (ticket != null) {
      final shouldPoll = ticket.isEscalated || ticket.isAgentActive;
      if (shouldPoll && _pollTimer == null) {
        _startPolling();
      } else if (!shouldPoll && _pollTimer != null) {
        _stopPolling();
      }

      emit(
        state.copyWith(
          status: SupportStatus.loaded,
          ticketId: ticket.id,
          ticketNumber: ticket.ticketNumber,
          ticketStatus: ticket.status,
          handledBy: ticket.handledBy,
          messages: ticket.messages,
          quickReplies: ticket.quickReplies,
          errorMessage: null,
        ),
      );
    } else {
      if (!silent) {
        emit(
          state.copyWith(
            status: SupportStatus.loaded,
            messages: const [],
            quickReplies: const [
              'Where is my technician?',
              'Cancel my booking',
              'Payment & refund issue',
              'Talk to human agent',
            ],
          ),
        );
      }
    }
  }

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.isSending) return;

    // Optimistic user message addition
    final optimisticMsg = SupportMessageModel(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      role: 'customer',
      body: trimmed,
      createdAt: DateTime.now(),
    );

    emit(
      state.copyWith(
        isSending: true,
        messages: [...state.messages, optimisticMsg],
      ),
    );

    final updatedTicket = await _repo.sendMessage(trimmed, ticketId: state.ticketId);
    if (updatedTicket != null) {
      final shouldPoll = updatedTicket.isEscalated || updatedTicket.isAgentActive;
      if (shouldPoll && _pollTimer == null) {
        _startPolling();
      } else if (!shouldPoll && _pollTimer != null) {
        _stopPolling();
      }

      emit(
        state.copyWith(
          isSending: false,
          ticketId: updatedTicket.id,
          ticketNumber: updatedTicket.ticketNumber,
          ticketStatus: updatedTicket.status,
          handledBy: updatedTicket.handledBy,
          messages: updatedTicket.messages,
          quickReplies: updatedTicket.quickReplies,
        ),
      );
    } else {
      emit(state.copyWith(isSending: false));
    }
  }

  /// Upload and send media (image, video, audio/voice note)
  Future<void> sendMediaMessage({
    required String filePath,
    required String mediaType, // 'image', 'video', 'audio'
    String? caption,
  }) async {
    if (state.isSending) return;

    emit(state.copyWith(isSending: true));

    try {
      // 1. Upload to Cloudinary via backend upload endpoint
      final uploadedUrl = await _mediaUpload.uploadFile(filePath);

      final displayText = (caption != null && caption.trim().isNotEmpty)
          ? caption.trim()
          : (mediaType == 'image'
              ? '📷 Photo attachment'
              : (mediaType == 'video'
                  ? '🎥 Video attachment'
                  : '🎙️ Voice note'));

      final updatedTicket = await _repo.sendMessage(
        displayText,
        ticketId: state.ticketId,
        attachments: [uploadedUrl],
        mediaType: mediaType,
      );

      if (updatedTicket != null) {
        final shouldPoll = updatedTicket.isEscalated || updatedTicket.isAgentActive;
        if (shouldPoll && _pollTimer == null) {
          _startPolling();
        }

        emit(
          state.copyWith(
            isSending: false,
            ticketId: updatedTicket.id,
            ticketNumber: updatedTicket.ticketNumber,
            ticketStatus: updatedTicket.status,
            handledBy: updatedTicket.handledBy,
            messages: updatedTicket.messages,
            quickReplies: updatedTicket.quickReplies,
          ),
        );
      } else {
        emit(state.copyWith(isSending: false));
      }
    } catch (e) {
      emit(state.copyWith(
        isSending: false,
        errorMessage: ApiException.fromError(e),
      ));
    }
  }

  Future<void> escalateToHuman() async {
    if (state.isEscalating || state.isEscalated) return;

    emit(state.copyWith(isEscalating: true));
    final ticket = await _repo.escalateTicket(ticketId: state.ticketId);

    if (ticket != null) {
      _startPolling();
      emit(
        state.copyWith(
          isEscalating: false,
          ticketStatus: ticket.status,
          handledBy: ticket.handledBy,
          messages: ticket.messages,
          quickReplies: ticket.quickReplies,
        ),
      );
    } else {
      emit(state.copyWith(isEscalating: false));
    }
  }

  /// Start fresh new chat with Fixly AI
  Future<void> resetChat() async {
    emit(state.copyWith(status: SupportStatus.loading));
    final ticket = await _repo.resetTicket();
    if (ticket != null) {
      _stopPolling();
      emit(
        state.copyWith(
          status: SupportStatus.loaded,
          ticketId: ticket.id,
          ticketNumber: ticket.ticketNumber,
          ticketStatus: ticket.status,
          handledBy: ticket.handledBy,
          messages: ticket.messages,
          quickReplies: ticket.quickReplies,
        ),
      );
    } else {
      await loadChat();
    }
  }

  Future<void> submitTicket({
    required String subject,
    required String description,
  }) async {
    emit(state.copyWith(status: SupportStatus.submitting));
    await MockRepository.instance.mockDelay();
    emit(
      state.copyWith(
        status: SupportStatus.ticketSubmitted,
        lastTicketSubject: subject,
      ),
    );
  }
}
