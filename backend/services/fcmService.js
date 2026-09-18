import { getMessaging } from 'firebase-admin/messaging';

import { firebaseApp, isFirebaseConfigured } from '../config/firebase.js';

const invalidTokenCodes = new Set([
    'messaging/registration-token-not-registered',
    'messaging/invalid-registration-token',
]);

const ensureMessaging = () => {
    if (!isFirebaseConfigured()) {
        throw new Error('FCM is not configured. Set FCM credentials before sending push notifications.');
    }
    return getMessaging(firebaseApp);
};

export const isPermanentTokenError = (error) => invalidTokenCodes.has(error?.code);

export const sendToToken = async ({ token, title, body, data = {}, android, apns, dataOnly = false }) => {
    const message = {
        token,
        // Data-only messages guarantee the Flutter background isolate runs (so CallKit shows)
        // and prevent the OS from drawing a second tray banner alongside the call UI.
        ...(dataOnly ? {} : { notification: { title, body } }),
        data: Object.fromEntries(Object.entries(data).map(([key, value]) => [key, String(value)])),
        ...(android ? { android } : {}),
        ...(apns ? { apns } : {}),
    };
    return ensureMessaging().send(message);
};

export const sendToTokens = async ({ tokens, title, body, data = {} }) => {
    if (!tokens.length) return { successCount: 0, failureCount: 0, responses: [] };
    const message = {
        tokens,
        notification: { title, body },
        data: Object.fromEntries(Object.entries(data).map(([key, value]) => [key, String(value)])),
    };
    return ensureMessaging().sendEachForMulticast(message);
};

export const sendToTopic = async ({ topic, title, body, data = {} }) => {
    return ensureMessaging().send({
        topic,
        notification: { title, body },
        data: Object.fromEntries(Object.entries(data).map(([key, value]) => [key, String(value)])),
    });
};
