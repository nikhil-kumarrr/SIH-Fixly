import { graph } from "./graph/graph.js";
import { getMemory, addMemoryMessage, getSessionState, saveSessionState, clearSession } from "./config/memory.js";
import { localizeAgentOutput } from "./services/localizeService.js";

/** Client null/empty must not wipe Redis-filled slots (bookingType, workerId, …). */
const mergeConversationState = (cached = {}, client = {}) => {
    const out = { ...(cached || {}) };
    for (const [key, value] of Object.entries(client || {})) {
        if (value === null || value === undefined || value === "") continue;
        out[key] = value;
    }
    return out;
};

/**
 * Main AI Agent Message Processing Pipeline
 * Handles multi-turn state loading from Redis, LangGraph invocation, state saving, and formatted response return.
 */
export const processFixlyAgentMessage = async ({
    userId = "guest",
    message = "",
    conversationState = {},
    coordinates = null,
    addressLine = null,
    explicitLanguage = "en",
    io = null
}) => {
    const text = String(message || "").trim();
    const lang = explicitLanguage || conversationState.language || "en";
    const sessionId = userId || "guest_session";

    // 1. Restore previous session state from Redis (if not explicitly overridden)
    const cachedState = await getSessionState(sessionId);
    let activeState = {
        userId,
        coordinates,
        addressLine,
        ...mergeConversationState(cachedState || {}, conversationState || {}),
        prompt: text,
        language: explicitLanguage || conversationState.language || cachedState?.language || "en"
    };

    // 2. Invoke LangGraph Workflow
    const result = await graph.invoke(activeState);

    // 2b. Localize reply + chips into the user's app language (en/hi are native).
    try {
        const localized = await localizeAgentOutput({
            reply: result.aiResponse,
            suggestedReplies: result.suggestedReplies || [],
            lang,
        });
        result.aiResponse = localized.reply;
        result.suggestedReplies = localized.suggestedReplies;
    } catch (localizeErr) {
        console.warn("[Agent] localize skipped:", localizeErr.message);
    }

    // 3. Handle Redis Session Persistence
    if (result.action === "BOOKING_CREATED" || result.action === "SESSION_ABORTED") {
        await clearSession(sessionId);
    } else if (result.action === "RESET") {
        await clearSession(sessionId);
    } else {
        // Persist updated slot state in Redis
        const stateToSave = {
            category: result.category || null,
            bookingType: result.bookingType || null,
            isEmergency: Boolean(result.isEmergency),
            scheduledTime: result.scheduledTime || null,
            workerId: result.workerId || null,
            workerName: result.workerName || null,
            workerRate: result.workerRate || null,
            problemDescription: result.problemDescription || null,
            step: result.step || null,
            language: lang
        };
        await saveSessionState(sessionId, stateToSave);
    }

    // 4. Save conversation turns in Redis memory for low-latency history retrieval
    await addMemoryMessage(sessionId, "user", text);
    await addMemoryMessage(sessionId, "assistant", result.aiResponse);

    // 5. Return structured payload for Controller, CLI, and Mobile Frontend
    return {
        reply: result.aiResponse,
        state: {
            category: result.category || null,
            bookingType: result.bookingType || null,
            isEmergency: Boolean(result.isEmergency),
            scheduledTime: result.scheduledTime || null,
            workerId: result.workerId || null,
            workerName: result.workerName || null,
            workerRate: result.workerRate || null,
            problemDescription: result.problemDescription || null,
            step: result.step || null,
            language: lang
        },
        action: result.action,
        data: {
            workers: result.workers || null,
            booking: result.booking || null,
            bookings: result.bookings || null,
            estimate: result.estimate || null,
            policy: result.policy || null,
            step: result.step || null
        },
        workers: result.workers || null,
        booking: result.booking || null,
        bookings: result.bookings || null,
        estimate: result.estimate || null,
        policy: result.policy || null,
        suggestedReplies: result.suggestedReplies || []
    };
};

export const routeAgentMessage = processFixlyAgentMessage;
export const processFlexiAgentMessage = processFixlyAgentMessage;

export default processFixlyAgentMessage;
