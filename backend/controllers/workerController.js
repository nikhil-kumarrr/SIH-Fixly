import dotenv from 'dotenv';
dotenv.config();

import mongoose from 'mongoose';
import User from '../models/User.js';
import Booking from '../models/Booking.js';
import Review from '../models/Review.js';
import Cooperative from '../models/Cooperative.js';
import redis from '../config/redis.js';
import { uploadDataUriOrUrl } from '../utils/cloudinary.js';
import { updateUserProfile } from './authController.js';
import { getPlatformSettings } from '../services/settingsService.js';
import { buildCategoryCondition } from '../utils/workerCategoryFilter.js';
import { getRequestLanguage, localizeCategory, localizeCategories } from '../utils/i18nHelper.js';

/** Attach display-localized category/skills for the request language (cache stays raw). */
const withLocalizedWorkerTrade = (worker, lang) => {
    if (!worker) return worker;
    const clone = { ...worker };
    const profile = clone.workerProfile ? { ...clone.workerProfile } : null;
    const rawCategory = profile?.category || clone.category || '';
    const rawCategories = Array.isArray(profile?.categories) && profile.categories.length
        ? profile.categories
        : (rawCategory ? [rawCategory] : []);
    const rawSkills = Array.isArray(profile?.skills) ? profile.skills : (clone.skills || []);

    clone.category = localizeCategory(rawCategory, lang);
    clone.categories = localizeCategories(rawCategories, lang);
    clone.skills = localizeCategories(rawSkills, lang);
    clone.displayCategory = clone.category;
    if (profile) {
        profile.category = clone.category;
        profile.categories = clone.categories;
        profile.skills = clone.skills;
        clone.workerProfile = profile;
    }
    return clone;
};

// Haversine formula to calculate accurate distance between two coordinates in kilometers
const calculateHaversineDistanceKm = (lat1, lon1, lat2, lon2) => {
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

// Screen 7: Get Nearby Workers with Step-by-Step Filtering:
// 1. Category Matching
// 2. Skills Matching
// 3. Busy Worker / Active Job Exclusion (Real-time pull-to-refresh sync)
// 4. 10km Area Radius & Haversine Distance Calculation
// 5. Default Top Rated Sorting (Highest rating first, tie-breaker: nearest)
export const getNearbyWorkers = async (req, res) => {
    // #swagger.tags = ['Workers']
    // #swagger.description = 'Get nearby available workers with infinite scroll / lazy loading (5 items per batch), category & skills filtering, top rating sort, and Indian currency minimum charge'
    // #swagger.parameters['lng'] = { in: 'query', description: 'User longitude (e.g. 77.3639)', required: true, type: 'number' }
    // #swagger.parameters['lat'] = { in: 'query', description: 'User latitude (e.g. 28.6280)', required: true, type: 'number' }
    // #swagger.parameters['category'] = { in: 'query', description: 'Filter by category (e.g. Plumbing)', type: 'string' }
    // #swagger.parameters['skill'] = { in: 'query', description: 'Filter by single skill (e.g. Pipe Fitting)', type: 'string' }
    // #swagger.parameters['skills'] = { in: 'query', description: 'Filter by multiple skills comma-separated (e.g. Pipe Fitting, Leak Detection)', type: 'string' }
    // #swagger.parameters['sortBy'] = { in: 'query', description: 'Sorting order: top_rated (default), nearest, jobs, price_low, price_high', type: 'string', default: 'top_rated' }
    // #swagger.parameters['radiusInKm'] = { in: 'query', description: 'Search radius in kilometers (default 10)', type: 'number', default: 10 }
    // #swagger.parameters['offset'] = { in: 'query', description: 'Infinite scroll offset (0 for first batch, 5 for next batch, etc.)', type: 'integer', default: 0 }
    // #swagger.parameters['limit'] = { in: 'query', description: 'Batch size limit from .env (default 5)', type: 'integer', default: 5 }
    // #swagger.parameters['page'] = { in: 'query', description: 'Alternative page number for scroll (1 for first batch, 2 for next, etc.)', type: 'integer', default: 1 }
    try {
        const settings = await getPlatformSettings();
        const defaultRadius = Number(settings.workerSearchRadiusKm) || 10;
        const defaultPageLimit = parseInt(process.env.DEFAULT_WORKER_PAGE_LIMIT, 10) || 5;

        const {
            lng,
            lat,
            category,
            skill,
            skills,
            sortBy = 'top_rated', // Default: Top rating workers appear first
            radiusInKm = defaultRadius,
            page = 1,
            offset,
            skip,
            limit = defaultPageLimit
        } = req.query;

        if (!lng || !lat) {
            return res.status(400).json({
                success: false,
                code: 'VALIDATION_ERROR',
                message: 'Coordinates (lng, lat) are required.'
            });
        }

        const longitude = parseFloat(lng);
        const latitude = parseFloat(lat);
        const searchRadius = parseFloat(radiusInKm) || defaultRadius;

        if (isNaN(longitude) || isNaN(latitude)) {
            return res.status(400).json({
                success: false,
                code: 'VALIDATION_ERROR',
                message: 'Invalid coordinates provided'
            });
        }

        // STEP 4 EXCLUSION: Find all workers currently engaged in an active booking
        // If a worker has status APPROVED, ACCEPTED, ARRIVED, or IN_PROGRESS, they are busy working at a customer's location
        const busyWorkerIds = await Booking.distinct('worker', {
            worker: { $ne: null },
            status: { $in: ['APPROVED', 'ACCEPTED', 'ARRIVED', 'IN_PROGRESS'] }
        });

        // Base filter: Role worker, verified, has profile setup, not currently on active job, and online
        const queryFilter = {
            role: 'worker',
            isVerified: true,
            workerProfile: { $ne: null },
            _id: { $nin: busyWorkerIds },
            'workerProfile.isOnline': { $ne: false } // only exclude if explicitly toggled offline
        };

        const andConditions = [];

        // STEP 1: Category Filter (Matches workerProfile.category, categories array, or categoryRates with alias normalization)
        if (category && category.trim()) {
            andConditions.push(buildCategoryCondition(category));
        }

        // STEP 2: Skills Filter (Matches workerProfile.skills against requested skill / skills)
        const rawSkills = skill || skills;
        if (rawSkills) {
            const skillList = Array.isArray(rawSkills)
                ? rawSkills
                : String(rawSkills).split(',').map(s => s.trim()).filter(Boolean);

            if (skillList.length > 0) {
                const skillRegexes = skillList.map(s => new RegExp(s, 'i'));
                andConditions.push({
                    'workerProfile.skills': { $in: skillRegexes }
                });
            }
        }

        if (andConditions.length > 0) {
            queryFilter.$and = andConditions;
        }

        // Fetch candidate workers from MongoDB (real-time, bypassing stale cache for pull-to-refresh accuracy)
        const workersFromDb = await User.find(queryFilter)
            .select('-password -activeDeviceId')
            .lean();

        // STEP 3: 10 km Radius & Distance Calculation using Haversine formula
        const nearbyWorkers = [];

        for (const worker of workersFromDb) {
            // Current / Latest location of worker:
            // 1. worker.location (updated when worker moves or completes a job at customer's house)
            // 2. Fallback: worker.savedAddresses[0].location (default registration address)
            const coords = (worker.location && Array.isArray(worker.location.coordinates) && worker.location.coordinates.length === 2)
                ? worker.location.coordinates
                : (worker.savedAddresses && worker.savedAddresses[0]?.location?.coordinates?.length === 2)
                    ? worker.savedAddresses[0].location.coordinates
                    : null;

            if (!coords) continue;

            const [workerLng, workerLat] = coords;
            if (isNaN(workerLng) || isNaN(workerLat)) continue;

            const distanceKm = calculateHaversineDistanceKm(latitude, longitude, workerLat, workerLng);

            // Strict 10 km (or custom radius) check
            if (distanceKm <= searchRadius) {
                const roundedDistance = parseFloat(distanceKm.toFixed(1));
                const profile = worker.workerProfile || {};
                const workerRate = profile.rate ?? profile.hourlyRate ?? 0;
                const rating = Number((profile.rating || 0.0).toFixed(1));
                const totalJobs = profile.totalJobs || 0;
                
                // Formatted Title (e.g. "Master Plumber", "Senior Electrician", or category)
                const categoryTitle = profile.category
                    ? (profile.category.toLowerCase().includes('plumb') ? 'Master Plumber' : `${profile.category} Specialist`)
                    : 'Certified Professional';

                const rawCategory = profile.category || category || 'General';
                const rawSkills = profile.skills || [];
                const lang = getRequestLanguage(req);

                nearbyWorkers.push({
                    _id: worker._id,
                    name: worker.name,
                    phone: worker.phone,
                    email: worker.email,
                    avatar: worker.avatar || profile.selfieImageUrl || 'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=200&auto=format&fit=crop&q=80',
                    rating,
                    category: localizeCategory(rawCategory, lang),
                    categories: localizeCategories(
                        Array.isArray(profile.categories) && profile.categories.length
                            ? profile.categories
                            : [rawCategory],
                        lang
                    ),
                    title: profile.bio ? categoryTitle : localizeCategory(rawCategory, lang),
                    skills: localizeCategories(rawSkills, lang),
                    totalJobs,
                    rate: workerRate, // Database schema rate
                    minimumCharge: workerRate, // Minimum charge shown on frontend
                    rateFormatted: `₹${workerRate}`, // Indian currency without per hour
                    distanceKm: roundedDistance,
                    distanceFormatted: `${roundedDistance} km`,
                    distanceDisplay: `${roundedDistance} km`,
                    isOnline: profile.isOnline !== false,
                    isAvailable: true, // Guaranteed available since busy workers are excluded
                    location: worker.location || { type: 'Point', coordinates: [workerLng, workerLat] },
                    workerProfile: profile
                });
            }
        }

        // STEP 5: Sorting (Default: top_rated first, tie-breaker: nearest)
        if (sortBy === 'top_rated') {
            nearbyWorkers.sort((a, b) => {
                if (b.rating !== a.rating) {
                    return b.rating - a.rating;
                }
                return a.distanceKm - b.distanceKm;
            });
        } else if (sortBy === 'jobs') {
            nearbyWorkers.sort((a, b) => b.totalJobs - a.totalJobs);
        } else if (sortBy === 'price_low') {
            nearbyWorkers.sort((a, b) => a.rate - b.rate);
        } else if (sortBy === 'price_high') {
            nearbyWorkers.sort((a, b) => b.rate - a.rate);
        } else if (sortBy === 'nearest') {
            nearbyWorkers.sort((a, b) => {
                if (a.distanceKm !== b.distanceKm) {
                    return a.distanceKm - b.distanceKm;
                }
                return b.rating - a.rating;
            });
        } else {
            // Fallback default: top_rated
            nearbyWorkers.sort((a, b) => b.rating - a.rating);
        }

        const totalWorkers = nearbyWorkers.length;
        const pageLimit = Math.max(1, parseInt(limit, 10) || defaultPageLimit);

        // Infinite Scroll / Lazy Loading: Supports both offset/skip and page queries
        let startIndex = 0;
        let currentPage = 1;

        if (offset !== undefined || skip !== undefined) {
            startIndex = Math.max(0, parseInt(offset ?? skip, 10) || 0);
            currentPage = Math.floor(startIndex / pageLimit) + 1;
        } else if (page !== undefined) {
            currentPage = Math.max(1, parseInt(page, 10) || 1);
            startIndex = (currentPage - 1) * pageLimit;
        }

        const paginatedWorkers = nearbyWorkers.slice(startIndex, startIndex + pageLimit);
        const hasMore = (startIndex + pageLimit) < totalWorkers;
        const nextOffset = hasMore ? (startIndex + pageLimit) : null;
        const nextPage = hasMore ? (currentPage + 1) : null;

        // STEP 3 (b): Not Found Handling
        if (totalWorkers === 0) {
            return res.status(200).json({
                success: false,
                code: 'NO_WORKERS_FOUND',
                message: `No available professionals found within ${searchRadius} km. Please try again shortly or select a different category.`,
                count: 0,
                totalWorkers: 0,
                hasMore: false,
                nextOffset: null,
                nextPage: null,
                offset: startIndex,
                limit: pageLimit,
                searchRadiusKm: searchRadius,
                workers: []
            });
        }

        return res.status(200).json({
            success: true,
            hasMore,
            nextOffset,
            nextPage,
            offset: startIndex,
            limit: pageLimit,
            count: paginatedWorkers.length,
            totalWorkers,
            searchRadiusKm: searchRadius,
            workers: paginatedWorkers
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

// Screen 8: Worker Profile Details
export const getWorkerProfile = async (req, res) => {
    try {
        const { workerId } = req.params;
        const lang = getRequestLanguage(req);
        const cacheKey = `worker:profile:${workerId}`;

        const cachedProfile = await redis.get(cacheKey);
        if (cachedProfile) {
            const worker = JSON.parse(cachedProfile);
            // Live availability still refreshed below for cache hits.
            const activeBooking = await Booking.findOne({
                worker: workerId,
                status: { $in: ['APPROVED', 'ACCEPTED', 'ARRIVED', 'IN_PROGRESS'] }
            });
            const isAvailable = !activeBooking;
            const isBusy = !!activeBooking;
            worker.isAvailable = isAvailable;
            worker.isBusy = isBusy;
            if (worker.workerProfile) {
                worker.workerProfile.isAvailable = isAvailable;
                worker.workerProfile.isBusy = isBusy;
            }
            return res.status(200).json({
                success: true,
                source: 'cache',
                worker: withLocalizedWorkerTrade(worker, lang),
            });
        }

        const ttl = parseInt(process.env.CACHE_TTL_WORKER_PROFILE, 10) || 600;

        const worker = await User.findOne({ _id: workerId, role: 'worker' })
            .select('-password -activeDeviceId')
            .lean();

        if (!worker || !worker.workerProfile) {
            return res.status(404).json({ success: false, message: 'Worker profile not found.' });
        }

        const workerObjId = mongoose.Types.ObjectId.isValid(workerId)
            ? new mongoose.Types.ObjectId(workerId)
            : workerId;

        const [completed, cancelled, reviews, recentReviewsRaw] = await Promise.all([
            Booking.countDocuments({ worker: workerId, status: 'COMPLETED' }),
            Booking.countDocuments({ worker: workerId, status: 'CANCELLED' }),
            Review.find({ worker: workerObjId, reviewerRole: { $ne: 'worker' } }).select('rating').lean(),
            Review.find({ worker: workerObjId, reviewerRole: { $ne: 'worker' } })
                .populate('customer', 'name avatar')
                .populate('booking', 'bookingId workPhotos completionPhotos')
                .sort({ createdAt: -1 })
                .limit(5)
                .lean()
        ]);
        const total = completed + cancelled;
        const completionRate = total === 0 ? 0 : Math.round((completed / total) * 100);
        const avgRating = reviews.length
            ? reviews.reduce((s, r) => s + (r.rating || 5), 0) / reviews.length
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

        // Format recent 5 customer reviews with work photos and customer details
        const bookingIds = recentReviewsRaw.map(r => r.booking?._id || r.booking).filter(Boolean);
        const partnerReviews = bookingIds.length > 0 ? await Review.find({
            booking: { $in: bookingIds },
            reviewerRole: 'worker',
            photos: { $exists: true, $not: { $size: 0 } }
        }).select('booking photos').lean() : [];

        const partnerPhotosByBooking = {};
        for (const pr of partnerReviews) {
            partnerPhotosByBooking[String(pr.booking)] = pr.photos;
        }

        const formattedRecentReviews = recentReviewsRaw.map(r => {
            const bIdStr = String(r.booking?._id || r.booking || '');
            let workPhotos = Array.isArray(r.photos) && r.photos.length > 0 ? r.photos : [];
            if (workPhotos.length === 0) {
                if (partnerPhotosByBooking[bIdStr]?.length) {
                    workPhotos = partnerPhotosByBooking[bIdStr];
                } else if (r.booking?.workPhotos?.length) {
                    workPhotos = r.booking.workPhotos;
                } else if (r.booking?.completionPhotos?.length) {
                    workPhotos = r.booking.completionPhotos;
                }
            }
            const customerName = r.customer?.name || 'Customer';
            const customerAvatar = r.customer?.avatar || null;
            return {
                _id: r._id,
                id: r._id,
                bookingId: r.booking?.bookingId || (typeof r.booking === 'string' ? r.booking : null),
                reviewerName: customerName,
                customerName,
                avatar: customerAvatar,
                avatarUrl: customerAvatar,
                rating: Number(r.rating) || 5,
                comment: r.feedback || '',
                feedback: r.feedback || '',
                description: r.feedback || '',
                badgesGiven: r.badgesGiven || [],
                photos: workPhotos.slice(0, 3),
                workPhotos: workPhotos.slice(0, 3),
                createdAt: r.createdAt
            };
        });

        worker.reviews = formattedRecentReviews;
        worker.recentReviews = formattedRecentReviews;
        worker.reviewCount = reviews.length;
        worker.totalReviews = reviews.length;

        // Ensure recentWorkPhotos is populated
        if (!worker.workerProfile.recentWorkPhotos || worker.workerProfile.recentWorkPhotos.length === 0) {
            const reviewsWithPhotos = await Review.find({
                worker: workerObjId,
                photos: { $exists: true, $not: { $size: 0 } }
            }).sort({ createdAt: -1 }).limit(10).lean();

            const collectedPhotos = [];
            for (const rwp of reviewsWithPhotos) {
                if (Array.isArray(rwp.photos)) {
                    for (const p of rwp.photos) {
                        if (p && !collectedPhotos.includes(p)) collectedPhotos.push(p);
                    }
                }
            }
            worker.workerProfile.recentWorkPhotos = collectedPhotos.slice(0, 15);
        }
        worker.recentWorkPhotos = worker.workerProfile.recentWorkPhotos || [];

        if (worker.workerProfile) {
            const settings = await getPlatformSettings();
            const platformRadius = Number(settings.workerSearchRadiusKm) || 15;
            if (!worker.workerProfile.serviceRadiusKm) {
                worker.workerProfile.serviceRadiusKm = platformRadius;
            }
            const workerRate = worker.workerProfile.rate ?? worker.workerProfile.hourlyRate ?? 0;
            worker.workerProfile.rate = workerRate;
            worker.workerProfile.hourlyRate = workerRate;
            worker.workerProfile.minimumCharge = workerRate;
            worker.workerProfile.rateFormatted = `₹${workerRate}`;
            worker.workerProfile.reviews = formattedRecentReviews;
            worker.workerProfile.reviewCount = reviews.length;
            worker.workerProfile.totalReviews = reviews.length;
        }

        await redis.set(cacheKey, JSON.stringify(worker), 'EX', ttl);

        // Check real-time active booking status (never stale, bypasses cache)
        const activeBooking = await Booking.findOne({
            worker: workerId,
            status: { $in: ['APPROVED', 'ACCEPTED', 'ARRIVED', 'IN_PROGRESS'] }
        });
        const isAvailable = !activeBooking;
        const isBusy = !!activeBooking;

        worker.isAvailable = isAvailable;
        worker.isBusy = isBusy;
        if (worker.workerProfile) {
            worker.workerProfile.isAvailable = isAvailable;
            worker.workerProfile.isBusy = isBusy;
        }

        return res.status(200).json({
            success: true,
            source: 'db',
            worker: withLocalizedWorkerTrade(worker, lang),
        });

    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

export const setupWorkerProfile = async (req, res) => {
    // If multipart files or complex structure, delegate to updateUserProfile
    if (req.files || (req.file) || (req.body && (req.body.avatar || req.body.aadhaarFrontPhoto || req.body.panFrontPhoto))) {
        return updateUserProfile(req, res);
    }
    return updateUserProfile(req, res);
};

export const getMyAvailability = async (req, res) => {
    try {
        if (req.user.role !== 'worker') {
            return res.status(403).json({ success: false, code: 'FORBIDDEN', message: 'Worker role required' });
        }
        const user = await User.findById(req.user.id).select('workerProfile');
        const p = user?.workerProfile || {};
        return res.status(200).json({
            success: true,
            data: {
                isOnline: Boolean(p.isOnline),
                lastActiveAt: p.lastActiveAt || null,
                serviceRadiusKm: p.serviceRadiusKm || 10,
                availabilitySchedule: p.availabilitySchedule || { days: [], startTime: '09:00', endTime: '18:00' },
            },
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

export const patchMyAvailability = async (req, res) => {
    try {
        if (req.user.role !== 'worker') {
            return res.status(403).json({ success: false, code: 'FORBIDDEN', message: 'Worker role required' });
        }
        const user = await User.findById(req.user.id);
        if (!user.workerProfile) user.workerProfile = {};
        if (typeof req.body.isOnline === 'boolean') {
            user.workerProfile.isOnline = req.body.isOnline;
            user.workerProfile.lastActiveAt = new Date();
        }
        if (req.body.serviceRadiusKm != null) {
            user.workerProfile.serviceRadiusKm = Number(req.body.serviceRadiusKm);
        }
        await user.save();
        const io = req.app.get('io');
        if (io) {
            io.emit('worker:availability-changed', {
                workerId: String(user._id),
                isOnline: user.workerProfile.isOnline,
            });
        }
        return res.status(200).json({
            success: true,
            data: {
                isOnline: user.workerProfile.isOnline,
                lastActiveAt: user.workerProfile.lastActiveAt,
                serviceRadiusKm: user.workerProfile.serviceRadiusKm,
            },
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

export const putAvailabilitySchedule = async (req, res) => {
    try {
        if (req.user.role !== 'worker') {
            return res.status(403).json({ success: false, code: 'FORBIDDEN', message: 'Worker role required' });
        }
        const { days, startTime, endTime } = req.body || {};
        const user = await User.findById(req.user.id);
        if (!user.workerProfile) user.workerProfile = {};
        user.workerProfile.availabilitySchedule = {
            days: Array.isArray(days) ? days : [],
            startTime: startTime || '09:00',
            endTime: endTime || '18:00',
        };
        await user.save();
        return res.status(200).json({ success: true, data: user.workerProfile.availabilitySchedule });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

export const computeReliability = async (workerId) => {
    const [completed, cancelled, reviews] = await Promise.all([
        Booking.countDocuments({ worker: workerId, status: 'COMPLETED' }),
        Booking.countDocuments({ worker: workerId, status: 'CANCELLED' }),
        Review.find({ worker: workerId }).select('rating'),
    ]);
    const total = completed + cancelled;
    const completionRate = total === 0 ? 0 : Math.round((completed / total) * 100);
    const avgRating = reviews.length
        ? reviews.reduce((s, r) => s + r.rating, 0) / reviews.length
        : 0;
    const customerFeedback = Math.round((avgRating / 5) * 100);
    const cancellationRate = total === 0 ? 100 : Math.round((1 - cancelled / total) * 100);
    const score = Math.round(
        (completionRate * 0.4) + (customerFeedback * 0.35) + (cancellationRate * 0.25),
    );
    return {
        score,
        onTimeArrival: completionRate,
        completionRate,
        customerFeedback,
        cancellationRate,
        responseTime: completionRate,
        rating: Number(avgRating.toFixed(1)),
        completedJobs: completed,
    };
};

export const getWorkerReliability = async (req, res) => {
    try {
        const reliability = await computeReliability(req.params.workerId);
        return res.status(200).json({ success: true, reliability, data: reliability });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

export const getCategoryWageFloor = (category, floor) => {
    if (!floor) return 300;
    const cat = (category || '').toString().toLowerCase().trim();
    return floor[cat] || floor.default || 300;
};

export const getWorkerRates = async (req, res) => {
    try {
        if (req.user.role !== 'worker') {
            return res.status(403).json({ success: false, code: 'FORBIDDEN', message: 'Worker role required' });
        }
        const user = await User.findById(req.user.id).select('federation workerProfile');
        if (!user) return res.status(404).json({ success: false, message: 'User not found' });

        let federation = null;
        if (user.federation) {
            federation = await Cooperative.findById(user.federation);
        }
        if (!federation) {
            federation = await Cooperative.findOne({ active: true });
        }
        if (!federation) {
            federation = await Cooperative.create({});
        }

        const floor = federation.minimumWageFloor?.toObject ? federation.minimumWageFloor.toObject() : (federation.minimumWageFloor || {});

        const profile = user.workerProfile || {};
        let categories = [];
        if (Array.isArray(profile.categories) && profile.categories.length > 0) {
            categories = profile.categories;
        } else if (profile.category) {
            categories = [profile.category];
        } else if (Array.isArray(profile.skills) && profile.skills.length > 0) {
            categories = profile.skills;
        } else {
            categories = ['Plumbing'];
        }

        const existingRates = Array.isArray(profile.categoryRates) ? profile.categoryRates : [];
        const rateMap = {};
        for (const r of existingRates) {
            if (r && r.category) {
                rateMap[r.category.toLowerCase().trim()] = r.rate;
            }
        }

        const resolvedCategories = categories.map(cat => {
            const catKey = cat.toLowerCase().trim();
            const minFloor = getCategoryWageFloor(cat, floor);
            const userRate = rateMap[catKey] ?? profile.hourlyRate ?? profile.rate ?? minFloor;
            return {
                category: cat,
                rate: Math.max(Number(userRate) || minFloor, minFloor),
                minimumFloor: minFloor,
            };
        });

        return res.status(200).json({
            success: true,
            data: {
                categories: resolvedCategories,
                federation: {
                    _id: federation._id,
                    name: federation.name,
                    federationName: federation.federationName,
                    registrationNumber: federation.registrationNumber,
                    fairWagePolicy: federation.fairWagePolicy,
                    minimumWageFloor: floor,
                }
            }
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

export const updateWorkerRates = async (req, res) => {
    try {
        if (req.user.role !== 'worker') {
            return res.status(403).json({ success: false, code: 'FORBIDDEN', message: 'Worker role required' });
        }
        
        const { categoryRates } = req.body;
        if (!categoryRates) {
            return res.status(400).json({ success: false, message: 'categoryRates required' });
        }
        
        const user = await User.findById(req.user.id);
        if (!user) return res.status(404).json({ success: false, message: 'User not found' });
        
        let federation = null;
        if (user.federation) {
            federation = await Cooperative.findById(user.federation);
        }
        if (!federation) {
            federation = await Cooperative.findOne({ active: true });
        }
        if (!federation) {
            federation = await Cooperative.create({});
        }

        const floor = federation.minimumWageFloor?.toObject ? federation.minimumWageFloor.toObject() : (federation.minimumWageFloor || {});

        // Normalize rates from Array or Object
        let rateEntries = [];
        if (Array.isArray(categoryRates)) {
            rateEntries = categoryRates.map(item => ({
                category: (item.category || item.name || '').toString().trim(),
                rate: Number(item.rate ?? 0)
            })).filter(item => item.category);
        } else if (typeof categoryRates === 'object') {
            rateEntries = Object.entries(categoryRates).map(([cat, val]) => ({
                category: cat.trim(),
                rate: Number(val ?? 0)
            })).filter(item => item.category);
        }

        if (rateEntries.length === 0) {
            return res.status(400).json({ success: false, message: 'No valid category rates provided' });
        }

        // Validate each category against federation minimum wage floor
        for (const entry of rateEntries) {
            const minRate = getCategoryWageFloor(entry.category, floor);
            if (entry.rate < minRate) {
                return res.status(400).json({ 
                    success: false, 
                    code: 'BELOW_WAGE_FLOOR', 
                    message: `Rate for ${entry.category} cannot be below the federation minimum wage floor of ₹${minRate}` 
                });
            }
        }
        
        if (!user.workerProfile) user.workerProfile = {};

        // Merge into existing categoryRates array
        const existingRates = Array.isArray(user.workerProfile.categoryRates) ? user.workerProfile.categoryRates : [];
        const rateMap = new Map();
        for (const r of existingRates) {
            if (r && r.category) rateMap.set(r.category.toLowerCase().trim(), { category: r.category, rate: r.rate });
        }
        for (const r of rateEntries) {
            rateMap.set(r.category.toLowerCase().trim(), { category: r.category, rate: r.rate });
        }
        const updatedArray = Array.from(rateMap.values());

        user.workerProfile.categoryRates = updatedArray;
        if (rateEntries.length > 0) {
            user.workerProfile.hourlyRate = rateEntries[0].rate;
            user.workerProfile.rate = rateEntries[0].rate;
        }
        await user.save();
        
        return res.status(200).json({ 
            success: true, 
            categoryRates: user.workerProfile.categoryRates,
            federation: {
                _id: federation._id,
                name: federation.name,
                federationName: federation.federationName,
                minimumWageFloor: floor,
            }
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};
