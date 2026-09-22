import dotenv from 'dotenv';
dotenv.config();

import Booking from '../models/Booking.js';
import Service from '../models/Service.js';
import User from '../models/User.js';
import redis from '../config/redis.js';
import { uploadMulterFiles } from '../utils/cloudinary.js';
import { notifyUser, notifyUsers, safeNotify } from '../services/notificationService.js';
import { findEligibleWorkerIds } from '../services/eligibleWorkers.js';
import { getPlatformSettings } from '../services/settingsService.js';
import { scheduleReminders } from '../queues/scheduledBookingQueue.js';
import { validateAndCalculateCoupon } from '../services/couponService.js';
import Review from '../models/Review.js';

/** Hydrate isReviewed / workerReviewed from Review docs (fixes legacy single-flag data). */
async function attachReviewFlags(bookings) {
    const list = Array.isArray(bookings) ? bookings.filter(Boolean) : [];
    if (list.length === 0) return bookings;
    const ids = list.map((b) => b._id).filter(Boolean);
    if (ids.length === 0) return bookings;
    const reviews = await Review.find({ booking: { $in: ids } })
        .select('booking reviewerRole')
        .lean();
    const byBooking = {};
    for (const r of reviews) {
        const key = String(r.booking);
        if (!byBooking[key]) byBooking[key] = { customer: false, worker: false };
        if (r.reviewerRole === 'worker') byBooking[key].worker = true;
        else byBooking[key].customer = true;
    }
    for (const b of list) {
        const flags = byBooking[String(b._id)];
        if (!flags) continue;
        if (flags.customer) b.isReviewed = true;
        if (flags.worker) b.workerReviewed = true;
    }
    return bookings;
}

// Real-time Coupon Code Verification for Customer Checkout
export const validateCoupon = async (req, res) => {
    // #swagger.tags = ['Bookings']
    // #swagger.description = 'Validate a promotional coupon code and calculate real-time discount amount'
    try {
        const { couponCode, amount, serviceId, category } = req.body;
        if (!couponCode) {
            return res.status(400).json({ success: false, message: 'couponCode is required' });
        }

        let resolvedCategory = category;
        if (!resolvedCategory && serviceId) {
            const service = await Service.findById(serviceId).lean();
            resolvedCategory = service?.category;
        }

        const result = await validateAndCalculateCoupon({
            couponCode,
            baseAmount: Number(amount) || 0,
            serviceCategory: resolvedCategory,
            userRole: req.user?.role || 'customer',
            userId: req.user?.id || req.user?._id,
        });

        if (!result.isValid) {
            return res.status(400).json({ success: false, message: result.message });
        }

        return res.status(200).json({
            success: true,
            message: `Coupon '${result.couponCode}' applied successfully!`,
            data: result
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

/** Apply or remove coupon on an existing booking invoice (billing / payment screen). */
export const applyCouponToBooking = async (req, res) => {
    try {
        const { bookingId } = req.params;
        const { couponCode, remove } = req.body || {};
        const wantsRemove =
            remove === true ||
            remove === 'true' ||
            couponCode === null ||
            (typeof couponCode === 'string' && !couponCode.trim());

        const booking = await Booking.findById(bookingId).populate('service', 'category name');
        if (!booking) {
            return res.status(404).json({ success: false, message: 'Booking not found' });
        }

        const customerId = String(booking.customer);
        const requesterId = String(req.user?.id || req.user?._id);
        if (customerId !== requesterId && req.user?.role !== 'admin') {
            return res.status(403).json({ success: false, message: 'Not allowed' });
        }

        if (booking.invoice?.paymentStatus === 'PAID') {
            return res.status(400).json({
                success: false,
                message: wantsRemove
                    ? 'Cannot remove coupon after payment'
                    : 'Cannot apply coupon after payment',
            });
        }

        const inv = booking.invoice || {};
        const base = Number(inv.baseServiceFee) || 0;
        const parts = Number(inv.extraPartsTotal) || 0;
        const platform = Number(inv.platformFee) || 0;
        const urgent = Number(inv.urgentFee) || 0;
        // Recompute subtotal before coupon (strip any prior coupon)
        const subtotal = base + parts + platform + urgent;

        if (wantsRemove) {
            booking.invoice = {
                ...(inv.toObject?.() || inv),
                baseServiceFee: base,
                extraPartsTotal: parts,
                platformFee: platform,
                urgentFee: urgent,
                couponCode: null,
                couponDiscount: 0,
                totalAmount: subtotal,
                paymentStatus: inv.paymentStatus || 'PENDING',
                paymentMethod: inv.paymentMethod || 'UPI',
            };
            await booking.save();

            const populated = await Booking.findById(booking._id)
                .populate('service', 'name category icon basePrice')
                .populate('customer', 'name avatar')
                .populate('worker', 'name avatar workerProfile')
                .lean();

            return res.status(200).json({
                success: true,
                message: 'Coupon removed',
                booking: populated,
            });
        }

        if (!couponCode) {
            return res.status(400).json({ success: false, message: 'couponCode is required' });
        }

        const category = booking.service?.category || null;
        const previousCode = inv.couponCode
            ? String(inv.couponCode).toUpperCase().trim()
            : null;
        const sameCode =
            previousCode &&
            previousCode === String(couponCode).toUpperCase().trim();

        const result = await validateAndCalculateCoupon({
            couponCode,
            baseAmount: subtotal,
            serviceCategory: category,
            userRole: req.user?.role || 'customer',
            userId: requesterId,
            skipUsedCheck: !!sameCode,
        });

        if (!result.isValid) {
            return res.status(400).json({ success: false, message: result.message });
        }

        booking.invoice = {
            ...inv.toObject?.() || inv,
            baseServiceFee: base,
            extraPartsTotal: parts,
            platformFee: platform,
            urgentFee: urgent,
            couponCode: result.couponCode,
            couponDiscount: result.discountAmount,
            totalAmount: result.finalAmount,
            paymentStatus: inv.paymentStatus || 'PENDING',
            paymentMethod: inv.paymentMethod || 'UPI',
        };
        await booking.save();

        // Coupon stays reserved on invoice only — burn after successful payment.
        const populated = await Booking.findById(booking._id)
            .populate('service', 'name category icon basePrice')
            .populate('customer', 'name avatar')
            .populate('worker', 'name avatar workerProfile')
            .lean();

        return res.status(200).json({
            success: true,
            message: `Coupon '${result.couponCode}' applied. Saved ₹${result.discountAmount}`,
            data: result,
            booking: populated,
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

export const removeCouponFromBooking = async (req, res) => {
    try {
        const { bookingId } = req.params;
        const booking = await Booking.findById(bookingId);
        if (!booking) {
            return res.status(404).json({ success: false, message: 'Booking not found' });
        }

        const customerId = String(booking.customer);
        const requesterId = String(req.user?.id || req.user?._id);
        if (customerId !== requesterId && req.user?.role !== 'admin') {
            return res.status(403).json({ success: false, message: 'Not allowed' });
        }

        if (booking.invoice?.paymentStatus === 'PAID') {
            return res.status(400).json({ success: false, message: 'Cannot remove coupon after payment' });
        }

        const inv = booking.invoice || {};
        const base = Number(inv.baseServiceFee) || 0;
        const parts = Number(inv.extraPartsTotal) || 0;
        const platform = Number(inv.platformFee) || 0;
        const urgent = Number(inv.urgentFee) || 0;
        const subtotal = base + parts + platform + urgent;

        booking.invoice = {
            ...(inv.toObject?.() || inv),
            baseServiceFee: base,
            extraPartsTotal: parts,
            platformFee: platform,
            urgentFee: urgent,
            couponCode: null,
            couponDiscount: 0,
            totalAmount: subtotal,
            paymentStatus: inv.paymentStatus || 'PENDING',
            paymentMethod: inv.paymentMethod || 'UPI',
        };
        await booking.save();

        const populated = await Booking.findById(booking._id)
            .populate('service', 'name category icon basePrice')
            .populate('customer', 'name avatar')
            .populate('worker', 'name avatar workerProfile')
            .lean();

        return res.status(200).json({
            success: true,
            message: 'Coupon removed',
            booking: populated,
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

// Screen 5 & 6: Estimate Price Breakdown
export const calculateEstimate = async (req, res) => {
    // #swagger.tags = ['Bookings']
    // #swagger.parameters['body'] = { in: 'body', description: 'Estimate Input', required: true, schema: { serviceId: '64f1bc000000000000000002', estimatedHours: 2, isEmergency: false, bookingType: 'STANDARD', couponCode: 'FIXLY50' } }
    try {
        const { serviceId, estimatedHours = 1, isEmergency, bookingType, couponCode } = req.body;

        const settings = await getPlatformSettings();
        const Cooperative = (await import('../models/Cooperative.js')).default;
        let federation = await Cooperative.findOne({ active: true });
        if (!federation) federation = await Cooperative.create({});

        const platformFee = settings.customerPlatformFee !== undefined && settings.customerPlatformFee !== null
            ? Number(settings.customerPlatformFee)
            : 0;
        const defaultLaborRate = Number(settings.defaultLaborRatePerHour) || 50;

        const service = await Service.findById(serviceId);
        
        let floor = federation.minimumWageFloor?.default || 300;
        if (service && service.category) {
            const cat = service.category.toLowerCase().trim();
            floor = federation.minimumWageFloor?.[cat] || federation.minimumWageFloor?.default || floor;
        }
        
        let basePrice = service ? service.basePrice : defaultLaborRate;
        if (basePrice < floor) basePrice = floor; // Enforce Federation Minimum Wage Floor

        const laborMin = basePrice * estimatedHours;
        const laborMax = laborMin + 45;
        const materialsMin = 20;
        const materialsMax = 40;

        const isSos = isEmergency === true || String(bookingType).toUpperCase() === 'EMERGENCY_SOS';
        const urgentFee = isSos
            ? (Number(settings.emergencySurchargeFixed) || Math.round(laborMin * (Number(settings.emergencySurchargePercent || 20) / 100)) || 50)
            : 0;

        let couponDiscount = 0;
        let appliedCoupon = null;
        if (couponCode) {
            const couponRes = await validateAndCalculateCoupon({
                couponCode,
                baseAmount: laborMin,
                serviceCategory: service?.category,
                userRole: req.user?.role || 'customer',
                userId: req.user?.id || req.user?._id,
            });
            if (couponRes.isValid) {
                couponDiscount = couponRes.discountAmount;
                appliedCoupon = {
                    code: couponRes.couponCode,
                    title: couponRes.title,
                    discount: couponRes.discount,
                    discountAmount: couponRes.discountAmount
                };
            }
        }

        const rawMin = laborMin + materialsMin + platformFee + urgentFee;
        const rawMax = laborMax + materialsMax + platformFee + urgentFee;

        return res.status(200).json({
            success: true,
            estimate: {
                laborEstimate: { min: laborMin, max: laborMax },
                materialsParts: { min: materialsMin, max: materialsMax },
                serviceFee: platformFee,
                urgentFee,
                couponDiscount,
                appliedCoupon,
                isEmergency: isSos,
                totalEstimate: {
                    min: Math.max(0, rawMin - couponDiscount),
                    max: Math.max(0, rawMax - couponDiscount)
                },
                baseServiceFee: laborMin,
                demandAdjustment: 0,
                estimatedTotal: Math.max(0, rawMin - couponDiscount),
                currency: 'INR',
                isEstimate: true,
            }
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

// Screen 8: Create New Booking (Customer creates booking; Initial status: PENDING)
export const createBooking = async (req, res) => {
    // #swagger.tags = ['Bookings']
    // #swagger.description = 'Customer creates a new booking request with scheduling and emergency SOS support'
    try {
        const {
            serviceId,
            workerId,
            problemDescription,
            problemPhotos,
            addressLine,
            coordinates,
            scheduledTime,
            timeSlot,
            bookingType = 'STANDARD',
            isEmergency = false,
            couponCode = null
        } = req.body;

        if (!serviceId) {
            return res.status(400).json({ success: false, message: 'serviceId is required' });
        }
        if (!addressLine) {
            return res.status(400).json({ success: false, message: 'addressLine is required' });
        }

        let coords = coordinates;
        if (typeof coords === 'string') {
            try { coords = JSON.parse(coords); } catch { /* keep */ }
        }
        if (!coords || !Array.isArray(coords) || coords.length !== 2) {
            return res.status(400).json({ success: false, message: 'Valid coordinates [longitude, latitude] are required' });
        }

        let photoUrls = [];
        if (Array.isArray(problemPhotos)) {
            photoUrls = problemPhotos.filter(Boolean);
        } else if (typeof problemPhotos === 'string' && problemPhotos.trim()) {
            try {
                const parsed = JSON.parse(problemPhotos);
                photoUrls = Array.isArray(parsed) ? parsed : [problemPhotos];
            } catch {
                photoUrls = [problemPhotos];
            }
        }

        if (req.files?.length) {
            const uploaded = await uploadMulterFiles(req.files, 'gigconnect/bookings');
            photoUrls = [...photoUrls, ...uploaded];
        }

        // Fetch service to get baseline pricing
        const service = await Service.findById(serviceId);
        let baseFee = service ? (service.basePrice || 100) : 100;

        if (workerId) {
            const activeBooking = await Booking.findOne({
                worker: workerId,
                status: { $in: ['APPROVED', 'ACCEPTED', 'ARRIVED', 'IN_PROGRESS'] }
            });
            if (activeBooking) {
                return res.status(400).json({
                    success: false,
                    code: 'WORKER_BUSY',
                    message: 'This professional is currently busy with another client. Please select another worker or wait until their current job is completed.'
                });
            }

            const worker = await User.findById(workerId).lean();
            if (worker?.workerProfile?.rate) {
                baseFee = worker.workerProfile.rate;
            }
        } else {
            // Auto-dispatch mode: verify at least 1 verified eligible worker is available in radius
            const { findEligibleWorkerIds } = await import('../services/eligibleWorkers.js');
            const eligibleWorkerIds = await findEligibleWorkerIds({
                serviceAddress: { location: { type: 'Point', coordinates: coords } }
            }, service?.category);

            if (!eligibleWorkerIds || eligibleWorkerIds.length === 0) {
                return res.status(400).json({
                    success: false,
                    code: 'NO_WORKERS_AVAILABLE',
                    message: 'No verified professionals are currently available in your area. Please try again shortly or schedule for later.'
                });
            }
        }
        
        const Cooperative = (await import('../models/Cooperative.js')).default;
        let federation = await Cooperative.findOne({ active: true });
        if (!federation) federation = await Cooperative.create({});

        let floor = federation.minimumWageFloor?.default || 300;
        if (service && service.category) {
            const cat = service.category.toLowerCase().trim();
            floor = federation.minimumWageFloor?.[cat] || federation.minimumWageFloor?.default || floor;
        }
        if (baseFee < floor) baseFee = floor;

        // Determine booking urgency and scheduling
        const isSos = isEmergency === true || String(bookingType).toUpperCase() === 'EMERGENCY_SOS';
        const finalBookingType = isSos ? 'EMERGENCY_SOS' : (scheduledTime ? 'SCHEDULED' : (bookingType || 'STANDARD'));

        let parsedScheduledTime = Date.now();
        let finalTimeSlot = timeSlot;
        if (scheduledTime) {
            const parsed = new Date(scheduledTime);
            if (isNaN(parsed.getTime())) {
                return res.status(400).json({ success: false, message: 'Invalid scheduledTime format' });
            }
            const now = new Date();
            const minTime = new Date(now.getTime() + 30 * 60000);
            const maxTime = new Date(now.getTime() + 7 * 24 * 60 * 60000);
            if (parsed < minTime) {
                return res.status(400).json({ success: false, message: 'Scheduled time must be at least 30 minutes from now' });
            }
            if (parsed > maxTime) {
                return res.status(400).json({ success: false, message: 'Scheduled time cannot be more than 7 days ahead' });
            }
            parsedScheduledTime = parsed;
            
            if (!finalTimeSlot) {
                const options = { weekday: 'short', month: 'short', day: 'numeric', hour: 'numeric', minute: 'numeric' };
                finalTimeSlot = parsed.toLocaleString('en-US', options);
            }
        }

        const settings = await getPlatformSettings();
        const platformFee = settings.customerPlatformFee !== undefined && settings.customerPlatformFee !== null
            ? Number(settings.customerPlatformFee)
            : 0;
        const urgentFee = isSos
            ? (Number(settings.emergencySurchargeFixed) || Math.round(baseFee * (Number(settings.emergencySurchargePercent || 20) / 100)) || 50)
            : 0;

        let couponDiscount = 0;
        let appliedCouponCode = null;
        if (couponCode) {
            const couponRes = await validateAndCalculateCoupon({
                couponCode,
                baseAmount: baseFee,
                serviceCategory: service?.category,
                userRole: req.user?.role || 'customer',
                userId: req.user?.id || req.user?._id,
            });
            if (couponRes.isValid) {
                couponDiscount = couponRes.discountAmount;
                appliedCouponCode = couponRes.couponCode;
                // Burn only after successful payment (verifyPayment).
            }
        }

        const totalAmount = Math.max(0, baseFee + platformFee + urgentFee - couponDiscount);

        // Create booking with initial status: 'PENDING'
        const booking = await Booking.create({
            customer: req.user.id,
            worker: workerId || null,
            service: serviceId,
            bookingType: finalBookingType,
            isEmergency: isSos,
            timeSlot: finalTimeSlot || (isSos ? 'Immediate (SOS Emergency)' : null),
            problemDescription: problemDescription || null,
            problemPhotos: photoUrls,
            serviceAddress: {
                addressLine,
                location: { type: 'Point', coordinates: coords }
            },
            scheduledTime: parsedScheduledTime,
            status: 'PENDING', // Initial phase is always PENDING
            invoice: {
                baseServiceFee: baseFee,
                extraPartsTotal: 0,
                platformFee: platformFee,
                urgentFee: urgentFee,
                couponCode: appliedCouponCode,
                couponDiscount: couponDiscount,
                totalAmount: totalAmount,
                paymentStatus: 'PENDING',
                paymentMethod: 'UPI'
            }
        });

        if (finalBookingType === 'SCHEDULED' && parsedScheduledTime > Date.now()) {
            await scheduleReminders(booking._id, new Date(parsedScheduledTime));
        }

        // Populate service & worker details for response
        const populatedBooking = await Booking.findById(booking._id)
            .populate('service', 'name category icon basePrice')
            .populate('worker', 'name avatar workerProfile rating')
            .populate('customer', 'name avatar')
            .lean();

        const io = req.app.get('io');
        if (io) {
            if (isSos) {
                // High-priority SOS broadcast to all nearby workers
                io.emit('emergency:booking_requested', {
                    bookingId: booking._id,
                    booking: populatedBooking,
                    coordinates: coords,
                    category: service?.category,
                    urgentFee
                });
            }

            if (workerId) {
                io.emit('worker:booking_requested', {
                    workerId: String(workerId),
                    booking: populatedBooking
                });
            } else {
                io.emit('booking:new_available', {
                    bookingId: booking._id,
                    coordinates: coords,
                    category: service?.category,
                    isEmergency: isSos,
                    bookingType: finalBookingType
                });
            }
        }

        safeNotify(async () => {
            const eventType = isSos ? 'EMERGENCY_BOOKING_ALERT' : 'NEW_BOOKING_AVAILABLE';
            if (workerId) {
                await notifyUser({
                    recipient: workerId,
                    eventType: isSos ? 'EMERGENCY_BOOKING_ALERT' : 'BOOKING_ASSIGNED',
                    entityId: booking._id,
                    bookingId: booking._id,
                    dedupeKey: `BOOKING_ASSIGNED:${booking._id}:${workerId}`,
                });
                return;
            }
            const allWorkers = await User.find({ role: 'worker', isVerified: true }).select('location savedAddresses').lean();
            const workerIds = [];
            const broadcastRadius = Number(settings.workerSearchRadiusKm) || 10;
            for (const w of allWorkers) {
                const wCoords = (w.location && w.location.coordinates) || (w.savedAddresses?.[0]?.location?.coordinates);
                if (wCoords && wCoords.length === 2) {
                    const dist = calculateHaversineDistanceKm(coords[1], coords[0], wCoords[1], wCoords[0]);
                    if (dist <= broadcastRadius) workerIds.push(String(w._id));
                }
            }
            await notifyUsers(workerIds, {
                eventType,
                entityId: booking._id,
                bookingId: booking._id,
                dedupeKeyFor: (id) => `${eventType}:${booking._id}:${id}`,
            });
        });

        return res.status(201).json({
            success: true,
            message: isSos
                ? 'SOS Emergency booking dispatched to all nearby verified workers!'
                : 'Booking created successfully. Waiting for worker approval.',
            booking: populatedBooking
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

// Screen 9: Get Booking Confirmation & Status
export const getBookingDetails = async (req, res) => {
    try {
        const { bookingId } = req.params;

        const booking = await Booking.findById(bookingId)
            .populate('service')
            .populate('worker', 'name avatar workerProfile')
            .populate('customer', 'name avatar')
            .lean();

        if (!booking) {
            return res.status(404).json({ success: false, message: 'Booking not found' });
        }

        await attachReviewFlags([booking]);
        return res.status(200).json({ success: true, booking });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

// Customer edits the problem details of an existing booking.
export const updateBooking = async (req, res) => {
    try {
        const { bookingId } = req.params;
        const { problemDescription, scheduledTime, serviceAddress } = req.body || {};
        const booking = await Booking.findById(bookingId);

        if (!booking) {
            return res.status(404).json({ success: false, message: 'Booking not found' });
        }
        if (String(booking.customer) !== String(req.user.id)) {
            return res.status(403).json({ success: false, message: 'You can only edit your own booking' });
        }
        if (['COMPLETED', 'CANCELLED'].includes(booking.status)) {
            return res.status(400).json({ success: false, message: 'Completed or cancelled bookings cannot be edited' });
        }

        if (problemDescription !== undefined) {
            booking.problemDescription = String(problemDescription).trim() || null;
        }
        if (scheduledTime !== undefined) {
            const parsedTime = new Date(scheduledTime);
            if (Number.isNaN(parsedTime.getTime())) {
                return res.status(400).json({ success: false, message: 'Invalid scheduledTime' });
            }
            booking.scheduledTime = parsedTime;
        }
        if (serviceAddress !== undefined) {
            if (!serviceAddress || typeof serviceAddress !== 'object') {
                return res.status(400).json({ success: false, message: 'Invalid serviceAddress' });
            }
            if (serviceAddress.addressLine !== undefined) {
                const addressLine = String(serviceAddress.addressLine).trim();
                if (!addressLine) {
                    return res.status(400).json({ success: false, message: 'addressLine cannot be empty' });
                }
                booking.serviceAddress.addressLine = addressLine;
            }
            if (Array.isArray(serviceAddress.coordinates)) {
                if (serviceAddress.coordinates.length !== 2 || serviceAddress.coordinates.some((value) => Number.isNaN(Number(value)))) {
                    return res.status(400).json({ success: false, message: 'Invalid service coordinates' });
                }
                booking.serviceAddress.location = {
                    type: 'Point',
                    coordinates: serviceAddress.coordinates.map(Number),
                };
            }
        }

        // Description-only edits must NOT unassign worker / reopen pool.
        // Only rebroadcast when an unassigned open booking changes time/address.
        const descriptionOnly =
            problemDescription !== undefined &&
            scheduledTime === undefined &&
            serviceAddress === undefined;
        const isOpenUnassigned =
            ['PENDING', 'SEARCHING'].includes(booking.status) && !booking.worker;
        const shouldRebroadcast = !descriptionOnly && isOpenUnassigned;

        if (shouldRebroadcast) {
            booking.status = 'PENDING';
            booking.declinedBy = null;
            booking.declineReason = null;
        }
        await booking.save();

        const populatedBooking = await Booking.findById(booking._id)
            .populate('service', 'name title category icon basePrice')
            .populate('worker', 'name avatar workerProfile rating')
            .populate('customer', 'name avatar')
            .lean();
        const service = populatedBooking?.service;
        const category = service?.category;
        const assignedWorkerId = populatedBooking?.worker
            ? String(populatedBooking.worker._id || populatedBooking.worker)
            : null;

        const io = req.app.get('io');
        if (io) {
            io.emit('booking:updated', { bookingId: booking._id, booking: populatedBooking });
            if (assignedWorkerId) {
                io.to(`worker_${assignedWorkerId}`).emit('booking:updated', {
                    bookingId: booking._id,
                    booking: populatedBooking,
                });
                io.to(`user_${assignedWorkerId}`).emit('booking:updated', {
                    bookingId: booking._id,
                    booking: populatedBooking,
                });
            }
        }
        if (shouldRebroadcast) {
            safeNotify(async () => {
                if (!category) return;
                const workerIds = await findEligibleWorkerIds(booking, category);
                await notifyUsers(workerIds, {
                    eventType: 'NEW_BOOKING_AVAILABLE',
                    entityId: booking._id,
                    bookingId: booking._id,
                    dedupeKeyFor: (id) => `NEW_BOOKING_AVAILABLE:${booking._id}:${id}`,
                });
            });
        } else if (assignedWorkerId) {
            safeNotify(async () => {
                await notifyUser({
                    recipient: assignedWorkerId,
                    eventType: 'BOOKING_UPDATED',
                    entityId: booking._id,
                    bookingId: booking._id,
                    dedupeKey: `BOOKING_UPDATED:${booking._id}:${assignedWorkerId}:${Date.now()}`,
                });
            });
        }

        return res.status(200).json({
            success: true,
            message: 'Booking updated successfully',
            booking: populatedBooking,
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

// Cancel Booking
export const cancelBooking = async (req, res) => {
    try {
        const { bookingId } = req.params;
        const { reason } = req.body;

        const booking = await Booking.findById(bookingId).populate('worker', 'name avatar workerProfile location savedAddresses');
        if (!booking) return res.status(404).json({ success: false, message: 'Booking not found' });

        if (['COMPLETED', 'CANCELLED'].includes(booking.status)) {
            return res.status(400).json({ success: false, message: 'Cannot cancel an already completed/cancelled booking' });
        }

        let cancellationFee = 0;
        const isCustomer = req.user.role === 'customer' || String(booking.customer) === String(req.user.id);

        if (isCustomer) {
            if (['PENDING', 'SEARCHING', 'APPROVED', 'ACCEPTED'].includes(booking.status)) {
                if (!booking.workerNavigationStartedAt) {
                    // Tier 1/2: Free if worker hasn't started navigation
                    cancellationFee = 0;
                } else {
                    // Worker started navigation
                    let originalDistance = 0;
                    let currentDistance = 0;

                    if (booking.worker && booking.serviceAddress?.location?.coordinates) {
                        const jobLng = booking.serviceAddress.location.coordinates[0];
                        const jobLat = booking.serviceAddress.location.coordinates[1];
                        const worker = booking.worker;

                        const workerHomeLng = worker.location?.coordinates?.[0] || worker.savedAddresses?.[0]?.location?.coordinates?.[0] || jobLng;
                        const workerHomeLat = worker.location?.coordinates?.[1] || worker.savedAddresses?.[0]?.location?.coordinates?.[1] || jobLat;
                        
                        originalDistance = calculateHaversineDistanceKm(workerHomeLat, workerHomeLng, jobLat, jobLng);

                        let currentLng = workerHomeLng;
                        let currentLat = workerHomeLat;
                        try {
                            const trackingData = await redis.get(`tracking:booking:${booking._id}`);
                            if (trackingData) {
                                const parsed = JSON.parse(trackingData);
                                if (parsed.lat && parsed.lng) {
                                    currentLat = parsed.lat;
                                    currentLng = parsed.lng;
                                }
                            }
                        } catch (err) {}

                        currentDistance = calculateHaversineDistanceKm(currentLat, currentLng, jobLat, jobLng);
                    }

                    const distanceCovered = originalDistance - currentDistance;
                    if (distanceCovered < (originalDistance * 0.5)) {
                        // Tier 3: Free if worker covered < 50% distance
                        cancellationFee = 0;
                    } else {
                        // Tier 4: Charged if worker covered > 50% distance
                        cancellationFee = Math.max(0, Math.round(distanceCovered * 10)); // Rs. 10/km covered
                    }
                }
            } else if (booking.status === 'ARRIVED') {
                // Tier 5: If ARRIVED but not started, customer pays base price
                cancellationFee = booking.invoice?.baseServiceFee || 100;
            }
        }

        booking.status = 'CANCELLED';
        booking.cancelledBy = req.user.id;
        booking.cancelReason = reason || 'Customer cancelled';
        booking.cancelledAt = new Date();
        booking.cancellationFee = cancellationFee;
        
        if (cancellationFee > 0 && booking.invoice) {
            booking.invoice.cancellationFee = cancellationFee;
            booking.invoice.totalAmount = (booking.invoice.totalAmount || 0) + cancellationFee;
        }

        await booking.save();

        // Purge temporary live tracking cache from Redis immediately
        try {
            await redis.del(`tracking:booking:${bookingId}`);
        } catch (_) {}

        const io = req.app.get('io');
        if (io) {
            io.to(`booking_${bookingId}`).emit('booking_status_update', {
                bookingId,
                status: 'CANCELLED'
            });
            if (booking.worker) {
                io.emit('worker:availability_changed', {
                    workerId: String(booking.worker),
                    isAvailable: true,
                    status: 'AVAILABLE'
                });
            }
        }

        safeNotify(async () => {
            const actorId = String(req.user.id);
            const customerId = String(booking.customer);
            const workerId = booking.worker ? String(booking.worker) : null;
            if (workerId && actorId !== workerId) {
                await notifyUser({
                    recipient: workerId,
                    eventType: 'BOOKING_CANCELLED',
                    entityId: booking._id,
                    bookingId: booking._id,
                    dedupeKey: `BOOKING_CANCELLED:${booking._id}:${workerId}`,
                });
            }
            if (actorId !== customerId) {
                await notifyUser({
                    recipient: customerId,
                    eventType: 'BOOKING_CANCELLED',
                    entityId: booking._id,
                    bookingId: booking._id,
                    dedupeKey: `BOOKING_CANCELLED:${booking._id}:${customerId}`,
                });
            }
        });

        return res.status(200).json({ success: true, message: 'Booking cancelled successfully', booking });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};


export const getBookingHistory = async (req, res) => {
    try {
        const userId = req.user.id;
        const role = req.user.role;

        let query = {};
        if (role === 'worker') {
            query = { worker: userId };
        } else {
            query = { customer: userId };
        }

        const bookings = await Booking.find(query)
            .populate('service')
            .populate('worker', 'name avatar workerProfile')
            .populate('customer', 'name avatar')
            .sort({ createdAt: -1 })
            .lean();

        await attachReviewFlags(bookings);

        return res.status(200).json({
            success: true,
            message: 'Booking history fetched successfully',
            bookings,
            data: bookings,
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

export const getBookingInvoice = async (req, res) => {
    try {
        const { bookingId } = req.params;

        const booking = await Booking.findById(bookingId)
            .populate('service')
            .populate('customer', 'name email avatar')
            .populate('worker', 'name avatar workerProfile')
            .lean();

        if (!booking) {
            return res.status(404).json({ success: false, message: 'Booking not found' });
        }

        return res.status(200).json({
            success: true,
            message: 'Booking invoice fetched successfully',
            invoice: booking.invoice,
            bookingDetails: {
                bookingId: booking.bookingId,
                customer: booking.customer,
                worker: booking.worker,
                service: booking.service,
                addOns: booking.addOns,
                jobStartedAt: booking.jobStartedAt,
                jobCompletedAt: booking.jobCompletedAt,
                status: booking.status
            }
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

export const getLiveTracking = async (req, res) => {
    // #swagger.tags = ['Bookings']
    // #swagger.description = 'Get live real-time GPS tracking coordinates for an active booking (Cached in Redis <1ms, 0 DB load)'
    // #swagger.parameters['bookingId'] = { in: 'path', description: 'Booking ID', required: true, type: 'string' }
    try {
        const { bookingId } = req.params;

        // 1. Ultra-fast Redis in-memory cache check (<1ms response, 0 DB load)
        try {
            const cachedTracking = await redis.get(`tracking:booking:${bookingId}`);
            if (cachedTracking) {
                const parsed = JSON.parse(cachedTracking);
                return res.status(200).json({
                    success: true,
                    source: 'redis_live',
                    message: 'Live tracking data fetched successfully',
                    location: {
                        longitude: parsed.lng,
                        latitude: parsed.lat,
                        heading: parsed.heading || 0,
                        updatedAt: parsed.timestamp || Date.now()
                    }
                });
            }
        } catch (redisErr) {
            console.warn('Redis live tracking lookup warning:', redisErr.message);
        }

        // 2. Fallback if worker has not started moving yet
        const booking = await Booking.findById(bookingId).populate('worker', 'location savedAddresses');
        if (!booking) {
            return res.status(404).json({ success: false, message: 'Booking not found' });
        }

        if (!booking.worker) {
            return res.status(400).json({ success: false, message: 'No worker assigned to this booking yet' });
        }

        const worker = booking.worker;
        const coords = (worker.location && worker.location.coordinates)
            ? worker.location.coordinates
            : (worker.savedAddresses?.[0]?.location?.coordinates);

        if (!coords || coords.length !== 2) {
            return res.status(404).json({ success: false, message: 'Worker location not available' });
        }

        return res.status(200).json({
            success: true,
            source: 'base_location',
            message: 'Live tracking data fetched successfully',
            location: {
                longitude: coords[0],
                latitude: coords[1],
                heading: 0,
                updatedAt: Date.now()
            }
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

export const triggerSosAlert = async (req, res) => {
    try {
        const { bookingId } = req.params;

        const booking = await Booking.findById(bookingId);
        if (!booking) return res.status(404).json({ success: false, message: 'Booking not found' });

        // Broadcast SOS event to the specific booking room
        const io = req.app.get('io');
        if (io) {
            io.to(`booking_${bookingId}`).emit('sos_alert', {
                bookingId,
                message: 'EMERGENCY: SOS has been triggered!',
                timestamp: Date.now()
            });
        }

        safeNotify(async () => {
            const actorId = String(req.user.id);
            const counterpart = String(booking.customer) === actorId
                ? booking.worker
                : booking.customer;
            if (counterpart) {
                await notifyUser({
                    recipient: counterpart,
                    eventType: 'SOS_ALERT',
                    entityId: booking._id,
                    bookingId: booking._id,
                    dedupeKey: `SOS_ALERT:${booking._id}:${counterpart}:${Math.floor(Date.now() / 60000)}`,
                });
            }
        });

        return res.status(200).json({
            success: true,
            message: 'SOS alert triggered successfully. Emergency contacts and socket room notified.'
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

const populateBooking = (q) => q
    .populate('service')
    .populate('worker', 'name avatar workerProfile')
    .populate('customer', 'name avatar');

const paginate = (req) => {
    const page = Math.max(1, Number(req.query.page) || 1);
    const limit = Math.min(50, Math.max(1, Number(req.query.limit) || 20));
    return { page, limit, skip: (page - 1) * limit };
};

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

export const listWorkerIncoming = async (req, res) => {
    // #swagger.tags = ['Bookings']
    // #swagger.description = 'List incoming available jobs for worker within 10km radius from current / last completed job location'
    // #swagger.parameters['lng'] = { in: 'query', description: 'Worker current longitude (optional, falls back to worker.location in DB)', type: 'number' }
    // #swagger.parameters['lat'] = { in: 'query', description: 'Worker current latitude (optional, falls back to worker.location in DB)', type: 'number' }
    // #swagger.parameters['radiusInKm'] = { in: 'query', description: 'Search radius in km (default 10)', type: 'number', default: 10 }
    // #swagger.parameters['page'] = { in: 'query', description: 'Page number', type: 'integer', default: 1 }
    // #swagger.parameters['limit'] = { in: 'query', description: 'Limit per page', type: 'integer', default: 20 }
    try {
        if (req.user.role !== 'worker') {
            return res.status(403).json({ success: false, code: 'FORBIDDEN', message: 'Worker role required' });
        }

        const workerId = req.user.id;
        const settings = await getPlatformSettings();
        const defaultRadius = Number(settings.workerSearchRadiusKm) || 10;
        const radiusInKm = parseFloat(req.query.radiusInKm) || defaultRadius;

        // Fetch worker profile to get current location & skills
        const worker = await User.findById(workerId).lean();
        if (!worker) {
            return res.status(404).json({ success: false, message: 'Worker not found' });
        }

        // Determine worker's effective current coordinates:
        // Priority 1: Query params (lat, lng from mobile GPS)
        // Priority 2: worker.location (dynamically updated from last completed job or GPS)
        // Priority 3: worker.savedAddresses[0].location (fallback default registration address)
        let workerLng = parseFloat(req.query.lng);
        let workerLat = parseFloat(req.query.lat);

        if (isNaN(workerLng) || isNaN(workerLat)) {
            const coords = (worker.location && Array.isArray(worker.location.coordinates) && worker.location.coordinates.length === 2)
                ? worker.location.coordinates
                : (worker.savedAddresses && worker.savedAddresses[0]?.location?.coordinates?.length === 2)
                    ? worker.savedAddresses[0].location.coordinates
                    : null;

            if (coords) {
                workerLng = coords[0];
                workerLat = coords[1];
            }
        } else {
            // Background sync of worker live location if provided in query
            User.findByIdAndUpdate(workerId, {
                location: { type: 'Point', coordinates: [workerLng, workerLat] }
            }).catch(() => {});
        }

        const { page, limit, skip } = paginate(req);

        // Fetch open bookings waiting for workers (open pool or assigned to this worker).
        // Exclude jobs this worker already declined (legacy PENDING+declinedBy rows too).
        const query = {
            status: { $in: ['PENDING', 'SEARCHING'] },
            $or: [{ worker: null }, { worker: workerId }],
            $nor: [{ declinedBy: workerId }],
        };
        let openBookings = await populateBooking(
            Booking.find(query).sort({ createdAt: -1 })
        ).lean();
        // Belt: string/ObjectId mismatch or stale declineReason-only rows.
        openBookings = openBookings.filter((b) => {
            if (b.declinedBy != null && String(b.declinedBy) === String(workerId)) {
                return false;
            }
            if (b.declineReason && String(b.worker) === String(workerId)) {
                return false;
            }
            return true;
        });

        // If coordinates could not be resolved at all, fallback to un-filtered pagination
        if (isNaN(workerLng) || isNaN(workerLat)) {
            const paginated = openBookings.slice(skip, skip + limit);
            return res.status(200).json({
                success: true,
                data: paginated,
                bookings: paginated,
                page,
                limit,
                total: openBookings.length,
                hasMore: (skip + limit) < openBookings.length
            });
        }

        // Filter bookings within the 10km radius from worker's current location
        const nearbyJobs = [];
        for (const b of openBookings) {
            const jobCoords = b.serviceAddress?.location?.coordinates;
            if (!jobCoords || jobCoords.length !== 2) continue;

            const [jobLng, jobLat] = jobCoords;
            if (isNaN(jobLng) || isNaN(jobLat)) continue;

            const dist = calculateHaversineDistanceKm(workerLat, workerLng, jobLat, jobLng);
            if (dist <= radiusInKm) {
                const roundedDist = parseFloat(dist.toFixed(1));
                nearbyJobs.push({
                    ...b,
                    distanceKm: roundedDist,
                    distanceFormatted: `${roundedDist} km`,
                    distanceDisplay: `${roundedDist} km`
                });
            }
        }

        // Sort by nearest distance
        nearbyJobs.sort((a, b) => a.distanceKm - b.distanceKm);

        const total = nearbyJobs.length;
        const paginatedBookings = nearbyJobs.slice(skip, skip + limit);
        const hasMore = (skip + limit) < total;

        return res.status(200).json({
            success: true,
            workerCurrentCoordinates: [workerLng, workerLat],
            searchRadiusKm: radiusInKm,
            data: paginatedBookings,
            bookings: paginatedBookings,
            page,
            limit,
            total,
            hasMore
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

export const listWorkerActive = async (req, res) => {
    try {
        if (req.user.role !== 'worker') {
            return res.status(403).json({ success: false, code: 'FORBIDDEN', message: 'Worker role required' });
        }
        const { page, limit, skip } = paginate(req);
        const query = {
            worker: req.user.id,
            status: {
                $in: [
                    'APPROVED',
                    'ACCEPTED',
                    'ARRIVED',
                    'ESTIMATION_GIVEN',
                    'READY_TO_START',
                    'IN_PROGRESS',
                    'PAYMENT_PENDING',
                ],
            },
        };
        const [bookings, total] = await Promise.all([
            populateBooking(Booking.find(query).sort({ updatedAt: -1 }).skip(skip).limit(limit)),
            Booking.countDocuments(query),
        ]);
        return res.status(200).json({ success: true, data: bookings, bookings, page, limit, total });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

export const listWorkerCompleted = async (req, res) => {
    try {
        if (req.user.role !== 'worker') {
            return res.status(403).json({ success: false, code: 'FORBIDDEN', message: 'Worker role required' });
        }
        const { page, limit, skip } = paginate(req);
        const query = { worker: req.user.id, status: 'COMPLETED' };
        const [bookings, total] = await Promise.all([
            populateBooking(Booking.find(query).sort({ jobCompletedAt: -1 }).skip(skip).limit(limit)),
            Booking.countDocuments(query),
        ]);
        return res.status(200).json({ success: true, data: bookings, bookings, page, limit, total });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

export const declineBooking = async (req, res) => {
    try {
        if (req.user.role !== 'worker') {
            return res.status(403).json({ success: false, code: 'FORBIDDEN', message: 'Worker role required' });
        }
        const allowed = new Set(['TOO_FAR', 'UNAVAILABLE', 'WRONG_SKILL', 'CUSTOMER_REQUEST', 'OTHER']);
        const reason = allowed.has(req.body?.reason) ? req.body.reason : 'OTHER';
        const booking = await Booking.findById(req.params.bookingId);
        if (!booking) return res.status(404).json({ success: false, code: 'NOT_FOUND', message: 'Booking not found' });
        if (!['PENDING', 'SEARCHING'].includes(booking.status)) {
            return res.status(400).json({ success: false, code: 'VALIDATION_ERROR', message: 'Booking cannot be declined' });
        }
        booking.declineReason = reason;
        booking.declinedBy = req.user.id;
        booking.status = 'CANCELLED';
        booking.cancelledBy = req.user.id;
        booking.cancelReason = reason;
        booking.cancelledAt = new Date();
        await booking.save();
        const io = req.app.get('io');
        if (io) {
            const payload = {
                bookingId: String(booking._id),
                canonicalBookingId: booking.bookingId,
                status: 'CANCELLED',
                reason,
                workerId: req.user.id,
                declined: true,
            };
            io.to(`booking_${booking._id}`).emit('booking:declined', payload);
            io.to(`booking_${booking._id}`).emit('booking_status_update', payload);
            const customerId = booking.customer ? String(booking.customer) : null;
            if (customerId) {
                io.to(`customer_${customerId}`).emit('booking_status_update', payload);
                io.to(`user_${customerId}`).emit('booking_status_update', payload);
            }
        }
        return res.status(200).json({
            success: true,
            data: { declined: true, cancelled: true, reason, status: 'CANCELLED' },
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};
export const workerCancelBooking = async (req, res) => {
    try {
        const { bookingId } = req.params;
        const { reason } = req.body;
        
        if (req.user.role !== 'worker') {
            return res.status(403).json({ success: false, code: 'FORBIDDEN', message: 'Worker role required' });
        }

        const booking = await Booking.findById(bookingId).populate('service');
        if (!booking) return res.status(404).json({ success: false, message: 'Booking not found' });

        if (String(booking.worker) !== String(req.user.id)) {
            return res.status(403).json({ success: false, message: 'You are not assigned to this booking' });
        }

        if (!['APPROVED', 'ACCEPTED'].includes(booking.status)) {
            return res.status(400).json({ success: false, message: 'Only APPROVED or ACCEPTED bookings can be cancelled by worker' });
        }

        booking.status = 'PENDING';
        booking.worker = null;
        booking.declinedBy = req.user.id;
        booking.declineReason = reason || 'Worker cancelled scheduled booking';
        await booking.save();

        const io = req.app.get('io');
        if (io) {
            io.to(`booking_${bookingId}`).emit('booking_status_update', {
                bookingId,
                status: 'PENDING'
            });
            
            io.emit('booking:new_available', {
                bookingId: booking._id,
                coordinates: booking.serviceAddress?.location?.coordinates,
                category: booking.service?.category,
                isEmergency: booking.isEmergency,
                bookingType: booking.bookingType
            });
        }

        safeNotify(async () => {
            await notifyUser({
                recipient: booking.customer,
                eventType: 'BOOKING_CANCELLED',
                entityId: booking._id,
                bookingId: booking._id,
                dedupeKey: `BOOKING_CANCELLED_BY_WORKER:${booking._id}:${Date.now()}`,
            });

            const workerIds = await findEligibleWorkerIds(booking, booking.service?.category);
            await notifyUsers(workerIds, {
                eventType: 'NEW_BOOKING_AVAILABLE',
                entityId: booking._id,
                bookingId: booking._id,
                dedupeKeyFor: (id) => `NEW_BOOKING_AVAILABLE:${booking._id}:${id}`,
            });
        });

        return res.status(200).json({ success: true, message: 'Booking cancelled and re-dispatched' });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

export const createEmergencyBooking = async (req, res) => {
    try {
        const { serviceId, issueDescription, offeredPrice, latitude, longitude } = req.body;
        
        if (!serviceId || !latitude || !longitude) {
            return res.status(400).json({ success: false, message: 'serviceId, latitude, and longitude are required' });
        }

        const coords = [parseFloat(longitude), parseFloat(latitude)];
        
        const settings = await getPlatformSettings();
        const defaultRate = Number(settings.defaultLaborRatePerHour) || 50;
        const service = await Service.findById(serviceId);
        let baseFee = offeredPrice || (service ? (service.basePrice || defaultRate) : defaultRate);

        const platformFee = settings.customerPlatformFee !== undefined && settings.customerPlatformFee !== null
            ? Number(settings.customerPlatformFee)
            : 0;
        
        const urgentFee = Number(settings.emergencySurchargeFixed) || Math.round(baseFee * (Number(settings.emergencySurchargePercent || 20) / 100)) || 50;
        const totalAmount = baseFee + platformFee + urgentFee;

        const booking = await Booking.create({
            customer: req.user.id,
            service: serviceId,
            bookingType: 'EMERGENCY_SOS',
            isEmergency: true,
            timeSlot: 'Immediate (SOS Emergency)',
            problemDescription: issueDescription || null,
            serviceAddress: {
                addressLine: 'Emergency Location',
                location: { type: 'Point', coordinates: coords }
            },
            status: 'PENDING',
            invoice: {
                baseServiceFee: baseFee,
                extraPartsTotal: 0,
                platformFee: platformFee,
                urgentFee: urgentFee,
                totalAmount: totalAmount,
                paymentStatus: 'PENDING',
                paymentMethod: 'UPI'
            }
        });

        const populatedBooking = await Booking.findById(booking._id)
            .populate('service', 'name category icon basePrice')
            .populate('customer', 'name avatar')
            .lean();

        const io = req.app.get('io');
        if (io) {
            io.emit('emergency:booking_requested', {
                bookingId: booking._id,
                booking: populatedBooking,
                coordinates: coords,
                category: service?.category,
                urgentFee
            });
        }

        safeNotify(async () => {
            const workerIds = await findEligibleWorkerIds(booking, service?.category);
            await notifyUsers(workerIds, {
                eventType: 'EMERGENCY_BOOKING_ALERT',
                entityId: booking._id,
                bookingId: booking._id,
                dedupeKeyFor: (id) => `EMERGENCY_BOOKING_ALERT:${booking._id}:${id}`,
            });
        });

        return res.status(201).json({
            success: true,
            message: 'SOS Emergency booking dispatched to all nearby verified workers!',
            booking: populatedBooking
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};
