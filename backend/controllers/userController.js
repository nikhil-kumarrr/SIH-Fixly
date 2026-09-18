import User from '../models/User.js';
import redis from '../config/redis.js';
import { fail, ok, isObjectId } from '../utils/http.js';

const publicUser = (user) => {
    const json = user.toObject ? user.toObject() : user;
    delete json.password;
    delete json.activeDeviceId;
    if (json.kycDocuments) {
        delete json.kycDocuments.aadhaarNumber;
        delete json.kycDocuments.govermentIdNumber;
        delete json.kycDocuments.panNumber;
    }
    return json;
};

export const getMyProfile = async (req, res) => {
    try {
        const user = await User.findById(req.user.id).select('-password');
        if (!user) return fail(res, 404, 'NOT_FOUND', 'User not found');
        return ok(res, { data: publicUser(user), user: publicUser(user) });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

export const updateMyProfile = async (req, res) => {
    try {
        const user = await User.findById(req.user.id);
        if (!user) return fail(res, 404, 'NOT_FOUND', 'User not found');

        const {
            name,
            phone,
            avatar,
            preferredLanguage,
            emergencyContact,
            workAddress,
            bio,
            rate,
            hourlyRate,
            experienceYears,
            skills,
            categories,
            category,
            gender,
            dateOfBirth,
            upiId,
            savedAddresses,
        } = req.body;

        if (name !== undefined) user.name = String(name).trim();
        if (phone !== undefined) user.phone = String(phone).trim();
        if (avatar !== undefined) user.avatar = avatar;
        if (preferredLanguage !== undefined) user.preferredLanguage = preferredLanguage;

        if (req.body.notificationPreferences !== undefined && typeof req.body.notificationPreferences === 'object') {
            user.notificationPreferences = {
                ...(user.notificationPreferences?.toObject ? user.notificationPreferences.toObject() : user.notificationPreferences),
                ...req.body.notificationPreferences,
            };
        }

        if (emergencyContact !== undefined && typeof emergencyContact === 'object') {
            user.emergencyContact = {
                name: emergencyContact.name !== undefined ? String(emergencyContact.name).trim() : (user.emergencyContact?.name || null),
                phone: emergencyContact.phone !== undefined ? String(emergencyContact.phone).trim() : (user.emergencyContact?.phone || null),
                relation: emergencyContact.relation !== undefined ? String(emergencyContact.relation).trim() : (user.emergencyContact?.relation || null),
            };
        }

        const isWorkerRole = user.role === 'worker';

        if (savedAddresses !== undefined && Array.isArray(savedAddresses)) {
            const prev = Array.isArray(user.savedAddresses) && user.savedAddresses[0]
                ? user.savedAddresses[0]
                : {};
            const prevLoc = prev.location?.coordinates?.length === 2
                ? prev.location
                : { type: 'Point', coordinates: [0, 0] };
            user.savedAddresses = savedAddresses.map((addr, idx) => {
                const a = addr && typeof addr === 'object' ? addr : {};
                const loc = a.location?.coordinates?.length === 2 ? a.location : (idx === 0 ? prevLoc : { type: 'Point', coordinates: [0, 0] });
                return {
                    label: a.label || (idx === 0 ? (prev.label || 'Home') : 'Address'),
                    addressLine: a.addressLine !== undefined ? String(a.addressLine).trim() : (prev.addressLine || ''),
                    city: a.city !== undefined ? String(a.city).trim() : (prev.city || ''),
                    pincode: a.pincode !== undefined ? String(a.pincode).trim() : (prev.pincode || ''),
                    location: loc,
                };
            });
        } else if (!isWorkerRole && workAddress !== undefined) {
            const line = String(workAddress).trim();
            const prev = Array.isArray(user.savedAddresses) && user.savedAddresses[0]
                ? user.savedAddresses[0]
                : {};
            const prevLoc = prev.location?.coordinates?.length === 2
                ? prev.location
                : { type: 'Point', coordinates: [0, 0] };
            user.savedAddresses = [{
                label: prev.label || 'Home',
                addressLine: line,
                city: req.body.city !== undefined ? String(req.body.city).trim() : (prev.city || ''),
                pincode: req.body.pincode !== undefined ? String(req.body.pincode).trim() : (prev.pincode || ''),
                location: prevLoc,
            }];
        }

        if (isWorkerRole) {
            const wp = (user.workerProfile && user.workerProfile.toObject
                ? user.workerProfile.toObject()
                : user.workerProfile) || {};
            const effRate = Number(hourlyRate !== undefined ? hourlyRate : (rate !== undefined ? rate : (wp.hourlyRate ?? wp.rate ?? 0)));
            const effExp = experienceYears !== undefined ? Number(experienceYears) : (wp.experienceYears ?? 0);
            const effBio = bio !== undefined ? String(bio).trim() : (wp.bio ?? null);
            const effWorkAddress = workAddress !== undefined ? String(workAddress).trim() : (wp.workAddress ?? null);
            const effCategory = category !== undefined ? String(category).trim() : (wp.category ?? null);
            const effCategories = Array.isArray(categories) ? categories.map(String) : (wp.categories || (effCategory ? [effCategory] : []));
            const effSkills = Array.isArray(skills) ? skills.map(String) : (wp.skills || effCategories);

            user.workerProfile = {
                ...wp,
                bio: effBio,
                workAddress: effWorkAddress,
                rate: effRate,
                hourlyRate: effRate,
                experienceYears: Number.isFinite(effExp) ? effExp : 0,
                category: effCategory,
                categories: effCategories,
                skills: effSkills,
            };

            if (gender !== undefined) user.workerProfile.gender = gender;
            if (dateOfBirth !== undefined) user.workerProfile.dateOfBirth = dateOfBirth;
            if (upiId !== undefined) {
                user.workerProfile.upi = { upiId: String(upiId).trim() };
            }
            if (req.body.state !== undefined) {
                user.workerProfile.state = String(req.body.state).trim();
            }
            if (req.body.district !== undefined) {
                user.workerProfile.district = String(req.body.district).trim();
            }
        }

        await user.save();
        const cleanUser = publicUser(user);
        return ok(res, { data: cleanUser, user: cleanUser });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

export const updateLanguage = async (req, res) => {
    try {
        const raw = String(req.body.language || req.body.preferredLanguage || '').trim().toLowerCase();
        let normalized = 'en';
        if (raw === 'hi' || raw === 'hindi') {
            normalized = 'hi';
        } else if (raw === 'en' || raw === 'english') {
            normalized = 'en';
        } else {
            return fail(res, 400, 'VALIDATION_ERROR', 'Language must be either "hi" (Hindi) or "en" (English)');
        }

        const user = await User.findByIdAndUpdate(
            req.user.id,
            { preferredLanguage: normalized },
            { returnDocument: 'after' },
        ).select('-password');

        if (!user) return fail(res, 404, 'NOT_FOUND', 'User not found');

        // Sync into Redis so notifications and mobile requests immediately pick it up
        try {
            await redis.set(`user:lang:${req.user.id}`, normalized, 'EX', 86400 * 30);
        } catch (_) {}

        return ok(res, {
            data: { preferredLanguage: user.preferredLanguage },
            preferredLanguage: user.preferredLanguage,
            message: 'Language preference updated successfully.'
        });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

export const updateLocation = async (req, res) => {
    try {
        const { coordinates, lng, lat } = req.body;
        const pair = Array.isArray(coordinates)
            ? coordinates
            : (lng != null && lat != null ? [Number(lng), Number(lat)] : null);
        if (!pair || pair.length !== 2 || Number.isNaN(pair[0]) || Number.isNaN(pair[1])) {
            return fail(res, 400, 'VALIDATION_ERROR', 'coordinates must be [longitude, latitude]');
        }
        const user = await User.findByIdAndUpdate(
            req.user.id,
            { location: { type: 'Point', coordinates: pair } },
            { returnDocument: 'after' },
        ).select('-password');
        return ok(res, { data: { location: user.location } });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

export const updateEmergencyContact = async (req, res) => {
    try {
        const { name, phone, relation } = req.body || {};
        if (!name || !phone) return fail(res, 400, 'VALIDATION_ERROR', 'name and phone required');
        const user = await User.findByIdAndUpdate(
            req.user.id,
            { emergencyContact: { name, phone, relation: relation || null } },
            { returnDocument: 'after' },
        ).select('-password');
        return ok(res, { data: { emergencyContact: user.emergencyContact } });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

export const listAddresses = async (req, res) => {
    try {
        const user = await User.findById(req.user.id).select('savedAddresses');
        if (!user) return fail(res, 404, 'NOT_FOUND', 'User not found');
        return ok(res, { data: user.savedAddresses });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

export const addAddress = async (req, res) => {
    try {
        const { label, addressLine, city, pincode, coordinates } = req.body || {};
        if (!addressLine || !Array.isArray(coordinates) || coordinates.length !== 2) {
            return fail(res, 400, 'VALIDATION_ERROR', 'addressLine and [lng, lat] required');
        }
        const user = await User.findById(req.user.id);
        user.savedAddresses.push({
            label: label || 'Home',
            addressLine,
            city,
            pincode,
            location: { type: 'Point', coordinates },
        });
        await user.save();
        return ok(res, { data: user.savedAddresses }, 201);
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

export const updateAddress = async (req, res) => {
    try {
        const { id } = req.params;
        if (!isObjectId(id)) return fail(res, 400, 'VALIDATION_ERROR', 'Invalid address id');
        const user = await User.findById(req.user.id);
        const addr = user.savedAddresses.id(id);
        if (!addr) return fail(res, 404, 'NOT_FOUND', 'Address not found');
        const { label, addressLine, city, pincode, coordinates } = req.body || {};
        if (label != null) addr.label = label;
        if (addressLine != null) addr.addressLine = addressLine;
        if (city != null) addr.city = city;
        if (pincode != null) addr.pincode = pincode;
        if (Array.isArray(coordinates) && coordinates.length === 2) {
            addr.location = { type: 'Point', coordinates };
        }
        await user.save();
        return ok(res, { data: user.savedAddresses });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

export const deleteAddress = async (req, res) => {
    try {
        const { id } = req.params;
        const user = await User.findById(req.user.id);
        const addr = user.savedAddresses.id(id);
        if (!addr) return fail(res, 404, 'NOT_FOUND', 'Address not found');
        addr.deleteOne();
        await user.save();
        return ok(res, { data: user.savedAddresses });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

export const updateNotificationPreferences = async (req, res) => {
    try {
        const { marketing, system, push } = req.body;
        const updates = {};
        if (marketing !== undefined) updates['notificationPreferences.marketing'] = Boolean(marketing);
        if (system !== undefined) updates['notificationPreferences.system'] = Boolean(system);
        if (push !== undefined) updates['notificationPreferences.push'] = Boolean(push);

        const user = await User.findByIdAndUpdate(
            req.user.id,
            { $set: updates },
            { returnDocument: 'after' }
        ).select('notificationPreferences');

        if (!user) return fail(res, 404, 'NOT_FOUND', 'User not found');
        return ok(res, { data: user.notificationPreferences });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};
