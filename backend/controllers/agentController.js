import { processFixlyAgentMessage } from '../agent/index.js';
import { fail, ok } from '../utils/http.js';
import { aiLogger } from '../utils/aiLogger.js';
import { normalizeAppLanguage } from '../utils/aiLocales.js';
import { createGeminiLiveEphemeralToken, LIVE_MODEL } from '../utils/geminiLiveToken.js';
import { resolveAppIntents } from '../agent/services/appIntentService.js';

export const chatWithFlexiAgent = async (req, res) => {
    console.log('chatWithFlexiAgent called with body:', req.body);
    // #swagger.tags = ['AI Agent']
    // #swagger.description = 'Interact with Fixly Conversational AI voice/text booking assistant'
    try {
        const { message, conversationState, coordinates, addressLine, language, lang } = req.body;
        if (!message) {
            return fail(res, 400, 'VALIDATION_ERROR', 'Message is required');
        }

        const userId = req.user?.id || req.headers['x-user-id'] || 'guest_user';
        const normalizedLanguage = normalizeAppLanguage(
            language || lang || req.user?.preferredLanguage || conversationState?.language || 'en',
        );

        aiLogger.logTurnStart({
            userId,
            message,
            language: normalizedLanguage,
            coordinates,
            addressLine,
            conversationState,
        });

        const appIntent = resolveAppIntents(message, { language: normalizedLanguage });

        // App-only (theme/nav/pay UI) — skip booking graph for low latency.
        if (appIntent.isAppOnly) {
            const responsePayload = {
                success: true,
                reply: appIntent.replyHint || 'Done.',
                state: { ...(conversationState || {}), language: normalizedLanguage },
                action: 'APP_ACTION',
                appActions: appIntent.actions,
                data: { step: null, category: null },
                booking: null,
                bookings: null,
                workers: null,
                estimate: null,
                policy: null,
                suggestedReplies: [],
                meta: {
                    brain: 'app-intent',
                    language: normalizedLanguage,
                },
            };
            aiLogger.logTurnEnd({
                action: 'APP_ACTION',
                reply: responsePayload.reply,
                state: responsePayload.state,
            });
            return ok(res, responsePayload);
        }

        const io = req.app.get('io');
        const result = await processFixlyAgentMessage({
            userId,
            message,
            conversationState: conversationState || {},
            coordinates,
            addressLine,
            explicitLanguage: normalizedLanguage,
            io,
        });

        const responsePayload = {
            success: true,
            reply: result.reply,
            state: result.state,
            action: result.action,
            appActions: appIntent.actions,
            data: {
                workers: result.workers || null,
                booking: result.booking || null,
                bookings: result.bookings || null,
                estimate: result.estimate || null,
                policy: result.policy || null,
                step: result.state?.step || null,
                category: result.state?.category || null,
            },
            booking: result.booking || null,
            bookings: result.bookings || null,
            workers: result.workers || null,
            estimate: result.estimate || null,
            policy: result.policy || null,
            suggestedReplies: result.suggestedReplies || [],
            meta: {
                brain: 'gemini-flash',
                chat: process.env.GROQ_MODEL || 'openai/gpt-oss-120b',
                language: normalizedLanguage,
            },
        };

        aiLogger.logTurnEnd({
            action: result.action,
            reply: result.reply,
            state: result.state,
            booking: result.booking,
            suggestedReplies: result.suggestedReplies,
        });

        return ok(res, responsePayload);
    } catch (error) {
        aiLogger.logTurnEnd({
            action: 'ERROR',
            reply: 'Internal Server Error',
            state: {},
            error: error.message,
        });
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

/** Mint short-lived Gemini Live token for device WebSocket (hybrid audio path). */
export const mintLiveToken = async (req, res) => {
    console.log('mintLiveToken called with body:', req.body);
    try {
        const language = normalizeAppLanguage(
            req.body?.language || req.user?.preferredLanguage || 'en',
        );
        const tokenPayload = await createGeminiLiveEphemeralToken({ language });
        return ok(res, {
            success: true,
            ...tokenPayload,
            language,
            liveModel: LIVE_MODEL,
        });
    } catch (error) {
        return fail(res, 500, 'LIVE_TOKEN_ERROR', error.message);
    }
};

/**
 * Live tool bridge: Gemini Live function-calling hits this so Flash brain
 * can run booking tools without loading the Live model.
 */
export const liveToolBridge = async (req, res) => {
    console.log('liveToolBridge called with body:', req.body);
    try {
        const { utterance, conversationState, coordinates, addressLine, language, tool } = req.body || {};
        if (!utterance || !String(utterance).trim()) {
            return fail(res, 400, 'VALIDATION_ERROR', 'utterance is required');
        }

        const userId = req.user?.id || req.headers['x-user-id'] || 'guest_user';
        const normalizedLanguage = normalizeAppLanguage(
            language || conversationState?.language || req.user?.preferredLanguage || 'en',
        );
        const text = String(utterance).trim();
        const appIntent = resolveAppIntents(text, { language: normalizedLanguage });
        const toolName = String(tool || '').toLowerCase();

        // App-tool or app-only utterance — skip booking graph.
        if (toolName === 'call_fixly_app' || appIntent.isAppOnly) {
            const hasActions = Array.isArray(appIntent.actions) && appIntent.actions.length > 0;
            const fallbackReply = normalizedLanguage === 'hi'
                ? 'समझ नहीं पाया कि कौन सा स्क्रीन खोलना है। प्रोफ़ाइल या बुकिंग्स कहकर देखें।'
                : 'I could not map that to a screen. Try saying open profile or open bookings.';
            return ok(res, {
                success: true,
                reply: appIntent.replyHint || (hasActions
                    ? (normalizedLanguage === 'hi' ? 'हो गया।' : 'Done.')
                    : fallbackReply),
                state: { ...(conversationState || {}), language: normalizedLanguage },
                action: 'APP_ACTION',
                appActions: appIntent.actions,
                booking: null,
                bookings: null,
                workers: null,
                estimate: null,
                policy: null,
                suggestedReplies: [],
                speakHint: appIntent.replyHint || (hasActions ? null : fallbackReply),
                language: normalizedLanguage,
            });
        }

        const io = req.app.get('io');

        const result = await processFixlyAgentMessage({
            userId,
            message: text,
            conversationState: conversationState || {},
            coordinates,
            addressLine,
            explicitLanguage: normalizedLanguage,
            io,
        });

        return ok(res, {
            success: true,
            reply: result.reply,
            state: result.state,
            action: result.action,
            appActions: appIntent.actions,
            booking: result.booking || null,
            bookings: result.bookings || null,
            workers: result.workers || null,
            estimate: result.estimate || null,
            policy: result.policy || null,
            suggestedReplies: result.suggestedReplies || [],
            speakHint: result.reply,
            language: normalizedLanguage,
        });
    } catch (error) {
        return fail(res, 500, 'LIVE_TOOL_ERROR', error.message);
    }
};
