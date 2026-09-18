import { translateService, translateServices, CATEGORY_DICTIONARY } from '../services/translationService.js';

export const getRequestLanguage = (req) => {
    const supported = ['en', 'hi', 'ta', 'te', 'kn', 'bn', 'mr', 'gu', 'pa'];
    const qLang = req.query?.lang;
    if (qLang && supported.includes(qLang.toLowerCase())) return qLang.toLowerCase();

    const userLang = req.user?.preferredLanguage;
    if (userLang && supported.includes(userLang.toLowerCase())) return userLang.toLowerCase();

    const header = req.headers?.['accept-language'];
    if (header) {
        const clean = header.toLowerCase();
        for (const lang of supported) {
            if (clean.startsWith(lang) || clean.includes(lang)) return lang;
        }
    }

    return 'en';
};

export const localizeService = async (service, lang = 'en') => {
    if (!service) return service;
    return await translateService(service, lang);
};

export const localizeServices = async (services, lang = 'en') => {
    if (!Array.isArray(services)) return [];
    return await translateServices(services, lang);
};

export const localizeCategories = (categories, lang = 'en') => {
    if (!Array.isArray(categories)) return [];
    return categories.map(cat => localizeCategory(cat, lang));
};

/** Single category/skill slug → label in request language (dict, 0ms). */
export const localizeCategory = (raw, lang = 'en') => {
    if (raw == null) return raw;
    const value = String(raw).trim();
    if (!value) return value;
    if (!lang || lang === 'en') {
        // Still normalize known slugs to English display names.
        const lower = value.toLowerCase();
        return CATEGORY_DICTIONARY[lower]?.en || value;
    }
    const lower = value.toLowerCase();
    return CATEGORY_DICTIONARY[lower]?.[lang] || CATEGORY_DICTIONARY[lower]?.en || value;
};
