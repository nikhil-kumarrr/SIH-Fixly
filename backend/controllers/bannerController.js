import Banner from '../models/Banner.js';
import User from '../models/User.js';
import mongoose from 'mongoose';
import { notifyUsers, notifyTopic, safeNotify } from '../services/notificationService.js';
import { invalidateHomeCache, syncBannerToRedis } from '../utils/homeCache.js';

const parseEmails = (raw) => {
    if (Array.isArray(raw)) {
        return raw.map((e) => String(e).toLowerCase().trim()).filter(Boolean);
    }
    if (typeof raw === 'string' && raw.trim()) {
        return raw.split(/[,;\s]+/).map((e) => e.toLowerCase().trim()).filter(Boolean);
    }
    return [];
};

const resolveTargetUserIds = async ({ targetUserIds, targetUserEmails }) => {
    let resolvedIds = Array.isArray(targetUserIds)
        ? targetUserIds.filter(Boolean).map((id) => String(id))
        : [];
    const emails = parseEmails(targetUserEmails);
    if (emails.length > 0) {
        const users = await User.find({ email: { $in: emails } }).select('_id').lean();
        for (const u of users) resolvedIds.push(String(u._id));
    }
    return { resolvedIds: [...new Set(resolvedIds)], emails };
};

export const getBanners = async (req, res) => {
    try {
        const { category, targetUserRole } = req.query;
        const query = { isActive: true };

        if (category && category !== 'all') {
            query.$or = [{ category: 'all' }, { category }];
        }

        if (targetUserRole && targetUserRole !== 'all') {
            query.targetUserRole = { $in: ['all', targetUserRole] };
        }

        // Hide user-specific coupons from public home unless assigned to this user
        const userId = req.user?.id || req.user?._id;
        if (userId) {
            query.$and = [
                ...(query.$and || []),
                {
                    $or: [
                        { targetUserIds: { $exists: false } },
                        { targetUserIds: { $size: 0 } },
                        { targetUserIds: userId },
                    ],
                },
                // Hide coupons this user already redeemed
                {
                    $or: [
                        { usedByUserIds: { $exists: false } },
                        { usedByUserIds: { $size: 0 } },
                        { usedByUserIds: { $nin: [userId] } },
                    ],
                },
            ];
        } else {
            query.$and = [
                ...(query.$and || []),
                {
                    $or: [
                        { targetUserIds: { $exists: false } },
                        { targetUserIds: { $size: 0 } },
                    ],
                },
            ];
        }

        const banners = await Banner.find(query)
            .sort({ priority: -1, createdAt: -1 })
            .lean();

        return res.status(200).json({
            success: true,
            banners,
        });
    } catch (error) {
        return res.status(500).json({
            success: false,
            message: error.message || 'Failed to fetch coupon banners',
            banners: [],
        });
    }
};

export const adminGetBanners = async (req, res) => {
    try {
        const banners = await Banner.find().sort({ priority: -1, createdAt: -1 }).lean();
        return res.status(200).json({ success: true, count: banners.length, banners });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

export const adminCreateBanner = async (req, res) => {
    try {
        const {
            title,
            code,
            discount,
            discountPercent,
            discountAmount,
            description,
            imageUrl,
            gradient,
            category,
            targetUserRole,
            targetUserIds,
            targetUserEmails,
            minOrderValue,
            maxDiscount,
            usageLimit,
            validUntil,
            isActive,
            priority
        } = req.body;

        if (!title || !code || !discount) {
            return res.status(400).json({
                success: false,
                message: 'Title, coupon code, and discount are required fields'
            });
        }

        const existing = await Banner.findOne({ code: code.toUpperCase().trim() });
        if (existing) {
            return res.status(400).json({
                success: false,
                message: `Coupon code '${code.toUpperCase()}' already exists`
            });
        }

        const { resolvedIds, emails } = await resolveTargetUserIds({
            targetUserIds,
            targetUserEmails,
        });

        const banner = await Banner.create({
            title,
            code: code.toUpperCase().trim(),
            discount,
            discountPercent: Number(discountPercent) || 0,
            discountAmount: Number(discountAmount) || 0,
            description: description || '',
            imageUrl: imageUrl || '',
            gradient: Array.isArray(gradient) && gradient.length > 0 ? gradient : ['#1E3A8A', '#3B82F6'],
            category: category || 'all',
            targetUserRole: targetUserRole || 'all',
            targetUserIds: resolvedIds,
            targetUserEmails: emails,
            minOrderValue: Number(minOrderValue) || 0,
            maxDiscount: Number(maxDiscount) || 500,
            usageLimit: Number(usageLimit) || 0,
            validUntil: validUntil ? new Date(validUntil) : new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
            isActive: isActive !== undefined ? Boolean(isActive) : true,
            priority: Number(priority) || 0
        });

        const shouldNotify = req.body.notifyUsers !== undefined ? Boolean(req.body.notifyUsers) : true;
        if (shouldNotify) {
            safeNotify(async () => {
                let eligibleUsers = [];
                if (resolvedIds.length > 0) {
                    eligibleUsers = await User.find({
                        _id: { $in: resolvedIds },
                        'notificationPreferences.marketing': { $ne: false }
                    }).select('_id').lean();
                } else {
                    const roleFilter = {};
                    if (targetUserRole === 'customer') roleFilter.role = 'customer';
                    else if (targetUserRole === 'worker') roleFilter.role = 'worker';
                    else if (targetUserRole === 'new_user') {
                        roleFilter.role = 'customer';
                        roleFilter.createdAt = { $gte: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000) };
                    } else {
                        roleFilter.role = { $in: ['customer', 'worker'] };
                    }
                    eligibleUsers = await User.find({
                        ...roleFilter,
                        'notificationPreferences.marketing': { $ne: false }
                    }).select('_id').lean();
                }

                const promoTitle = `New Offer: ${banner.discount}!`;
                const promoBody = `Use coupon code ${banner.code} to get ${banner.discount}. ${banner.description || ''}`.trim();

                if (eligibleUsers.length > 0) {
                    await notifyUsers(
                        eligibleUsers.map((u) => u._id),
                        {
                            title: promoTitle,
                            body: promoBody,
                            category: 'PROMOTION',
                            eventType: 'PROMOTION_COUPON',
                            action: 'discount',
                            priority: 'NORMAL',
                            data: {
                                couponCode: banner.code,
                                discount: banner.discount,
                                category: banner.category || 'all',
                                bannerId: String(banner._id)
                            }
                        }
                    );
                }

                if (resolvedIds.length === 0) {
                    try {
                        const topics = targetUserRole === 'worker'
                            ? ['fixly_workers_marketing']
                            : targetUserRole === 'customer'
                                ? ['fixly_customers_marketing']
                                : ['fixly_customers_marketing', 'fixly_workers_marketing'];
                        for (const topic of topics) {
                            await notifyTopic({
                                topic,
                                eventType: 'PROMOTION_COUPON',
                                title: promoTitle,
                                body: promoBody,
                                category: 'PROMOTION',
                                data: {
                                    couponCode: banner.code,
                                    discount: banner.discount,
                                    category: banner.category || 'all',
                                    bannerId: String(banner._id),
                                    action: 'discount'
                                }
                            });
                        }
                    } catch (err) {
                        console.warn('[notifications] topic broadcast skipped:', err.message);
                    }
                }
            });
        }

        await syncBannerToRedis();

        const io = req.app?.get('io');
        if (io) {
            io.emit('banners:updated', { action: 'created', banner });
            io.emit('home:updated');
        }

        return res.status(201).json({
            success: true,
            message: resolvedIds.length > 0
                ? `Coupon created for ${resolvedIds.length} specific user(s)`
                : 'Coupon banner created successfully',
            banner
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

export const adminUpdateBanner = async (req, res) => {
    try {
        const { id } = req.params;
        const banner = await Banner.findById(id);
        if (!banner) {
            return res.status(404).json({ success: false, message: 'Banner not found' });
        }

        const updates = { ...req.body };
        if (updates.code) updates.code = updates.code.toUpperCase().trim();

        if (updates.targetUserEmails !== undefined || updates.targetUserIds !== undefined) {
            const { resolvedIds, emails } = await resolveTargetUserIds({
                // Emails-only update replaces assignment (don't keep stale IDs)
                targetUserIds: updates.targetUserIds !== undefined
                    ? updates.targetUserIds
                    : (updates.targetUserEmails !== undefined ? [] : banner.targetUserIds),
                targetUserEmails: updates.targetUserEmails,
            });
            updates.targetUserIds = resolvedIds;
            updates.targetUserEmails = emails;
            // Re-assign = restore access: drop these users from usedByUserIds
            if (resolvedIds.length > 0) {
                const oidList = resolvedIds
                    .filter((id) => mongoose.isValidObjectId(id))
                    .map((id) => new mongoose.Types.ObjectId(id));
                if (oidList.length > 0) {
                    await Banner.updateOne(
                        { _id: id },
                        { $pull: { usedByUserIds: { $in: oidList } } }
                    );
                }
            }
        }

        const updated = await Banner.findByIdAndUpdate(id, updates, { new: true });
        await syncBannerToRedis();

        const io = req.app?.get('io');
        if (io) {
            io.emit('banners:updated', { action: 'updated', banner: updated });
            io.emit('home:updated');
        }

        return res.status(200).json({
            success: true,
            message: 'Coupon banner updated successfully',
            banner: updated
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

export const adminDeleteBanner = async (req, res) => {
    try {
        const { id } = req.params;
        const banner = await Banner.findByIdAndDelete(id);
        if (!banner) {
            return res.status(404).json({ success: false, message: 'Banner not found' });
        }
        await syncBannerToRedis();

        const io = req.app?.get('io');
        if (io) {
            io.emit('banners:updated', { action: 'deleted', bannerId: id });
            io.emit('home:updated');
        }

        return res.status(200).json({
            success: true,
            message: 'Coupon banner deleted successfully'
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};
