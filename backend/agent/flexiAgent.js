import { detectCategoryFromKeywords, CATEGORY_MAP, sameCategory } from "./services/workerService.js";

export { CATEGORY_MAP, sameCategory };
export const detectCategory = detectCategoryFromKeywords;

export const detectLanguage = (text = "", userPreferred = "hi") => {
    if (/[\u0900-\u097F]/.test(text)) return "hi";
    const hindiWords = ["kya", "kaise", "chahiye", "karo", "nal", "bijli", "paani", "bhai", "mujhe", "mera", "turant", "jaldi", "nahin", "nahi", "kru", "karein", "batao", "bhejo"];
    if (hindiWords.some(w => text.toLowerCase().includes(w))) return "hi";
    return userPreferred || "hi";
};

export const isBookingQuery = (text = "") => {
    const lower = text.toLowerCase().trim();
    if (["confirm", "new", "standard", "emergency", "cancel", "kardo", "chahiye", "select", "karo", "batao"].some(w => lower.includes(w) && !lower.includes("status") && !lower.includes("track"))) {
        return false;
    }
    return [
        "booking status", "track booking", "my booking", "meri booking",
        "check booking", "order status", "कहाँ है", "स्टेटस", "मेरी बुकिंग",
        "booking update", "booking details", "order details"
    ].some(phrase => lower.includes(phrase));
};
