import redis from '../config/redis.js';
import { Groq } from 'groq-sdk';
import Settings from '../models/Settings.js';

// Language names in native and English
export const SUPPORTED_LANGUAGES = {
    en: 'English',
    hi: 'Hindi',
    mr: 'Marathi',
    ta: 'Tamil',
    te: 'Telugu',
    kn: 'Kannada',
    bn: 'Bengali',
    gu: 'Gujarati',
    pa: 'Punjabi'
};

// Core categories dictionary for instant 0ms fallback matching Flutter app
export const CATEGORY_DICTIONARY = {
    electrician: {
        en: 'Electrician',
        hi: 'इलेक्ट्रीशियन',
        mr: 'इलेक्ट्रिशियन',
        ta: 'மின்சார நிபுணர்',
        te: 'ఎలక్ట్రీషియన్',
        kn: 'ಎಲೆಕ್ಟ್ರಿಷಿಯನ್',
        bn: 'ইলেকট্রিশিয়ান',
        gu: 'ઇલેક્ટ્રિશિયન',
        pa: 'ਇਲੈਕਟ੍ਰੀਸ਼ੀਅਨ'
    },
    electrical: {
        en: 'Electrician',
        hi: 'इलेक्ट्रीशियन',
        mr: 'इलेक्ट्रिशियन',
        ta: 'மின்சார நிபுணர்',
        te: 'ఎలక్ట్రీషియన్',
        kn: 'ಎಲೆಕ್ಟ್ರಿಷಿಯನ್',
        bn: 'ইলেকট্রিশিয়ান',
        gu: 'ઇલેક્ટ્રિશિયન',
        pa: 'ਇਲੈਕਟ੍ਰੀਸ਼ੀਅನ್'
    },
    plumber: {
        en: 'Plumber',
        hi: 'प्लंबर',
        mr: 'प्लंबर',
        ta: 'குழாய் பழுதுபார்ப்பவர்',
        te: 'ప్లంబర్',
        kn: 'ಪ್ಲಂಬರ್',
        bn: 'প্লাম্বার',
        gu: 'પ્લમ્બર',
        pa: 'ਪਲੰਬਰ'
    },
    plumbing: {
        en: 'Plumber',
        hi: 'प्लंबर',
        mr: 'प्लंबर',
        ta: 'குழாய் பழுதுபார்ப்பவர்',
        te: 'ప్లంబర్',
        kn: 'ಪ್ಲಂಬರ್',
        bn: 'প্লাম্বার',
        gu: 'પ્લમ્બર',
        pa: 'ਪਲੰਬਰ'
    },
    carpenter: {
        en: 'Carpenter',
        hi: 'बढ़ई',
        mr: 'सुतार',
        ta: 'தச்சர்',
        te: 'వడ్రంగి',
        kn: 'ಬಡಗಿ',
        bn: 'ছুতার',
        gu: 'સુથાર',
        pa: 'ਤਰਖਾਣ'
    },
    carpentry: {
        en: 'Carpenter',
        hi: 'बढ़ई',
        mr: 'सुतार',
        ta: 'தச்சர்',
        te: 'వడ్రంగి',
        kn: 'ಬಡಗಿ',
        bn: 'ছুতার',
        gu: 'સુથાર',
        pa: 'ਤਰਖਾਣ'
    },
    painter: {
        en: 'Painter',
        hi: 'पेंटर',
        mr: 'रंगारी',
        ta: 'வண்ணப்பூசுபவர்',
        te: 'పెయింటర్',
        kn: 'ಬಣ್ಣಗಾರ',
        bn: 'রংমিস্ত্রি',
        gu: 'કલર કામ',
        pa: 'ਪੇਂਟਰ'
    },
    painting: {
        en: 'Painter',
        hi: 'पेंटर',
        mr: 'रंगारी',
        ta: 'வண்ணப்பூசுபவர்',
        te: 'పెయింటర్',
        kn: 'ಬಣ್ಣಗಾರ',
        bn: 'রংমিস্ত্রি',
        gu: 'કલર કામ',
        pa: 'ਪੇਂਟਰ'
    },
    gardener: {
        en: 'Gardener',
        hi: 'माली',
        mr: 'माळी',
        ta: 'தோட்டக்காரர்',
        te: 'తోటమాలి',
        kn: 'ತೋಟಗಾರ',
        bn: 'মালী',
        gu: 'માળી',
        pa: 'ਮਾਲੀ'
    },
    gardening: {
        en: 'Gardener',
        hi: 'माली',
        mr: 'माळी',
        ta: 'தோட்டக்காரர்',
        te: 'తోటమాలి',
        kn: 'ತೋಟಗಾರ',
        bn: 'মালী',
        gu: 'માળી',
        pa: 'ਮਾਲੀ'
    },
    'domestic helper': {
        en: 'Domestic Helper',
        hi: 'घरेलू सहायक',
        mr: 'घरकाम मदतनीस',
        ta: 'வீட்டு உதவியாளர்',
        te: 'గృహ సహాయకుడు',
        kn: 'ಮನೆ ಕೆಲಸದ ಸಹಾಯಕ',
        bn: 'গৃহকর্মী',
        gu: 'ઘરેલું સહાયક',
        pa: 'ਘਰੇਲੂ ਸਹਾਇਕ'
    },
    'domestic_helper': {
        en: 'Domestic Helper',
        hi: 'घरेलू सहायक',
        mr: 'घरकाम मदतनीस',
        ta: 'வீட்டு உதவியாளர்',
        te: 'గృహ సహాయకుడు',
        kn: 'ಮನೆ ಕೆಲಸದ ಸಹಾಯಕ',
        bn: 'গৃহকর্মী',
        gu: 'ઘરેલું સહાયક',
        pa: 'ਘਰੇਲੂ ਸਹਾਇਕ'
    },
    'domestic help': {
        en: 'Domestic Helper',
        hi: 'घरेलू सहायक',
        mr: 'घरकाम मदतनीस',
        ta: 'வீட்டு உதவியாளர்',
        te: 'గృహ సహాయకుడు',
        kn: 'ಮನೆ ಕೆಲಸದ ಸಹಾಯಕ',
        bn: 'গৃহকর্মী',
        gu: 'ઘરેલું સહાયક',
        pa: 'ਘਰੇਲੂ ਸਹਾਇਕ'
    },
    caregiving: {
        en: 'Caregiving',
        hi: 'देखभाल',
        mr: 'देखभाल',
        ta: 'பராமரிப்பு',
        te: 'సంరక్షణ',
        kn: 'ಆರೈಕೆ',
        bn: 'পরিচর্যা',
        gu: 'સંભાળ',
        pa: 'ਦੇਖਭਾਲ'
    },
    driver: {
        en: 'Driver',
        hi: 'ड्राइवर',
        mr: 'चालक',
        ta: 'ஓட்டுநர்',
        te: 'డ్రైవర్',
        kn: 'ಚಾಲಕ',
        bn: 'চালক',
        gu: 'ડ્રાઇવર',
        pa: 'ਡਰਾਈਵਰ'
    },
    driving: {
        en: 'Driver',
        hi: 'ड्राइवर',
        mr: 'चालक',
        ta: 'ஓட்டுநர்',
        te: 'డ్రైవర్',
        kn: 'ಚಾಲಕ',
        bn: 'চালক',
        gu: 'ડ્રાઇવર',
        pa: 'ਡਰਾਈਵਰ'
    },
    technician: {
        en: 'Technician',
        hi: 'तकनीशियन',
        mr: 'तंत्रज्ञ',
        ta: 'தொழில்நுட்ப வல்லுநர்',
        te: 'టెక్నీషియన్',
        kn: 'ತಂತ್ರಜ್ಞ',
        bn: 'প্রযুক্তিবিদ',
        gu: 'ટેકનિશિયન',
        pa: 'ਤਕਨੀਸ਼ੀਅਨ'
    },
    cleaning: {
        en: 'Cleaning',
        hi: 'सफाई',
        mr: 'स्वच्छता',
        ta: 'துப்புரவு',
        te: 'శుభ్రపరచడం',
        kn: 'ಸ್ವಚ್ಛತೆ',
        bn: 'পরিষ্কারকরণ',
        gu: 'સફાઈ',
        pa: 'ਸਫ਼ਾਈ'
    },
    'ac repair': {
        en: 'AC Repair',
        hi: 'एसी मरम्मत',
        mr: 'एसी दुरुस्ती',
        ta: 'ஏசி பழுது',
        te: 'ఏసీ రిపేరు',
        kn: 'ಎಸಿ ದುರಸ್ತಿ',
        bn: 'এসি মেরামত',
        gu: 'એસી રિપેર',
        pa: 'ਏਸੀ ਰਿਪੇਅਰ'
    }
};

let groqClientInstance = null;
let currentKey = null;

async function getGroqClient() {
    let key = process.env.GROQ_API_KEY;
    try {
        const settings = await Settings.findOne({}).lean();
        if (settings?.apiKeys?.groqApiKey) {
            key = settings.apiKeys.groqApiKey;
        }
    } catch (_) {}

    if (!key) return null;

    if (!groqClientInstance || key !== currentKey) {
        groqClientInstance = new Groq({ apiKey: key });
        currentKey = key;
    }
    return groqClientInstance;
}

/**
 * Translates a single service document into the requested target language.
 * Checks Redis cache first (TTL: 30 days). If cache miss, queries Groq AI.
 */
export async function translateService(service, targetLang = 'en') {
    if (!service) return service;
    const isDoc = typeof service.toObject === 'function';
    const obj = isDoc ? service.toObject() : { ...service };

    if (!targetLang || targetLang === 'en') {
        obj.displayTitle = obj.title;
        obj.displayCategory = obj.category;
        obj.displayDescription = obj.description || '';
        obj.displayWhatsIncluded = obj.whatsIncluded || [];
        return obj;
    }

    const serviceId = String(obj._id || obj.id || '');
    const cacheKey = `app:i18n:svc:${targetLang}:${serviceId}`;

    // 1. Try Redis cache
    try {
        const cached = await redis.get(cacheKey);
        if (cached) {
            const parsed = JSON.parse(cached);
            obj.displayTitle = parsed.displayTitle || obj.title;
            obj.displayCategory = parsed.displayCategory || obj.category;
            obj.displayDescription = parsed.displayDescription || obj.description || '';
            obj.displayWhatsIncluded = parsed.displayWhatsIncluded || obj.whatsIncluded || [];
            return obj;
        }
    } catch (cacheErr) {
        console.warn('[TranslationService] Redis get error:', cacheErr.message);
    }

    // 2. Fast category dictionary match
    const catLower = (obj.category || '').toLowerCase().trim();
    const dictCategory = CATEGORY_DICTIONARY[catLower]?.[targetLang] || obj.category;

    // 3. Translate with Groq AI
    try {
        const groq = await getGroqClient();
        if (groq) {
            const langName = SUPPORTED_LANGUAGES[targetLang] || targetLang;
            const payload = {
                title: obj.title,
                category: dictCategory,
                description: obj.description || '',
                whatsIncluded: Array.isArray(obj.whatsIncluded) ? obj.whatsIncluded : []
            };

            const prompt = `Translate the fields of this home service into ${langName} (${targetLang}).
Return a JSON object with the exact same structure:
{
  "displayTitle": "translated title",
  "displayCategory": "translated category",
  "displayDescription": "translated description",
  "displayWhatsIncluded": ["translated item 1", "translated item 2"]
}
Keep brand names like Fixly as Fixly. Return ONLY valid JSON.`;

            const completion = await groq.chat.completions.create({
                messages: [
                    { role: 'system', content: prompt },
                    { role: 'user', content: JSON.stringify(payload) }
                ],
                model: 'openai/gpt-oss-120b',
                response_format: { type: 'json_object' },
                temperature: 0.1,
                max_tokens: 500
            });

            const content = completion.choices?.[0]?.message?.content;
            if (content) {
                const translated = JSON.parse(content);
                obj.displayTitle = translated.displayTitle || obj.title;
                obj.displayCategory = translated.displayCategory || dictCategory;
                obj.displayDescription = translated.displayDescription || obj.description || '';
                obj.displayWhatsIncluded = Array.isArray(translated.displayWhatsIncluded)
                    ? translated.displayWhatsIncluded
                    : obj.whatsIncluded || [];

                // Cache in Redis for 30 days
                try {
                    await redis.set(
                        cacheKey,
                        JSON.stringify({
                            displayTitle: obj.displayTitle,
                            displayCategory: obj.displayCategory,
                            displayDescription: obj.displayDescription,
                            displayWhatsIncluded: obj.displayWhatsIncluded
                        }),
                        'EX',
                        86400 * 30
                    );
                } catch (_) {}

                return obj;
            }
        }
    } catch (aiErr) {
        console.warn(`[TranslationService] Groq translation failed for ${targetLang}:`, aiErr.message);
    }

    // 4. Fallback if AI unavailable: use dictionary category and original title
    obj.displayTitle = obj.title;
    obj.displayCategory = dictCategory;
    obj.displayDescription = obj.description || '';
    obj.displayWhatsIncluded = obj.whatsIncluded || [];
    return obj;
}

/**
 * Translates an array of services concurrently.
 */
export async function translateServices(services, targetLang = 'en') {
    if (!Array.isArray(services)) return [];
    if (!targetLang || targetLang === 'en') {
        return services.map(s => {
            const isDoc = typeof s.toObject === 'function';
            const obj = isDoc ? s.toObject() : { ...s };
            obj.displayTitle = obj.title;
            obj.displayCategory = obj.category;
            obj.displayDescription = obj.description || '';
            obj.displayWhatsIncluded = obj.whatsIncluded || [];
            return obj;
        });
    }

    return await Promise.all(services.map(s => translateService(s, targetLang)));
}
