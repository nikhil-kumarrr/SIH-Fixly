import { llm } from "../config/llmModel.js";
import { FIXLY_SYSTEM_PROMPT } from "../prompts/agentPrompt.js";
import { detectCategoryFromKeywords, sameCategory } from "../services/workerService.js";

/**
 * Fast keyword detector for identity questions
 */
const isIdentityQuestion = (text = "") => {
    const lower = text.toLowerCase();
    return (
        lower.includes("who are you") ||
        lower.includes("what are you") ||
        lower.includes("who created you") ||
        lower.includes("who developed you") ||
        lower.includes("who made you") ||
        lower.includes("tum kaun ho") ||
        lower.includes("tumhe kisne banaya") ||
        lower.includes("kaun banaya") ||
        lower.includes("developer kaun")
    );
};

/**
 * Fast keyword detector for off-topic queries
 */
const isOffTopicQuery = (text = "") => {
    const lower = text.toLowerCase();
    return [
        "cricket", "ipl", "match score", "politics", "election", "modi", "rahul gandhi",
        "movie", "cinema", "bollywood", "song", "weather", "mausam", "recipe", "biryani",
        "chatgpt", "openai", "who is elon", "stock market", "bitcoin", "crypto"
    ].some(w => lower.includes(w));
};

/**
 * Fast keyword detector for status queries
 */
const isStatusQuery = (text = "") => {
    const lower = text.toLowerCase();
    if (lower.includes("confirm") || lower.includes("booking karo") || lower.includes("chahiye")) return false;
    return (
        lower.includes("status") ||
        lower.includes("track") ||
        lower.includes("kahan hai") ||
        lower.includes("meri booking") ||
        lower.includes("my booking") ||
        lower.includes("order status")
    );
};

/**
 * Fast keyword detector for cancellation
 */
const isCancelQuery = (text = "") => {
    const lower = text.toLowerCase();
    return ["cancel", "quit", "exit", "band karo", "nahi chahiye", "radd karo", "रद्द"].some(w => lower.includes(w));
};

/**
 * Fast keyword detector for reset
 */
const isResetQuery = (text = "") => {
    const lower = text.toLowerCase();
    return [
        "reset", "clear", "restart", "start over", "shuru se", "nayi booking",
        "another service", "dusri service", "koi aur service"
    ].some(w => lower.includes(w));
};

/**
 * Fast keyword detector for confirmation
 */
const isConfirmQuery = (text = "") => {
    const lower = text.toLowerCase().trim();
    // If message mentions a category or schedule keyword, it is a service request, not a confirmation
    if (detectCategoryFromKeywords(lower)) return false;
    if (lower.includes("select") || lower.includes("chuno") || /[0-9a-fA-F]{24}/.test(text)) return false;
    if (lower.includes("schedule") || lower.includes("tomorrow") || lower.includes("kal") || lower.includes("baje")) return false;

    const exactWords = ["yes", "haan", "ha", "हाँ", "thik hai", "theek hai", "ok", "proceed", "confirm", "kardo", "kar do"];
    if (exactWords.includes(lower)) return true;

    return [
        "confirm kardo", "kar do confirm", "yes confirm", "haan confirm",
        "booking confirm", "confirm booking", "haan kardo", "haan kar do", "book now"
    ].some(w => lower.includes(w));
};

/** Worker-pick / auto-assign utterance — must not reset booking slots. */
export const isWorkerSelectUtterance = (text = "") => {
    const lower = text.toLowerCase();
    return (
        lower.includes("select worker") ||
        lower.includes("select first") ||
        lower.includes("first worker") ||
        lower.includes("auto-assign") ||
        lower.includes("auto assign") ||
        lower.includes("chuno") ||
        /[0-9a-fA-F]{24}/.test(text)
    );
};

export const parseExplicitBookingType = (text = "") => {
    const lower = text.toLowerCase().trim();
    // Worker selection messages must never be read as booking-type answers.
    if (isWorkerSelectUtterance(text)) return null;

    if (["sos", "emergency", "turant", "urgent", "jaldi", "आपातकालीन", "तत्काल", "danger"].some(w => lower.includes(w))) {
        return "EMERGENCY_SOS";
    }
    // Avoid bare "time"/"date" — too greedy (false SCHEDULED).
    if (["schedule", "later", "baad me", "kal", "tomorrow", "shaam", "baje", "शेड्यूल", "बाद में", "समय"].some(w => lower.includes(w))) {
        return "SCHEDULED";
    }
    if (["standard", "normal", "regular", "सामान्य", "स्टैंडर्ड"].some(w => lower.includes(w))) {
        return "STANDARD";
    }
    return null;
};

/**
 * Router Node: LLM extracts slots; THIS code owns flow (deterministic FSM).
 * Filled slots are sticky — never wiped by LLM null / alias category labels.
 */
export const agentRouter = async (state) => {
    const text = (state.prompt || "").trim();
    const lang = state.language || "en";

    // 1. Fast path checks
    if (isCancelQuery(text)) {
        return {
            ...state,
            intent: "CANCEL",
            action: "SESSION_ABORTED"
        };
    }

    if (isResetQuery(text)) {
        return {
            ...state,
            intent: "RESET",
            action: "RESET"
        };
    }

    if (isIdentityQuestion(text)) {
        return {
            ...state,
            intent: "IDENTITY_QUERY"
        };
    }

    if (isOffTopicQuery(text)) {
        return {
            ...state,
            intent: "OFF_TOPIC"
        };
    }

    if (isStatusQuery(text)) {
        return {
            ...state,
            intent: "STATUS_QUERY"
        };
    }

    // Check confirmation intent when in confirmation step
    if (state.step === "AWAITING_CONFIRMATION" && isConfirmQuery(text)) {
        return {
            ...state,
            intent: "CONFIRMATION"
        };
    }

    // 2. LLM Intent & Slot Extraction (optional enrichment only)
    let extracted = {
        intent: "BOOKING_FLOW",
        category: null,
        bookingType: null,
        isEmergency: false,
        scheduledTime: null,
        workerSelection: null,
        problemDescription: null,
        confirmation: false,
        reply: null
    };

    try {
        const promptContext = `${FIXLY_SYSTEM_PROMPT}

Current Slot State (DO NOT clear filled slots unless user clearly changes service):
${JSON.stringify({
    category: state.category,
    bookingType: state.bookingType,
    isEmergency: state.isEmergency,
    scheduledTime: state.scheduledTime,
    step: state.step,
    workerName: state.workerName
})}

User Message: "${text}"
Target Language: ${lang}

Rules:
- If user is selecting a worker (Select worker / ID / Auto-assign), keep category+bookingType unchanged; set workerSelection.
- If bookingType already filled, only change it when user explicitly picks Emergency/Standard/Schedule.
- Return ONLY JSON.

Analyze the message and return ONLY the JSON object.`;

        const aiRes = await llm.invoke(promptContext);
        const cleaned = (aiRes.content || "").replace(/```json/gi, "").replace(/```/g, "").trim();
        const parsed = JSON.parse(cleaned);

        if (parsed.intent) extracted.intent = parsed.intent;
        if (parsed.category) extracted.category = parsed.category;
        if (parsed.bookingType) extracted.bookingType = parsed.bookingType;
        if (parsed.isEmergency !== undefined) extracted.isEmergency = Boolean(parsed.isEmergency);
        if (parsed.scheduledTime) extracted.scheduledTime = parsed.scheduledTime;
        if (parsed.workerSelection) extracted.workerSelection = parsed.workerSelection;
        if (parsed.problemDescription) extracted.problemDescription = parsed.problemDescription;
        if (parsed.confirmation !== undefined) extracted.confirmation = Boolean(parsed.confirmation);
        if (parsed.reply) extracted.reply = parsed.reply;
    } catch (err) {
        console.warn("[Router] LLM extraction fallback to rules:", err.message);
        if (isConfirmQuery(text)) {
            extracted.confirmation = true;
            if (state.step === "AWAITING_CONFIRMATION") extracted.intent = "CONFIRMATION";
        }
    }

    const selectingWorker = isWorkerSelectUtterance(text);
    const keywordCat = detectCategoryFromKeywords(text);
    const explicitType = parseExplicitBookingType(text);

    // Real category switch ONLY when user keywords name a different service.
    // LLM alias Electrical vs DB electrician must NOT count as a switch.
    const isCategorySwitched = Boolean(
        keywordCat &&
        state.category &&
        !selectingWorker &&
        !sameCategory(keywordCat, state.category)
    );

    const activeCategory = isCategorySwitched
        ? keywordCat
        : (state.category || keywordCat || extracted.category || null);

    // Sticky bookingType: never drop a filled slot on LLM noise / alias category.
    let resolvedBookingType = state.bookingType || null;
    if (isCategorySwitched) {
        resolvedBookingType = explicitType; // may be null until user picks again
    } else if (explicitType) {
        resolvedBookingType = explicitType;
    } else if (
        !resolvedBookingType &&
        extracted.bookingType &&
        state.step === "AWAITING_BOOKING_TYPE"
    ) {
        // Accept LLM bookingType only while actively asking for it — never invent on turn 1.
        resolvedBookingType = extracted.bookingType;
    }

    // Stuck-session recovery: already past booking-type step but slot missing.
    if (
        !resolvedBookingType &&
        ["AWAITING_WORKER_SELECTION", "AWAITING_CONFIRMATION", "AWAITING_SCHEDULE_TIME"].includes(state.step)
    ) {
        resolvedBookingType = "STANDARD";
    }

    const problemDescription = isCategorySwitched
        ? (extracted.problemDescription || text)
        : (
            selectingWorker
                ? (state.problemDescription || extracted.problemDescription || text)
                : (extracted.problemDescription || state.problemDescription || text)
        );

    return {
        ...state,
        intent: extracted.intent,
        category: activeCategory,
        bookingType: resolvedBookingType,
        isEmergency: resolvedBookingType === "EMERGENCY_SOS" || explicitType === "EMERGENCY_SOS",
        scheduledTime: isCategorySwitched
            ? (extracted.scheduledTime || null)
            : (extracted.scheduledTime || state.scheduledTime || null),
        workerId: isCategorySwitched ? null : state.workerId,
        workerName: isCategorySwitched ? null : state.workerName,
        workerRate: isCategorySwitched ? null : state.workerRate,
        workerSelection: selectingWorker
            ? (extracted.workerSelection || text)
            : extracted.workerSelection,
        problemDescription,
        confirmation: extracted.confirmation,
        llmReply: extracted.reply
    };
};

export default agentRouter;
