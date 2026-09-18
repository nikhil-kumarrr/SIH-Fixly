import express from 'express';
import {
    calculateEstimate,
    createBooking,
    getBookingDetails,
    updateBooking,
    cancelBooking,
    getLiveTracking,
    getBookingInvoice,
    triggerSosAlert,
    getBookingHistory,
    listWorkerIncoming,
    listWorkerActive,
    listWorkerCompleted,
    declineBooking,
    workerCancelBooking,
    createEmergencyBooking,
    validateCoupon,
    applyCouponToBooking,
    removeCouponFromBooking,
} from '../controllers/bookingController.js';
import {
    verifyArrivalOtp,
    verifyCompletionOtp,
    addExtraParts,
    completeJob,
    acceptBooking,
    startJob,
    startNavigation,
    submitPriceEstimation,
    acceptEstimation
} from '../controllers/activeJobController.js';
import { protect } from '../middleware/authMiddleware.js';
import upload from '../middleware/uploadMiddleware.js';
import { getBookingReview } from '../controllers/reviewController.js';

const router = express.Router();

// Search & Booking Creation
router.get('/history', protect, getBookingHistory);
router.get('/worker/incoming', protect, listWorkerIncoming);
router.get('/worker/active', protect, listWorkerActive);
router.get('/worker/completed', protect, listWorkerCompleted);
router.post('/estimate', protect, calculateEstimate);
router.post('/validate-coupon', protect, validateCoupon);
router.post('/:bookingId/apply-coupon', protect, applyCouponToBooking);
router.post('/:bookingId/remove-coupon', protect, removeCouponFromBooking);
router.post('/emergency', protect, createEmergencyBooking);
router.post('/', protect, upload.array('photos', 5), createBooking);
router.get('/:bookingId/review', protect, getBookingReview);
router.get('/:bookingId', protect, getBookingDetails);
router.patch('/:bookingId', protect, updateBooking);
router.patch('/:bookingId/cancel', protect, cancelBooking);
router.post('/:bookingId/worker-cancel', protect, workerCancelBooking);
router.post('/:bookingId/decline', protect, declineBooking);

// Verification & Live Tracking
router.get('/:bookingId/track', protect, getLiveTracking);
router.post('/:bookingId/accept', protect, acceptBooking);
router.post('/:bookingId/start-navigation', protect, startNavigation);
router.post('/:bookingId/verify-otp', protect, verifyArrivalOtp);
router.post('/:bookingId/submit-estimation', protect, submitPriceEstimation);
router.post('/:bookingId/price-estimation', protect, submitPriceEstimation);
router.post('/:bookingId/accept-estimation', protect, acceptEstimation);
router.post('/:bookingId/verify-completion-otp', protect, verifyCompletionOtp);
router.post('/:bookingId/start-job', protect, startJob);

// Job Execution & Extra Parts
router.patch('/:bookingId/add-parts', protect, addExtraParts);
router.post('/:bookingId/complete', protect, completeJob);
router.post('/:bookingId/sos', protect, triggerSosAlert);

// Billing & Invoice
router.get('/:bookingId/invoice', protect, getBookingInvoice);

export default router;