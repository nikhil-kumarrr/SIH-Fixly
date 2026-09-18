import { llm } from "../config/llmModel.js";

/**
 * App-supported languages (mirrors frontend LocaleScope). English and Hindi
 * replies are authored natively in the graph, so only the remaining locales
 * need on-the-fly translation.
 */
const LANG_NAMES = {
    ta: "Tamil",
    te: "Telugu",
    kn: "Kannada",
    bn: "Bengali",
    mr: "Marathi",
    gu: "Gujarati",
    pa: "Punjabi (Gurmukhi script)",
};

/**
 * Translate the assistant reply + suggested-reply chips into the user's language.
 * No-ops for en/hi (already authored) and falls back to the original text on any
 * failure so a translation hiccup never breaks the booking flow.
 */
export const localizeAgentOutput = async ({ reply, suggestedReplies = [], lang = "en" }) => {
    const target = LANG_NAMES[lang];
    if (!target) return { reply, suggestedReplies };

    const safeReply = String(reply || "").trim();
    if (!safeReply) return { reply, suggestedReplies };

    const prompt = `You are a translator for the Fixly home-services assistant.
Translate the message and each suggestion into natural, fluent ${target} using its native script.
Rules: keep numbers, prices (₹), booking IDs (like #BK-...), worker names and ratings unchanged; do NOT add emojis; keep it concise and conversational.
Return ONLY valid JSON, no markdown: {"reply": string, "suggestions": string[]}.

Message: ${JSON.stringify(safeReply)}
Suggestions: ${JSON.stringify(suggestedReplies || [])}`;

    try {
        const out = await llm.chat(prompt, { temperature: 0.2 });
        const cleaned = (out.content || "").replace(/```json/gi, "").replace(/```/g, "").trim();
        const parsed = JSON.parse(cleaned);
        return {
            reply: parsed.reply && String(parsed.reply).trim() ? String(parsed.reply).trim() : reply,
            suggestedReplies:
                Array.isArray(parsed.suggestions) && parsed.suggestions.length
                    ? parsed.suggestions.map((s) => String(s))
                    : suggestedReplies,
        };
    } catch (err) {
        console.warn("[Localize] translation failed, using original:", err.message);
        return { reply, suggestedReplies };
    }
};

export default localizeAgentOutput;
