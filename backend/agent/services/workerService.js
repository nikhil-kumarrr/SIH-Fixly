import User from "../../models/User.js";
import Booking from "../../models/Booking.js";
import Service from "../../models/Service.js";
import redis from "../../config/redis.js";
import { getPlatformSettings } from "../../services/settingsService.js";

const CATEGORIES_CACHE_KEY = 'app:services:categories';
const CATEGORIES_TTL = 86400; // 24 hours

/**
 * Fetch all active categories directly from Redis (24-hour cache).
 * Queries MongoDB only once on initial cache miss and caches for 24h.
 */
export const getActiveDBCategories = async () => {
    // 1. Ultra-fast Redis Retrieval (<1ms)
    try {
        const cached = await redis.get(CATEGORIES_CACHE_KEY);
        if (cached) {
            const parsed = JSON.parse(cached);
            let categories = [];
            if (Array.isArray(parsed)) {
                categories = parsed;
            } else if (parsed && typeof parsed === 'object') {
                categories = Object.keys(parsed);
            }
            if (categories.length > 0) {
                return categories;
            }
        }
    } catch (redisErr) {
        console.warn("[WorkerService] Redis cache read error for categories:", redisErr.message);
    }

    // 2. Cache miss: Fetch from MongoDB once, and cache in Redis for 24 hours (86400s)
    try {
        const services = await Service.find({ isActive: true }).lean();
        const grouped = services.reduce((acc, s) => {
            const cat = s.category;
            acc[cat] = acc[cat] || [];
            acc[cat].push(s);
            return acc;
        }, {});

        // Save in Redis with 24 hours TTL
        await redis.set(CATEGORIES_CACHE_KEY, JSON.stringify(grouped), 'EX', CATEGORIES_TTL);
        return Object.keys(grouped);
    } catch (e) {
        console.warn("[WorkerService] Error fetching categories from DB:", e.message);
    }

    return ["Plumbing", "Electrical", "Cleaning", "Carpentry", "AC Repair", "Painting"];
};

export const CATEGORY_MAP = {
    Electrical: [
        "electrical", "electrician", "electricity", "electric", "bijli", "switch", "wire", "wiring",
        "fan", "fuse", "mcb", "light", "lights", "power", "short circuit", "spark", "sparking",
        "socket", "plug", "bulb", "meter", "inverter", "current", "batti", "board", "tube", "tubelight",
        "बिजली", "इलेक्ट्रीशियन", "तार", "पंखा", "स्विच", "शॉर्ट सर्किट", "बत्ती", "करंट"
    ],
    Plumbing: [
        "plumbing", "plumber", "nal", "leak", "leaking", "leakage", "pipe", "pipes", "tap", "taps",
        "water", "paani", "drainage", "sewer", "sink", "flush", "toilet", "tank", "tanki", "motor",
        "motor repair", "choke", "overflow", "geyser", "basin", "प्लंबर", "नल", "पानी", "पाइप", "लीक",
        "टोंटी", "ड्रेनेज", "टंकी", "गीजर"
    ],
    Cleaning: [
        "cleaning", "cleaner", "safai", "sofa", "dust", "deep cleaning", "house cleaning", "bathroom cleaning",
        "kitchen cleaning", "vacuum", "sanitize", "mop", "झाड़ू", "सफाई", "क्लीनर", "धुलाई", "गहरी सफाई"
    ],
    Carpentry: [
        "carpentry", "carpenter", "wood", "wooden", "furniture", "door", "doors", "window", "bed", "table",
        "chair", "lock", "cabinet", "almirah", "hinge", "दरवाजा", "कारपेंटर", "लकड़ी", "फर्नीचर", "ताला", "अलमारी"
    ],
    Appliance: [
        "appliance", "ac", "air conditioner", "cooler", "fridge", "refrigerator", "washing machine",
        "microwave", "oven", "tv", "television", "ro", "water purifier", "chimney", "heater",
        "एसी", "कूलर", "फ्रिज", "अप्लायंस", "वॉशिंग मशीन", "आरो", "चिमनी"
    ],
    Painting: [
        "painting", "painter", "paint", "putty", "wall", "whitewash", "distemper", "color", "colour",
        "texture", "पेंटर", "पेंटिंग", "रंगाई", "पुट्टी", "सफेदी"
    ],
    Gardening: [
        "gardening", "gardener", "mali", "plants", "lawn", "grass", "pots", "tree", "garden",
        "माली", "पौधे", "बगीचा", "घास", "गमले"
    ]
};

/** Resolve LLM/canonical label (e.g. Electrical) to search terms including DB keys (electrician). */
export const getCategorySearchTerms = (category) => {
    if (!category) return [];
    if (CATEGORY_MAP[category]) {
        return [category.toLowerCase(), ...CATEGORY_MAP[category].map((w) => w.toLowerCase())];
    }
    const byKey = Object.keys(CATEGORY_MAP).find((k) => k.toLowerCase() === category.toLowerCase());
    if (byKey) {
        return [byKey.toLowerCase(), ...CATEGORY_MAP[byKey].map((w) => w.toLowerCase())];
    }
    const byWord = Object.entries(CATEGORY_MAP).find(([, words]) =>
        words.some((w) => w.toLowerCase() === category.toLowerCase())
    );
    if (byWord) {
        const [canonical, words] = byWord;
        return [canonical.toLowerCase(), ...words.map((w) => w.toLowerCase())];
    }
    return [category.toLowerCase()];
};

/**
 * Validate requested category against the live Database Service catalog.
 * Maps AI labels (Electrical) → DB keys (electrician).
 */
export const validateCategoryAgainstDB = async (categoryName) => {
    const activeCats = await getActiveDBCategories();
    if (!categoryName) {
        return { isValid: false, matchedCategory: null, availableCategories: activeCats };
    }

    const catLower = categoryName.toLowerCase().trim();

    // 1. Exact or case-insensitive match on DB key
    for (const c of activeCats) {
        if (c.toLowerCase() === catLower) {
            return { isValid: true, matchedCategory: c, availableCategories: activeCats };
        }
    }

    // 2. Alias via CATEGORY_MAP (Electrical ↔ electrician, Plumbing ↔ plumbing, …)
    const terms = getCategorySearchTerms(categoryName);
    for (const c of activeCats) {
        const cL = c.toLowerCase();
        if (terms.some((t) => t.length >= 3 && (cL === t || cL.includes(t) || t.includes(cL)))) {
            return { isValid: true, matchedCategory: c, availableCategories: activeCats };
        }
    }

    // 3. Appliance ↔ AC-style DB keys
    if (catLower === "appliance") {
        const found = activeCats.find(
            (c) => c.toLowerCase().includes("ac") || c.toLowerCase().includes("appliance")
        );
        if (found) return { isValid: true, matchedCategory: found, availableCategories: activeCats };
    }

    // 4. Loose substring fallback
    for (const c of activeCats) {
        if (c.toLowerCase().includes(catLower) || catLower.includes(c.toLowerCase())) {
            return { isValid: true, matchedCategory: c, availableCategories: activeCats };
        }
    }

    return { isValid: false, matchedCategory: null, availableCategories: activeCats };
};

/** Canonical compare — "electrician" ≡ "Electrical" ≡ "bijli". */
export const sameCategory = (a, b) => {
    if (!a || !b) return false;
    const al = String(a).toLowerCase().trim();
    const bl = String(b).toLowerCase().trim();
    if (al === bl) return true;
    const termsA = new Set(getCategorySearchTerms(a));
    return getCategorySearchTerms(b).some((t) => t.length >= 3 && termsA.has(t));
};

/**
 * Fast keyword category detector as local backup / fast path
 */
export const detectCategoryFromKeywords = (text = "") => {
    const lower = text.toLowerCase();
    for (const [cat, words] of Object.entries(CATEGORY_MAP)) {
        for (const w of words) {
            if (w.length <= 3) {
                const regex = new RegExp(`(^|[^a-z0-9\u0900-\u097F])${w}([^a-z0-9\u0900-\u097F]|$)`, 'i');
                if (regex.test(lower)) return cat;
            } else {
                if (lower.includes(w)) return cat;
            }
        }
    }
    return null;
};

/**
 * Ensures all verified workers in DB are marked online so backend testing and console chat work smoothly
 */
export const ensureTestWorkersOnline = async () => {
    try {
        await User.updateMany(
            { role: 'worker', isVerified: true },
            { $set: { 'workerProfile.isOnline': true } }
        );
    } catch (err) {
        console.warn("[WorkerService] Could not set workers online:", err.message);
    }
};

// Haversine formula to calculate accurate distance between two coordinates in kilometers
export const calculateHaversineDistanceKm = (lat1, lon1, lat2, lon2) => {
    const R = 6371; // Earth's radius in kilometers
    const dLat = (lat2 - lat1) * (Math.PI / 180);
    const dLon = (lon2 - lon1) * (Math.PI / 180);
    const a =
        Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(lat1 * (Math.PI / 180)) * Math.cos(lat2 * (Math.PI / 180)) *
        Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
};

/**
 * Fetch available, verified workers for a category who are not currently busy on active jobs
 * and are within the dynamic search radius (from Admin Platform Settings) of the customer's coordinates.
 */
export const getAvailableWorkers = async ({ category, coordinates = null, limit = 5, radiusInKm = null }) => {
    try {
        await ensureTestWorkersOnline();

        // Dynamically resolve worker search radius from Admin Platform Settings if not explicitly provided
        let effectiveRadius = radiusInKm;
        if (!effectiveRadius || isNaN(effectiveRadius)) {
            try {
                const settings = await getPlatformSettings();
                effectiveRadius = Number(settings?.workerSearchRadiusKm) || Number(settings?.serviceRadiusKm) || 15;
            } catch (_) {
                effectiveRadius = 15;
            }
        }

        const query = {
            role: 'worker',
            isVerified: true,
            'workerProfile.isOnline': true
        };

        if (category) {
            const queryWords = getCategorySearchTerms(category);
            const regexes = queryWords.slice(0, 12).map(w => new RegExp(w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i'));
            query.$or = [
                { 'workerProfile.category': { $in: regexes } },
                { 'workerProfile.categories': { $in: regexes } },
                { 'workerProfile.skills': { $in: regexes } }
            ];
        }

        // Exclude busy workers who are currently on an active booking
        const busyWorkers = await Booking.distinct('worker', {
            status: { $in: ['APPROVED', 'ACCEPTED', 'ARRIVED', 'IN_PROGRESS'] },
            worker: { $ne: null }
        });

        if (busyWorkers && busyWorkers.length > 0) {
            query._id = { $nin: busyWorkers.filter(Boolean) };
        }

        let workers = await User.find(query)
            .select('name avatar phone rating workerProfile address savedAddresses location')
            .lean();

        // Fallback: If 0 online but verified workers exist for category, check verified workers
        if (workers.length === 0 && category) {
            const fallbackQuery = {
                role: 'worker',
                isVerified: true
            };
            if (busyWorkers && busyWorkers.length > 0) {
                fallbackQuery._id = { $nin: busyWorkers.filter(Boolean) };
            }
            const queryWords = getCategorySearchTerms(category);
            const regexes = queryWords.slice(0, 12).map(w => new RegExp(w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i'));
            fallbackQuery.$or = [
                { 'workerProfile.category': { $in: regexes } },
                { 'workerProfile.categories': { $in: regexes } },
                { 'workerProfile.skills': { $in: regexes } }
            ];
            workers = await User.find(fallbackQuery)
                .select('name avatar phone rating workerProfile address savedAddresses location')
                .lean();
        }

        // Parse customer coordinates [longitude, latitude]
        let custLng = null;
        let custLat = null;
        if (Array.isArray(coordinates) && coordinates.length === 2) {
            custLng = Number(coordinates[0]);
            custLat = Number(coordinates[1]);
        } else if (coordinates && typeof coordinates === 'object') {
            custLng = Number(coordinates.lng ?? coordinates.longitude);
            custLat = Number(coordinates.lat ?? coordinates.latitude);
        }

        const hasValidCoords = !isNaN(custLng) && !isNaN(custLat) && custLng !== null && custLat !== null;

        // Map and filter by dynamic search radius from admin settings
        const mappedWorkers = [];
        for (const w of workers) {
            const wCoords = (w.location && Array.isArray(w.location.coordinates) && w.location.coordinates.length === 2)
                ? w.location.coordinates
                : (w.savedAddresses && w.savedAddresses[0]?.location?.coordinates?.length === 2)
                    ? w.savedAddresses[0].location.coordinates
                    : null;

            // Worker's own service radius takes precedence if smaller, or use platform effectiveRadius
            const workerMaxRadius = Number(w.workerProfile?.serviceRadiusKm) || effectiveRadius;
            const allowedRadius = Math.min(effectiveRadius, workerMaxRadius);

            let distanceKm = 1.5; // fallback if no coords available
            if (hasValidCoords && wCoords) {
                const wLng = Number(wCoords[0]);
                const wLat = Number(wCoords[1]);
                if (!isNaN(wLng) && !isNaN(wLat)) {
                    distanceKm = calculateHaversineDistanceKm(custLat, custLng, wLat, wLng);
                    // Strict radius check: worker must be within allowed dynamic radius
                    if (distanceKm > allowedRadius) {
                        continue; // Skip worker outside dynamic radius
                    }
                }
            }

            mappedWorkers.push({
                _id: String(w._id),
                name: w.name || 'Fixly Cooperative Worker',
                avatar: w.avatar || w.workerProfile?.selfieImageUrl || null,
                rating: w.workerProfile?.rating !== undefined ? Number(w.workerProfile.rating) : 0.0,
                ratingCount: w.workerProfile?.totalJobs || 0,
                category: w.workerProfile?.category || category,
                hourlyRate: w.workerProfile?.rate || w.workerProfile?.hourlyRate || 250,
                experienceYears: w.workerProfile?.experienceYears || 4,
                society: w.workerProfile?.society?.name || 'Fixly Central Cooperative',
                isOnline: true,
                distanceKm: Number(distanceKm.toFixed(1))
            });
        }

        // Sort by distance ascending (closest first), tie-breaker by rating
        mappedWorkers.sort((a, b) => {
            if (Math.abs(a.distanceKm - b.distanceKm) > 0.1) {
                return a.distanceKm - b.distanceKm;
            }
            return (b.rating || 0) - (a.rating || 0);
        });

        return mappedWorkers.slice(0, limit);
    } catch (error) {
        console.error("[WorkerService] Error fetching available workers:", error);
        return [];
    }
};

/**
 * Match worker by ID or Name from user message
 */
export const matchWorkerChoice = (text = "", workers = []) => {
    if (!text || !workers || workers.length === 0) return null;
    const lower = text.toLowerCase().trim();

    // Check Auto / Nearest
    if (["auto", "auto-assign", "auto assign", "koi bhi", "any", "anyone", "closest", "nearest", "kisi ko bhi", "koi bhi chalega", "स्वतः", "कोई भी"].some(w => lower.includes(w))) {
        return { isAuto: true, worker: workers[0] || null };
    }

    // Match by ID
    const idMatch = text.match(/[0-9a-fA-F]{24}/);
    if (idMatch) {
        const found = workers.find(w => String(w._id) === idMatch[0]);
        if (found) return { isAuto: false, worker: found };
    }

    // Match by number: "first worker", "1st worker", "number 1", "pehla"
    if (lower.includes("pehla") || lower.includes("first") || lower.includes("1st") || lower.includes("number 1") || lower.includes("no 1")) {
        return { isAuto: false, worker: workers[0] };
    }
    if (lower.includes("dusra") || lower.includes("second") || lower.includes("2nd") || lower.includes("number 2") || lower.includes("no 2")) {
        if (workers.length > 1) return { isAuto: false, worker: workers[1] };
    }
    if (lower.includes("teesra") || lower.includes("third") || lower.includes("3rd") || lower.includes("number 3") || lower.includes("no 3")) {
        if (workers.length > 2) return { isAuto: false, worker: workers[2] };
    }

    // Match by Name
    for (const w of workers) {
        if (w.name) {
            const firstName = w.name.split(" ")[0].toLowerCase();
            if (lower.includes(w.name.toLowerCase()) || (firstName.length >= 3 && lower.includes(firstName))) {
                return { isAuto: false, worker: w };
            }
        }
    }

    return null;
};

export default {
    CATEGORY_MAP,
    getCategorySearchTerms,
    validateCategoryAgainstDB,
    detectCategoryFromKeywords,
    sameCategory,
    ensureTestWorkersOnline,
    getAvailableWorkers,
    matchWorkerChoice
};
