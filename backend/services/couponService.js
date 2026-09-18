import Banner from '../models/Banner.js';
import User from '../models/User.js';
import mongoose from 'mongoose';

/**
 * Validate a promotional coupon code and calculate discount amount
 */
export const validateAndCalculateCoupon = async ({
    couponCode,
    baseAmount = 0,
    serviceCategory = null,
    userRole = 'customer',
    userId = null,
    skipUsedCheck = false,
}) => {
    if (!couponCode || typeof couponCode !== 'string' || !couponCode.trim()) {
        return { isValid: false, message: 'Coupon code is required' };
    }

    const code = couponCode.toUpperCase().trim();
    const banner = await Banner.findOne({ code, isActive: true });

    if (!banner) {
        return { isValid: false, message: `Coupon code '${code}' is invalid or inactive` };
    }

    if (banner.validUntil && new Date(banner.validUntil) < new Date()) {
        return { isValid: false, message: `Coupon code '${code}' has expired` };
    }

    if (banner.usageLimit > 0 && banner.usedCount >= banner.usageLimit) {
        return { isValid: false, message: `Coupon code '${code}' has reached its usage limit` };
    }

    // Already redeemed by this user (unless re-applying same code on same booking)
    const usedBy = Array.isArray(banner.usedByUserIds) ? banner.usedByUserIds : [];
    if (!skipUsedCheck && userId && usedBy.some((id) => String(id) === String(userId))) {
        return {
            isValid: false,
            message: `Coupon '${code}' already used. Ask admin for a new coupon assignment.`,
        };
    }

    // User-specific: if targetUserIds set, only those users
    const targetedIds = Array.isArray(banner.targetUserIds) ? banner.targetUserIds : [];
    if (targetedIds.length > 0) {
        if (!userId) {
            return { isValid: false, message: `Coupon code '${code}' is restricted to specific users` };
        }
        const uid = String(userId);
        const allowed = targetedIds.some((id) => String(id) === uid);
        // Already-used users were pulled from targetUserIds — skipUsedCheck covers re-apply
        if (!allowed && !(skipUsedCheck && usedBy.some((id) => String(id) === uid))) {
            return { isValid: false, message: `Coupon code '${code}' is not assigned to your account` };
        }
    }

    // Role filter
    if (banner.targetUserRole && banner.targetUserRole !== 'all' && userRole) {
        if (banner.targetUserRole === 'new_user') {
            if (userRole !== 'customer') {
                return { isValid: false, message: `Coupon code '${code}' is for new customers only` };
            }
            if (userId && mongoose.isValidObjectId(userId)) {
                const user = await User.findById(userId).select('createdAt').lean();
                if (user?.createdAt) {
                    const ageMs = Date.now() - new Date(user.createdAt).getTime();
                    if (ageMs > 30 * 24 * 60 * 60 * 1000) {
                        return { isValid: false, message: `Coupon code '${code}' is for new customers only` };
                    }
                }
            }
        } else if (banner.targetUserRole !== userRole) {
            return { isValid: false, message: `Coupon code '${code}' is not applicable for your account` };
        }
    }

    // Category filter
    if (banner.category && banner.category !== 'all' && serviceCategory) {
        const catA = String(banner.category).toLowerCase().trim();
        const catB = String(serviceCategory).toLowerCase().trim();
        if (catA !== catB && !catB.includes(catA) && !catA.includes(catB)) {
            return { isValid: false, message: `Coupon code '${code}' is only valid for ${banner.category} services` };
        }
    }

    const orderAmt = Number(baseAmount) || 0;
    if (banner.minOrderValue && orderAmt < banner.minOrderValue) {
        return {
            isValid: false,
            message: `Minimum order amount of ₹${banner.minOrderValue} required to use coupon '${code}'`
        };
    }

    let discountAmount = 0;
    if (banner.discountPercent && banner.discountPercent > 0) {
        const calculated = Math.round(orderAmt * (banner.discountPercent / 100));
        const cap = banner.maxDiscount && banner.maxDiscount > 0 ? banner.maxDiscount : 500;
        discountAmount = Math.min(calculated, cap);
    } else if (banner.discountAmount && banner.discountAmount > 0) {
        discountAmount = Math.min(banner.discountAmount, orderAmt);
    } else if (banner.discount) {
        const percentMatch = String(banner.discount).match(/(\d+)\s*%/);
        const amountMatch = String(banner.discount).match(/(?:₹|RS|INR)?\s*(\d+)/i);
        if (percentMatch) {
            const pct = parseInt(percentMatch[1], 10);
            discountAmount = Math.min(Math.round(orderAmt * (pct / 100)), banner.maxDiscount || 500);
        } else if (amountMatch) {
            discountAmount = Math.min(parseInt(amountMatch[1], 10), orderAmt);
        }
    }

    discountAmount = Math.max(0, Math.min(discountAmount, orderAmt));
    const finalAmount = Math.max(0, orderAmt - discountAmount);

    return {
        isValid: true,
        couponCode: banner.code,
        title: banner.title,
        discount: banner.discount,
        discountAmount,
        finalAmount,
        minOrderValue: banner.minOrderValue || 0,
        maxDiscount: banner.maxDiscount || 0,
        bannerId: String(banner._id),
    };
};

/**
 * Mark coupon redeemed for a user: bump count, block re-use, pull from target list.
 * Admin must re-assign user (or new code) before they can use again.
 */
export const markCouponUsed = async (couponCode, userId = null) => {
    if (!couponCode) return;

    const code = String(couponCode).toUpperCase().trim();
    const update = { $inc: { usedCount: 1 } };

    if (userId && mongoose.isValidObjectId(userId)) {
        update.$addToSet = { usedByUserIds: userId };
        update.$pull = { targetUserIds: userId };

        const user = await User.findById(userId).select('email').lean();
        if (user?.email) {
            update.$pull.targetUserEmails = String(user.email).toLowerCase().trim();
        }
    }

    await Banner.updateOne({ code }, update);
};

export default {
    validateAndCalculateCoupon,
    markCouponUsed,
};
