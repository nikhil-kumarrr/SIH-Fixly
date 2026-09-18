import mongoose from 'mongoose';

const bannerSchema = new mongoose.Schema({
    title: { type: String, required: true, trim: true },
    code: { type: String, required: true, uppercase: true, trim: true },
    discount: { type: String, required: true, trim: true },
    discountPercent: { type: Number, default: 0 },
    discountAmount: { type: Number, default: 0 },
    description: { type: String, trim: true, default: '' },
    imageUrl: { type: String, default: '' },
    gradient: [{ type: String }],
    category: { type: String, default: 'all', index: true },
    // all | customer | worker | new_user | vip
    targetUserRole: {
        type: String,
        enum: ['all', 'customer', 'worker', 'new_user', 'vip'],
        default: 'all'
    },
    // Empty = everyone matching filters. Non-empty = only these users.
    targetUserIds: [{ type: mongoose.Schema.Types.ObjectId, ref: 'User' }],
    // Optional emails stored for admin UX; resolved to IDs on create/update
    targetUserEmails: [{ type: String, lowercase: true, trim: true }],
    minOrderValue: { type: Number, default: 0 },
    maxDiscount: { type: Number, default: 500 },
    usageLimit: { type: Number, default: 0 }, // 0 = unlimited total uses
    usedCount: { type: Number, default: 0 },
    // Users who already redeemed — blocked until admin re-assigns them
    usedByUserIds: [{ type: mongoose.Schema.Types.ObjectId, ref: 'User' }],
    validUntil: { type: Date },
    isActive: { type: Boolean, default: true, index: true },
    priority: { type: Number, default: 0 }
}, { timestamps: true });

bannerSchema.index({ code: 1 }, { unique: true });

const Banner = mongoose.model('Banner', bannerSchema);

export default Banner;
