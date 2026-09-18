import mongoose from 'mongoose';
import Review from '../models/Review.js';
import User from '../models/User.js';
import Booking from '../models/Booking.js';
import redis from '../config/redis.js';
import { uploadMulterFiles } from '../utils/cloudinary.js';

// Screen: Rating & Review Submission (supports customer→worker and worker→customer in single unified API)
export const submitReview = async (req, res) => {
    try {
        const { bookingId: bodyBookingId, workerId: rawWorkerId, rating, comment, description, traits, reviewerRole: bodyRole } = req.body;
        const bookingId = req.params.bookingId || bodyBookingId;

        if (!bookingId) {
            return res.status(400).json({ success: false, message: 'Booking ID is required' });
        }

        // Fetch booking to reliably determine worker & customer ObjectIds
        let booking = null;
        if (mongoose.Types.ObjectId.isValid(bookingId)) {
            booking = await Booking.findById(bookingId);
        }
        if (!booking) {
            booking = await Booking.findOne({ bookingId });
        }

        if (!booking) {
            return res.status(404).json({ success: false, message: 'Booking not found' });
        }

        const isWorker = req.user?.role === 'worker' || bodyRole === 'worker' || (booking.worker && String(booking.worker) === String(req.user?.id));
        const reviewerRole = isWorker ? 'worker' : 'customer';

        let customerId = booking.customer || req.body.customerId || (reviewerRole === 'customer' ? req.user?.id : null);
        let workerId = (rawWorkerId && String(rawWorkerId).trim() !== '') ? rawWorkerId : (booking.worker || req.body.workerId || (reviewerRole === 'worker' ? req.user?.id : null));

        if (isWorker && !workerId) {
            workerId = req.user?.id || booking.worker;
        }

        if (!customerId) {
            return res.status(400).json({ success: false, message: 'Customer ID could not be identified for this booking' });
        }
        if (!workerId) {
            return res.status(400).json({ success: false, message: 'Worker ID could not be identified for this booking' });
        }

        let badgesGiven = traits;
        if (typeof traits === 'string') {
            badgesGiven = traits.split(',').map((t) => t.trim()).filter(Boolean);
        }

        let photos = [];
        if (Array.isArray(req.body.photos)) {
            photos = req.body.photos;
        } else if (Array.isArray(req.body.workPhotos)) {
            photos = req.body.workPhotos;
        } else if (Array.isArray(req.body.images)) {
            photos = req.body.images;
        } else if (typeof req.body.photos === 'string' && req.body.photos) {
            try {
                const parsed = JSON.parse(req.body.photos);
                if (Array.isArray(parsed)) photos = parsed;
                else photos = [req.body.photos];
            } catch {
                photos = [req.body.photos];
            }
        } else if (typeof req.body.workPhotos === 'string' && req.body.workPhotos) {
            try {
                const parsed = JSON.parse(req.body.workPhotos);
                if (Array.isArray(parsed)) photos = parsed;
                else photos = [req.body.workPhotos];
            } catch {
                photos = [req.body.workPhotos];
            }
        } else if (typeof req.body.photo === 'string' && req.body.photo) {
            photos = [req.body.photo];
        }

        if (req.files?.length) {
            const uploaded = await uploadMulterFiles(req.files, 'gigconnect/reviews');
            photos = [...photos, ...uploaded];
        }

        // Deduplicate and limit to up to 3 work completion photos
        photos = [...new Set(photos.filter(p => typeof p === 'string' && p.trim().length > 0))].slice(0, 3);

        // If customer review has no photos, check if booking or worker review already has photos attached
        if (photos.length === 0 && reviewerRole === 'customer') {
            if (Array.isArray(booking.workPhotos) && booking.workPhotos.length > 0) {
                photos = booking.workPhotos.slice(0, 3);
            } else if (Array.isArray(booking.completionPhotos) && booking.completionPhotos.length > 0) {
                photos = booking.completionPhotos.slice(0, 3);
            } else {
                const workerRev = await Review.findOne({ booking: booking._id, reviewerRole: 'worker' }).select('photos').lean();
                if (workerRev?.photos?.length > 0) {
                    photos = workerRev.photos.slice(0, 3);
                }
            }
        }

        const feedback = comment || description || req.body.feedback || '';
        const ratingNum = Math.min(5, Math.max(1, Number(rating) || 5));

        const review = await Review.findOneAndUpdate(
            { booking: booking._id, reviewerRole },
            {
                booking: booking._id,
                customer: customerId,
                worker: workerId,
                reviewerRole,
                rating: ratingNum,
                feedback,
                badgesGiven: badgesGiven || [],
                photos,
            },
            { new: true, returnDocument: 'after', upsert: true, setDefaultsOnInsert: true }
        );

        // When work photos are present (from worker job proof or customer):
        if (photos.length > 0) {
            // 1. Update Booking records (role-specific reviewed flag)
            const reviewedPatch = reviewerRole === 'worker'
                ? { workerReviewed: true }
                : { isReviewed: true };
            await Booking.findByIdAndUpdate(booking._id, {
                ...reviewedPatch,
                workPhotos: photos,
                completionPhotos: photos
            });

            // 2. Synchronize to partner review if partner had submitted with empty photos
            const partnerRole = reviewerRole === 'worker' ? 'customer' : 'worker';
            await Review.findOneAndUpdate(
                {
                    booking: booking._id,
                    reviewerRole: partnerRole,
                    $or: [{ photos: { $size: 0 } }, { photos: { $exists: false } }]
                },
                { photos: photos }
            );

            // 3. Accumulate work photos into worker's portfolio (recentWorkPhotos, max 15 latest)
            await User.findByIdAndUpdate(workerId, {
                $push: {
                    'workerProfile.recentWorkPhotos': {
                        $each: photos,
                        $position: 0,
                        $slice: 15
                    }
                }
            });

            try {
                await redis.del(`worker:profile:${workerId}`);
            } catch (err) {
                console.warn('Redis cache clear error:', err.message);
            }
        } else {
            await Booking.findByIdAndUpdate(
                booking._id,
                reviewerRole === 'worker'
                    ? { workerReviewed: true }
                    : { isReviewed: true },
            );
        }

        // Update worker's aggregate rating & completed jobs when customer submits review
        if (reviewerRole === 'customer') {
            const workerObjId = mongoose.Types.ObjectId.isValid(workerId)
                ? new mongoose.Types.ObjectId(workerId)
                : workerId;

            const stats = await Review.aggregate([
                { $match: { worker: workerObjId, reviewerRole: 'customer' } },
                { $group: { _id: '$worker', avgRating: { $avg: '$rating' }, totalJobs: { $sum: 1 } } }
            ]);

            if (stats.length > 0) {
                await User.findByIdAndUpdate(workerId, {
                    'workerProfile.rating': Number(stats[0].avgRating.toFixed(1)),
                    'workerProfile.totalJobs': stats[0].totalJobs
                });
            }

            try {
                await redis.del(`worker:profile:${workerId}`);
            } catch (err) {
                console.warn('Redis cache clear error:', err.message);
            }
        }

        return res.status(201).json({
            success: true,
            message: 'Review submitted successfully',
            review,
            data: review
        });
    } catch (error) {
        if (error.code === 11000) {
            return res.status(409).json({ success: false, message: 'Review already submitted for this booking' });
        }
        return res.status(500).json({ success: false, message: error.message });
    }
};

// Screen: Worker Reviews Listing with Pagination (limit=5 by default)
export const getWorkerReviews = async (req, res) => {
    try {
        const defaultLimit = parseInt(process.env.REVIEWS_PAGE_LIMIT, 10) || 5;
        const page = Math.max(1, Number(req.query.page) || 1);
        const limit = Math.min(50, Math.max(1, Number(req.query.limit) || defaultLimit));
        const workerId = req.params.workerId;

        const workerFilterId = mongoose.Types.ObjectId.isValid(workerId)
            ? new mongoose.Types.ObjectId(workerId)
            : workerId;

        const filter = {
            worker: workerFilterId,
            reviewerRole: { $ne: 'worker' } // Show reviews given by customers to this worker
        };

        const [reviewsRaw, total, allStats] = await Promise.all([
            Review.find(filter)
                .populate('customer', 'name avatar email phone')
                .populate('booking', 'bookingId workPhotos completionPhotos problemDescription')
                .sort({ createdAt: -1 })
                .skip((page - 1) * limit)
                .limit(limit)
                .lean(),
            Review.countDocuments(filter),
            Review.find(filter).select('rating').lean()
        ]);

        const avg = allStats.length ? allStats.reduce((s, r) => s + (r.rating || 5), 0) / allStats.length : 0;

        // Fetch any worker completion photos for these bookings if customer review photos is empty
        const bookingIds = reviewsRaw.map(r => r.booking?._id || r.booking).filter(Boolean);
        const partnerReviews = bookingIds.length > 0 ? await Review.find({
            booking: { $in: bookingIds },
            reviewerRole: 'worker',
            photos: { $exists: true, $not: { $size: 0 } }
        }).select('booking photos').lean() : [];

        const partnerPhotosByBooking = {};
        for (const pr of partnerReviews) {
            partnerPhotosByBooking[String(pr.booking)] = pr.photos;
        }

        // Format each review with customer name, customer avatar, rating, description/feedback, and 3 work photos
        const formattedReviews = reviewsRaw.map(r => {
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
                booking: r.booking,
                bookingId: r.booking?.bookingId || (typeof r.booking === 'string' ? r.booking : null),
                customer: r.customer,
                customerId: r.customer?._id || r.customer,
                customerName,
                reviewerName: customerName,
                avatar: customerAvatar,
                avatarUrl: customerAvatar,
                rating: Number(r.rating) || 5,
                comment: r.feedback || '',
                feedback: r.feedback || '',
                description: r.feedback || '',
                badgesGiven: r.badgesGiven || [],
                traits: r.badgesGiven || [],
                photos: workPhotos.slice(0, 3),
                workPhotos: workPhotos.slice(0, 3),
                createdAt: r.createdAt,
                updatedAt: r.updatedAt
            };
        });

        const totalPages = Math.ceil(total / limit) || 1;
        const hasMore = (page * limit) < total;
        const nextPage = hasMore ? page + 1 : null;

        return res.status(200).json({
            success: true,
            data: formattedReviews,
            reviews: formattedReviews,
            summary: {
                count: total,
                average: Number(avg.toFixed(1)),
                rating: Number(avg.toFixed(1))
            },
            pagination: {
                page,
                limit,
                total,
                totalPages,
                hasMore,
                nextPage
            },
            page,
            limit,
            total,
            totalPages,
            hasMore,
            nextPage
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

export const getBookingReview = async (req, res) => {
    try {
        const { bookingId } = req.params;
        let booking = null;
        if (mongoose.Types.ObjectId.isValid(bookingId)) {
            booking = await Booking.findById(bookingId);
        }
        if (!booking) {
            booking = await Booking.findOne({ bookingId });
        }

        const bookingObjectId = booking ? booking._id : bookingId;

        const reviews = await Review.find({ booking: bookingObjectId })
            .populate('customer', 'name avatar email phone')
            .populate('worker', 'name avatar email phone workerProfile')
            .lean();

        if (!reviews || reviews.length === 0) {
            return res.status(404).json({ success: false, code: 'NOT_FOUND', message: 'Review not found' });
        }

        const customerReview = reviews.find(r => r.reviewerRole === 'customer') || reviews[0];
        const workerReview = reviews.find(r => r.reviewerRole === 'worker');

        if ((!customerReview.photos || customerReview.photos.length === 0) && workerReview?.photos?.length) {
            customerReview.photos = workerReview.photos.slice(0, 3);
        }

        return res.status(200).json({
            success: true,
            data: customerReview,
            review: customerReview,
            customerReview,
            workerReview,
            reviews
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

