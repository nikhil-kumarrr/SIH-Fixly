import PushToken from '../models/PushToken.js';
import { sendToToken, isPermanentTokenError } from './fcmService.js';
import { isFirebaseConfigured } from '../config/firebase.js';

/**
 * Dispatches High-Priority VoIP / Incoming Call Push Notification via FCM.
 * Triggers native full-screen incoming call UI (WhatsApp/Telegram style) with ringtone
 * even when the mobile app is completely closed or minimized.
 */
export const sendIncomingCallPush = async ({
    recipientUserId,
    bookingId,
    callSessionId,
    callerId,
    callerName,
    callerAvatar,
    callerRole,
    serviceTitle
}) => {
    if (!recipientUserId) return { success: false, reason: 'NO_RECIPIENT' };

    try {
        if (!isFirebaseConfigured()) {
            console.warn('[WebRTC Call Push] Firebase is not configured in environment. Push notification skipped.');
            return { success: false, reason: 'FCM_NOT_CONFIGURED' };
        }

        const activeTokens = await PushToken.find({
            user: recipientUserId,
            isActive: true
        }).select('token deviceId');

        if (!activeTokens || activeTokens.length === 0) {
            console.log(`[WebRTC Call Push] No active device tokens found for user ${recipientUserId}`);
            return { success: false, reason: 'NO_ACTIVE_TOKENS' };
        }

        // High priority data payload for Flutter CallKit / ConnectionService
        const callPayload = {
            type: 'INCOMING_CALL',
            callSessionId: String(callSessionId || `call_${bookingId}_${Date.now()}`),
            bookingId: String(bookingId),
            callerId: String(callerId || ''),
            callerName: String(callerName || (callerRole === 'customer' ? 'Customer' : 'Worker')),
            callerAvatar: String(callerAvatar || ''),
            callerRole: String(callerRole === 'customer' ? 'customer' : 'worker'),
            serviceTitle: String(serviceTitle || 'Gig Service'),
            hasAudio: 'true',
            hasVideo: 'false',
            timestamp: String(Date.now())
        };

        const pushPromises = activeTokens.map(async ({ token }) => {
            try {
                await sendToToken({
                    token,
                    data: callPayload,
                    dataOnly: true,
                    android: {
                        priority: 'high',
                        ttl: 30000 // 30 seconds ringing timeout
                    },
                    apns: {
                        headers: {
                            'apns-priority': '10',
                            'apns-push-type': 'voip'
                        },
                        payload: {
                            aps: {
                                'content-available': 1
                            }
                        }
                    }
                });
                return { token, success: true };
            } catch (error) {
                console.warn(`[WebRTC Call Push] Failed for token ${token.slice(0, 8)}...:`, error.message);
                if (isPermanentTokenError(error)) {
                    await PushToken.updateOne({ token }, { isActive: false });
                }
                return { token, success: false, error: error.message };
            }
        });

        const results = await Promise.allSettled(pushPromises);
        return { success: true, count: results.length };
    } catch (error) {
        console.error('[WebRTC Call Push] Unexpected error:', error);
        return { success: false, error: error.message };
    }
};

/**
 * Dispatches a silent dismiss push when caller hangs up before recipient answers
 * so that the incoming call ringtone stops immediately on the closed/background app.
 */
export const sendCancelCallPush = async ({
    recipientUserId,
    bookingId,
    callSessionId
}) => {
    if (!recipientUserId || !isFirebaseConfigured()) return;

    try {
        const activeTokens = await PushToken.find({
            user: recipientUserId,
            isActive: true
        }).select('token');

        if (!activeTokens || activeTokens.length === 0) return;

        const cancelPayload = {
            type: 'CANCEL_CALL',
            callSessionId: String(callSessionId || ''),
            bookingId: String(bookingId),
            timestamp: String(Date.now())
        };

        await Promise.allSettled(
            activeTokens.map(({ token }) =>
                sendToToken({
                    token,
                    data: cancelPayload,
                    dataOnly: true,
                    android: { priority: 'high', ttl: 10000 },
                    apns: { headers: { 'apns-priority': '10' } }
                }).catch(() => {})
            )
        );
    } catch (err) {
        console.warn('[WebRTC Cancel Push] Warning:', err.message);
    }
};
