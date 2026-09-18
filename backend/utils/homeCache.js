import redis from '../config/redis.js';
import Service from '../models/Service.js';
import Banner from '../models/Banner.js';
import User from '../models/User.js';
import Settings from '../models/Settings.js';
import Booking from '../models/Booking.js';
import Review from '../models/Review.js';

/**
 * Safely delete keys matching a pattern using SCAN to avoid blocking Redis
 * @param {string} pattern - e.g. 'app:services:*'
 */
export const deleteKeysByPattern = async (pattern) => {
    try {
        let cursor = '0';
        do {
            const [nextCursor, keys] = await redis.scan(cursor, 'MATCH', pattern, 'COUNT', 100);
            cursor = nextCursor;
            if (Array.isArray(keys) && keys.length > 0) {
                await redis.del(...keys);
            }
        } while (cursor !== '0');
    } catch (err) {
        console.warn(`[Redis] Failed to delete keys for pattern "${pattern}":`, err.message);
    }
};

/** 
 * Invalidate all `app:home:*` and `app:banners:*` dashboard caches across all languages.
 */
export const invalidateHomeCache = async () => {
    await deleteKeysByPattern('app:home:*');
    await deleteKeysByPattern('app:banners:*');
};

/**
 * Invalidate all service, category, and detail caches across all languages.
 */
export const invalidateServiceCache = async () => {
    await deleteKeysByPattern('app:services:*');
    await deleteKeysByPattern('service:details:*');
    await deleteKeysByPattern('app:i18n:svc:*');
    await invalidateHomeCache();
};

/**
 * Direct Push & Synchronization with Redis:
 * 1. Invalidates all stale service/category/home cache keys across all languages.
 * 2. Fetches all active services from DB and compiles grouped categories.
 * 3. Immediately pushes fresh grouped categories into Redis for:
 *    - 'app:services:categories' (generic)
 *    - 'app:services:categories:en' (default language query used by mobile app)
 * 4. Pre-caches service details if serviceDoc provided.
 * 5. Pre-warms the home screen dashboard cache ('app:home:dashboard:en').
 *
 * This guarantees the mobile app and frontend get new data instantly without
 * restarting Redis or waiting for cache expiration!
 *
 * @param {Object} [serviceDoc] - The newly created or updated service document (optional)
 */
export const syncServiceToRedis = async (serviceDoc = null) => {
    try {
        // Step 1: Invalidate all existing service, category, details & home cache keys
        await invalidateServiceCache();

        // Step 2: Fetch all currently active services from MongoDB sorted by creation time (stable sequence)
        const allServices = await Service.find({ isActive: true }).sort({ createdAt: 1, _id: 1 }).lean();

        // Step 3: Group services dynamically by category key
        const groupedCategories = allServices.reduce((acc, s) => {
            const catKey = (s.category || 'general').toString().toLowerCase().trim();
            acc[catKey] = acc[catKey] || [];
            acc[catKey].push(s);
            return acc;
        }, {});

        const categoriesTtl = parseInt(process.env.CACHE_TTL_CATEGORIES, 10) || 86400;
        const serialized = JSON.stringify(groupedCategories);

        // Step 4: Write to Redis for both generic and language-specific default keys
        await redis.set('app:services:categories', serialized, 'EX', categoriesTtl);
        await redis.set('app:services:categories:en', serialized, 'EX', categoriesTtl);

        // Step 5: If specific service provided, pre-cache its detail keys
        if (serviceDoc && (serviceDoc._id || serviceDoc.id)) {
            const svcId = String(serviceDoc._id || serviceDoc.id);
            const svcDetailsTtl = parseInt(process.env.CACHE_TTL_SERVICE_DETAILS, 10) || 1800;
            const svcObj = serviceDoc.toObject ? serviceDoc.toObject() : serviceDoc;
            const svcSerialized = JSON.stringify(svcObj);
            await redis.set(`service:details:${svcId}`, svcSerialized, 'EX', svcDetailsTtl);
            await redis.set(`service:details:${svcId}:en`, svcSerialized, 'EX', svcDetailsTtl);
        }

        // Step 6: Pre-warm home dashboard data
        const limit = parseInt(process.env.HOME_SERVICES_LIMIT, 10) || 6;
        const homeTtl = parseInt(process.env.CACHE_TTL_HOME, 10) || 3600;
        const rawCategories = await Service.distinct('category', { isActive: true });
        const rawTopServices = allServices.slice(0, limit);
        let banners = [];
        try {
            banners = await Banner.find({ isActive: true }).sort({ priority: -1, createdAt: -1 }).lean();
        } catch (_) {}

        const homePayload = {
            categories: rawCategories,
            rawCategories,
            topServices: rawTopServices,
            banners,
            featuredOffers: banners,
        };
        await redis.set('app:home:dashboard:en', JSON.stringify(homePayload), 'EX', homeTtl);

        console.log(`[Redis Cache Sync] Successfully pushed ${allServices.length} services across ${Object.keys(groupedCategories).length} categories to Redis!`);
    } catch (err) {
        console.error('[Redis Cache Sync] Error syncing services to Redis:', err.message);
        try {
            await invalidateServiceCache();
        } catch (_) {}
    }
};

/**
 * Synchronize and Pre-warm a Worker's profile and user cache in Redis.
 * - Clears stale `worker:profile:${workerId}`, `user:profile:${workerId}`, `user:email:${workerEmail}`
 * - Pre-computes reliability metrics (completionRate, ratings, cancellations, total jobs)
 * - Directly pushes the fresh, compiled worker profile into Redis key `worker:profile:${workerId}`
 * - Also updates `user:email:${workerEmail}` so auth/user lookups don't serve stale data.
 *
 * @param {string|mongoose.Types.ObjectId} workerId
 * @param {Object} [workerDoc] - Optional User document
 */
export const syncWorkerToRedis = async (workerId, workerDoc = null) => {
    try {
        if (!workerId) return;
        const idStr = String(workerId);

        // Always invalidate existing cache keys first
        await redis.del(`worker:profile:${idStr}`);
        await redis.del(`user:profile:${idStr}`);

        let worker = workerDoc;
        if (!worker || !worker.workerProfile) {
            worker = await User.findOne({ _id: idStr, role: 'worker' })
                .select('-password -activeDeviceId')
                .lean();
        } else if (worker.toObject) {
            worker = worker.toObject();
            delete worker.password;
            delete worker.activeDeviceId;
        }

        if (!worker) return;

        // Sync user email cache
        if (worker.email) {
            const emailKey = `user:email:${worker.email.toLowerCase().trim()}`;
            await redis.del(emailKey);
            const { password, activeDeviceId, ...safeUser } = worker;
            const ttl = safeUser.isVerified ? 86400 : 300;
            await redis.set(emailKey, JSON.stringify(safeUser), 'EX', ttl);
        }

        // Pre-warm worker profile if worker has profile
        if (worker.workerProfile) {
            const settings = await Settings.findOne().lean();
            const fallbackRadius = Number(settings?.workerSearchRadiusKm) || 15;
            if (!worker.workerProfile.serviceRadiusKm) {
                worker.workerProfile.serviceRadiusKm = fallbackRadius;
            }
            const workerRate = worker.workerProfile.rate ?? worker.workerProfile.hourlyRate ?? 0;
            worker.workerProfile.rate = workerRate;
            worker.workerProfile.hourlyRate = workerRate;
            worker.workerProfile.minimumCharge = workerRate;
            worker.workerProfile.rateFormatted = `₹${workerRate}`;

            const [completed, cancelled, reviews] = await Promise.all([
                Booking.countDocuments({ worker: idStr, status: 'COMPLETED' }),
                Booking.countDocuments({ worker: idStr, status: 'CANCELLED' }),
                Review.find({ worker: idStr }).select('rating'),
            ]);
            const total = completed + cancelled;
            const completionRate = total === 0 ? 0 : Math.round((completed / total) * 100);
            const avgRating = reviews.length
                ? reviews.reduce((s, r) => s + r.rating, 0) / reviews.length
                : 0;

            worker.reliability = {
                score: Math.round(
                    (completionRate * 0.4) + (Math.round((avgRating / 5) * 100) * 0.35) + ((total === 0 ? 100 : Math.round((1 - cancelled / total) * 100)) * 0.25),
                ),
                onTimeArrival: completionRate,
                completionRate,
                customerFeedback: Math.round((avgRating / 5) * 100),
                cancellationRate: total === 0 ? 100 : Math.round((1 - cancelled / total) * 100),
                responseTime: completionRate,
                rating: Number(avgRating.toFixed(1)),
                completedJobs: completed,
            };

            const ttl = parseInt(process.env.CACHE_TTL_WORKER_PROFILE, 10) || 1800;
            await redis.set(`worker:profile:${idStr}`, JSON.stringify(worker), 'EX', ttl);
            console.log(`[Redis Cache Sync] Successfully pushed worker ${idStr} profile to Redis!`);
        }
    } catch (err) {
        console.warn(`[Redis Cache Sync] Error syncing worker ${workerId} to Redis:`, err.message);
        try {
            await redis.del(`worker:profile:${String(workerId)}`);
            await redis.del(`user:profile:${String(workerId)}`);
        } catch (_) {}
    }
};

/**
 * Synchronize and Pre-warm Customer Cache in Redis.
 * Invalidates and updates `user:email:${email}` and `user:profile:${id}`
 */
export const syncCustomerToRedis = async (customerId, customerDoc = null) => {
    try {
        if (!customerId) return;
        const idStr = String(customerId);
        await redis.del(`user:profile:${idStr}`);

        let customer = customerDoc;
        if (!customer) {
            customer = await User.findById(idStr).select('-password -activeDeviceId').lean();
        } else if (customer.toObject) {
            customer = customer.toObject();
            delete customer.password;
            delete customer.activeDeviceId;
        }

        if (!customer) return;

        if (customer.email) {
            const emailKey = `user:email:${customer.email.toLowerCase().trim()}`;
            await redis.del(emailKey);
            const { password, activeDeviceId, ...safeUser } = customer;
            const ttl = safeUser.isVerified ? 86400 : 300;
            await redis.set(emailKey, JSON.stringify(safeUser), 'EX', ttl);
        }
        console.log(`[Redis Cache Sync] Successfully synced customer ${idStr} in Redis!`);
    } catch (err) {
        console.warn(`[Redis Cache Sync] Error syncing customer ${customerId} to Redis:`, err.message);
    }
};

/**
 * Synchronize Platform Governance Settings to Redis immediately.
 */
export const syncSettingsToRedis = async (settingsDoc = null) => {
    try {
        let settings = settingsDoc;
        if (!settings) {
            settings = await Settings.findOne().lean();
        } else if (settings.toObject) {
            settings = settings.toObject();
        }

        if (settings) {
            await redis.set('app:platform:settings', JSON.stringify(settings), 'EX', 3600);
            console.log(`[Redis Cache Sync] Successfully pre-warmed platform settings in Redis!`);
        } else {
            await redis.del('app:platform:settings');
        }
    } catch (err) {
        console.warn('[Redis Cache Sync] Error syncing settings to Redis:', err.message);
        try {
            await redis.del('app:platform:settings');
        } catch (_) {}
    }
};

/**
 * Synchronize Banner & Coupon changes to Redis.
 * Invalidates banner keys and pre-warms the home dashboard.
 */
export const syncBannerToRedis = async () => {
    try {
        await invalidateHomeCache();
        await syncServiceToRedis();
        console.log(`[Redis Cache Sync] Successfully refreshed banner & home screen cache in Redis!`);
    } catch (err) {
        console.warn('[Redis Cache Sync] Error syncing banners to Redis:', err.message);
    }
};
