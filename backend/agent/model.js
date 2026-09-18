import dotenv from "dotenv";
dotenv.config();
import { GoogleGenerativeAI } from "@google/generative-ai";

/**
 * Direct official Google Generative AI client
 * Ultra-fast, zero-overhead client for Gemini models.
 */
const geminiKey = process.env.GEMINI_API_KEY || "dummy_key_for_unconfigured_gemini";
const modelName = process.env.GEMINI_MODEL || "gemini-2.5-flash";

const genAI = new GoogleGenerativeAI(geminiKey);

export const llm = {
    invoke: async (prompt) => {
        const model = genAI.getGenerativeModel({
            model: modelName,
            generationConfig: {
                temperature: 0.1,
            }
        });
        const timeoutPromise = new Promise((_, reject) =>
            setTimeout(() => reject(new Error(`Timeout on model ${modelName}`)), 8000)
        );
        const result = await Promise.race([model.generateContent(prompt), timeoutPromise]);
        return {
            content: result.response.text(),
            model: modelName
        };
    }
};

export const isGeminiConfigured = () => {
    return Boolean(
        process.env.GEMINI_API_KEY &&
        process.env.GEMINI_API_KEY.length > 5 &&
        process.env.GEMINI_API_KEY !== "dummy_key_for_unconfigured_gemini"
    );
};

