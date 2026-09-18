import express from 'express';
import { submitReview, getBookingReview } from '../controllers/reviewController.js';
import { protect } from '../middleware/authMiddleware.js';
import upload from '../middleware/uploadMiddleware.js';

const router = express.Router();

// Single unified endpoint for review submission (supports up to 3 work photos via multipart or JSON)
router.post('/:bookingId', protect, upload.any(), submitReview);
router.post('/', protect, upload.any(), submitReview);
router.get('/:bookingId', protect, getBookingReview);

export default router;