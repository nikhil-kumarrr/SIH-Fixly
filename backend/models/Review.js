import mongoose from 'mongoose';

const reviewSchema = new mongoose.Schema({
    booking: { type: mongoose.Schema.Types.ObjectId, ref: 'Booking', required: true },
    customer: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    worker: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    reviewerRole: { type: String, enum: ['customer', 'worker'], default: 'customer', required: true },
    rating: { type: Number, required: true, min: 1, max: 5 },
    feedback: { type: String, trim: true, default: null },
    badgesGiven: [{ type: String }], // e.g., 'On Time', 'Clean Workspace', 'Polite'
    photos: [{ type: String }]
}, { timestamps: true });

// Compound unique index: each booking can have one review per role (customer + worker)
reviewSchema.index({ booking: 1, reviewerRole: 1 }, { unique: true });
reviewSchema.index({ worker: 1, reviewerRole: 1, createdAt: -1 });

const Review = mongoose.model('Review', reviewSchema);

export default Review;
