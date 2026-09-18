import dotenv from "dotenv";
dotenv.config();
import { GoogleGenerativeAI } from "@google/generative-ai";
import Groq from "groq-sdk";

const geminiKey = process.env.GEMINI_API_KEY || process.env.GOOGLE_API_KEY || "";
const groqKey = process.env.GROQ_API_KEY || "";

const geminiModelName = process.env.GEMINI_MODEL || "gemini-2.5-flash";
const groqModelName = process.env.GROQ_MODEL || "openai/gpt-oss-120b";

const genAI = geminiKey ? new GoogleGenerativeAI(geminiKey) : null;
const groqClient = groqKey ? new Groq({ apiKey: groqKey }) : null;

export const isGeminiAvailable = () => Boolean(geminiKey && geminiKey.length > 5);
export const isGroqAvailable = () => Boolean(groqKey && groqKey.length > 5);

async function invokeGemini(prompt, options = {}) {
    if (!genAI || !isGeminiAvailable()) return null;
    const model = genAI.getGenerativeModel({
        model: geminiModelName,
        generationConfig: {
            temperature: options.temperature !== undefined ? options.temperature : 0.1,
        },
    });
    const timeoutPromise = new Promise((_, reject) =>
        setTimeout(() => reject(new Error(`Timeout on Gemini ${geminiModelName}`)), 8000),
    );
    const result = await Promise.race([model.generateContent(prompt), timeoutPromise]);
    return {
        content: result.response.text(),
        model: geminiModelName,
        provider: "gemini",
    };
}

async function invokeGroq(prompt, options = {}) {
    if (!groqClient || !isGroqAvailable()) return null;
    const chatCompletion = await groqClient.chat.completions.create({
        messages: [
            { role: "user", content: typeof prompt === "string" ? prompt : JSON.stringify(prompt) },
        ],
        model: groqModelName,
        temperature: options.temperature !== undefined ? options.temperature : 0.1,
    });
    const content = chatCompletion.choices[0]?.message?.content || "";
    return {
        content,
        model: groqModelName,
        provider: "groq",
    };
}

export const llm = {
    /** Brain / tools / routing — Gemini Flash first, Groq fallback. */
    invoke: async (prompt, options = {}) => {
        let lastError = null;
        try {
            const gemini = await invokeGemini(prompt, options);
            if (gemini) return gemini;
        } catch (err) {
            lastError = err;
        }
        try {
            const groq = await invokeGroq(prompt, options);
            if (groq) return groq;
        } catch (err) {
            lastError = err;
        }
        throw lastError || new Error("No LLM provider available or configured.");
    },

    /** Chat / bubble copy — Groq gpt-oss-120b first, Gemini Flash fallback. */
    chat: async (prompt, options = {}) => {
        let lastError = null;
        try {
            const groq = await invokeGroq(prompt, {
                ...options,
                temperature: options.temperature !== undefined ? options.temperature : 0.4,
            });
            if (groq) return groq;
        } catch (err) {
            lastError = err;
        }
        try {
            const gemini = await invokeGemini(prompt, options);
            if (gemini) return gemini;
        } catch (err) {
            lastError = err;
        }
        throw lastError || new Error("No LLM chat provider available.");
    },
};

export { geminiModelName, groqModelName };

export default llm;
