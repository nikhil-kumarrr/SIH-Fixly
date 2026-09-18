import User from '../models/User.js';
import Cooperative from '../models/Cooperative.js';
import CooperativeSociety from '../models/CooperativeSociety.js';
import redis from '../config/redis.js';
import { generateOtpEmailHtml } from '../utils/emailTemplate.js';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import fs from 'fs';
import { emailQueue } from '../queues/queue.js';
import { uploadToCloudinary } from '../utils/cloudinary.js';
import { queueFileUpload } from '../utils/upload.js';
import { uploadQueueManager } from '../utils/uploadQueue.js';

const generateOTP = () => Math.floor(100000 + Math.random() * 900000).toString();
const REDIS_VERIFIED_TTL = 86400; // 24 Hours Cache TTL

// ==========================================
// SINGLE-DEVICE SESSION HELPER
// ==========================================
const createSession = async (user, deviceId) => {
    const userIdStr = user._id ? user._id.toString() : user.id;

    // Use User schema helper methods if the object is a Mongoose instance, else fallback
    const accessToken = typeof user.generateAccessToken === 'function'
        ? user.generateAccessToken()
        : jwt.sign(
            { id: userIdStr, role: user.role },
            process.env.JWT_SECRET,
            { expiresIn: process.env.JWT_ACCESS_EXPIRY || '15m' }
        );

    const refreshToken = typeof user.generateRefreshToken === 'function'
        ? user.generateRefreshToken()
        : jwt.sign(
            { id: userIdStr },
            process.env.REFRESH_SECRET,
            { expiresIn: process.env.JWT_REFRESH_EXPIRY || '7d' }
        );

    if (deviceId) {
        const activeDeviceKey = `user:active-device:${userIdStr}`;
        const oldDeviceId = await redis.get(activeDeviceKey);

        if (oldDeviceId && oldDeviceId !== deviceId) {
            await redis.del(`session:${userIdStr}:${oldDeviceId}`);
        }

        const sessionTtl = parseInt(process.env.REDIS_SESSION_TTL_SEC, 10) || 7 * 24 * 60 * 60;
        const pipeline = redis.pipeline();
        pipeline.set(activeDeviceKey, deviceId, 'EX', sessionTtl);
        pipeline.set(`session:${userIdStr}:${deviceId}`, refreshToken, 'EX', sessionTtl);
        await pipeline.exec();

        // Sync the activeDeviceId to MongoDB
        await User.findByIdAndUpdate(userIdStr, { activeDeviceId: deviceId });

        // Update local object reference in-place
        user.activeDeviceId = deviceId;
    }

    return { accessToken, refreshToken };
};

// User object se password strip karke Redis me cache karna
export const syncUserCache = async (email, userData) => {
    const { password, ...safeUser } = userData;
    const ttl = safeUser.isVerified ? REDIS_VERIFIED_TTL : 300;
    await redis.set(`user:email:${email}`, JSON.stringify(safeUser), 'EX', ttl);
};

// Cache Reader Helper
const getUserCache = async (email) => {
    const cachedUser = await redis.get(`user:email:${email}`);
    if (cachedUser) return JSON.parse(cachedUser);

    const user = await User.findOne({ email }).select('-password').lean();
    if (user) {
        await syncUserCache(email, user);
    }
    return user;
};

// ==========================================
// CONTROLLERS
// ==========================================

// Get Current Logged-in User Profile
export const getMe = async (req, res) => {
    try {
        const user = await User.findById(req.user.id).select('-password');

        if (!user) {
            return res.status(404).json({ success: false, message: 'User not found' });
        }

        res.status(200).json({
            success: true,
            user
        });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

// 1. REGISTER (Uses User schema pre-save hook for password hashing)
export const registerUser = async (req, res) => {
    // #swagger.tags = ['Auth']
    // #swagger.parameters['body'] = { in: 'body', description: 'User registration details', required: true, schema: { $ref: '#/definitions/RegisterInput' } }
    try {
        const { name, email, password, role, phone, location, workerProfile, federationId } = req.body;
        if (!email) return res.status(400).json({ success: false, message: 'Email is required' });

        if (role === 'admin') {
            return res.status(403).json({
                success: false,
                message: 'Admin registration is not allowed. Please login with configured system credentials.'
            });
        }

        const registeredRole = role === 'worker' ? 'worker' : 'customer';

        const emailNormalized = email.toLowerCase().trim();
        const existingUser = await getUserCache(emailNormalized);
        if (existingUser && existingUser.isVerified) {
            return res.status(400).json({ success: false, message: 'User already exists' });
        }
        
        let validFederationId = null;
        if (federationId) {
            const coop = await Cooperative.findById(federationId);
            if (coop && coop.status === 'approved') {
                validFederationId = federationId;
            } else {
                return res.status(400).json({ success: false, message: 'Invalid or unapproved federation' });
            }
        }

        const hasFullWorkerProfile = workerProfile && (
            workerProfile.category ||
            workerProfile.rate ||
            (workerProfile.categoryRates && workerProfile.categoryRates.length > 0)
        );

        // Keep workerProfile null until onboarding (setup-profile). A stub object
        // makes the app think KYC was submitted and skip to verification status.
        const userPayload = {
            name,
            email: emailNormalized,
            password, // Hashed automatically by User model's pre-save hook
            role: registeredRole,
            authProvider: 'local',
            phone: phone || null,
            location: location || null,
            workerProfile: registeredRole === 'worker' && hasFullWorkerProfile
                ? {
                    ...workerProfile,
                    rating: workerProfile.rating ?? 0.0,
                    totalJobs: workerProfile.totalJobs ?? 0,
                    walletBalance: workerProfile.walletBalance ?? 0,
                    totalEarnings: workerProfile.totalEarnings ?? 0,
                }
                : null,
            ...(validFederationId && { federation: validFederationId })
        };

        let userDoc = await User.findOne({ email: emailNormalized });
        if (!userDoc) {
            userDoc = await User.create(userPayload);
        } else {
            Object.assign(userDoc, userPayload);
            await userDoc.save();
        }

        const otp = generateOTP();
        const otpExpiry = parseInt(process.env.OTP_EXPIRY_SEC, 10) || 300;
        const pipeline = redis.pipeline();
        pipeline.del(`user:email:${emailNormalized}`);
        pipeline.set(`otp:${emailNormalized}`, otp, 'EX', otpExpiry);
        await pipeline.exec();

        await emailQueue.add('sendOtpEmail', {
            to: emailNormalized,
            subject: 'Your Verification Code',
            html: generateOtpEmailHtml(otp)
        });

        return res.status(201).json({
            success: true,
            message: 'OTP sent to email. Please verify.',
            userId: userDoc._id
        });
    } catch (error) {
        console.error('Register Error:', error);
        return res.status(500).json({ success: false, message: error.message });
    }
};

// 1.5 REGISTER FEDERATION
export const registerFederation = async (req, res) => {
    try {
        const { name, federationName, state, district, email, password, phone, registrationNumber } = req.body;
        
        if (!email || !password || !name) {
            return res.status(400).json({ success: false, message: 'Email, password, and name are required' });
        }

        const emailNormalized = email.toLowerCase().trim();
        const existingUser = await User.findOne({ email: emailNormalized });
        
        if (existingUser) {
            return res.status(400).json({ success: false, message: 'Email already registered' });
        }

        // Create cooperative (status pending)
        const coop = await Cooperative.create({
            name,
            federationName,
            state,
            district,
            registrationNumber,
            email: emailNormalized,
            phone,
            status: 'pending'
        });

        // Create admin user
        const adminUser = await User.create({
            name,
            email: emailNormalized,
            password,
            role: 'admin',
            adminRole: 'federation_admin',
            federation: coop._id,
            isVerified: true,
            isEmailVerified: true
        });

        coop.owner = adminUser._id;
        await coop.save();

        return res.status(201).json({
            success: true,
            message: 'Federation registered successfully. Awaiting super admin approval.',
            federationId: coop._id
        });
    } catch (error) {
        console.error('Register Federation Error:', error);
        return res.status(500).json({ success: false, message: error.message });
    }
};

// 2. VERIFY REGISTRATION OTP
export const verifyOTP = async (req, res) => {
    // #swagger.tags = ['Auth']
    // #swagger.parameters['body'] = { in: 'body', description: 'OTP verification details', required: true, schema: { $ref: '#/definitions/VerifyOtpInput' } }
    try {
        const { email, otp, deviceId } = req.body;
        if (!email || !otp) {
            return res.status(400).json({ success: false, message: 'Email and OTP are required' });
        }

        const emailNormalized = email.toLowerCase().trim();
        const cachedOtp = await redis.get(`otp:${emailNormalized}`);
        if (!cachedOtp || cachedOtp !== otp.toString()) {
            return res.status(400).json({ success: false, message: 'Invalid or expired OTP' });
        }

        const user = await User.findOne({ email: emailNormalized });
        if (!user) return res.status(404).json({ success: false, message: 'User not found' });

        user.isEmailVerified = true;
        if (user.role === 'customer') {
            user.isVerified = true;
        } else {
            // For workers, account isVerified status stays false until explicitly approved by Admin
            user.isVerified = Boolean(user.isVerified);
        }
        await user.save();

        const userObj = user.toObject();
        delete userObj.password;

        const pipeline = redis.pipeline();
        pipeline.del(`otp:${emailNormalized}`);
        await pipeline.exec();

        const tokens = await createSession(userObj, deviceId);
        await syncUserCache(emailNormalized, userObj);

        return res.status(200).json({
            success: true,
            message: 'Email verified successfully',
            user: userObj,
            ...tokens
        });
    } catch (error) {
        console.error('Verify OTP Error:', error);
        return res.status(500).json({ success: false, message: error.message });
    }
};

// 3. LOGIN
export const loginUser = async (req, res) => {
    // #swagger.tags = ['Auth']
    // #swagger.parameters['body'] = { in: 'body', description: 'User login credentials', required: true, schema: { $ref: '#/definitions/LoginInput' } }
    try {
        const { email, password, deviceId, location, phone } = req.body;
        if (!email || !password) {
            return res.status(400).json({ success: false, message: 'Email and password are required' });
        }

        const emailNormalized = email.toLowerCase().trim();
        const user = await User.findOne({ email: emailNormalized }).select('+password');
        if (!user) {
            console.log(`[AUTH LOGIN] User not found: "${emailNormalized}"`);
            return res.status(404).json({ success: false, message: 'User not found' });
        }

        if (user.authProvider === 'google') {
            return res.status(400).json({ success: false, message: 'Please login using Google' });
        }

        const isMatch = await user.comparePassword(password);
        if (!isMatch) {
            console.log(`[AUTH LOGIN] Password mismatch for user: "${emailNormalized}"`);
            return res.status(401).json({ success: false, message: 'Invalid credentials' });
        }

        if (!user.isEmailVerified && !user.isVerified) {
            return res.status(401).json({ success: false, message: 'Please verify your email first' });
        }

        let isModified = false;
        if (user.role === 'customer' && user.kycDocuments) {
            user.kycDocuments = undefined;
            isModified = true;
        }
        if (location) {
            user.location = location;
            isModified = true;
        }
        if (phone && !user.phone) {
            user.phone = phone;
            isModified = true;
        }

        if (isModified) {
            await user.save();
        }

        const userObj = user.toObject();
        delete userObj.password;

        const tokens = await createSession(userObj, deviceId);
        await syncUserCache(emailNormalized, userObj);

        return res.status(200).json({
            success: true,
            user: userObj,
            ...tokens
        });
    } catch (error) {
        console.error('Login Error:', error);
        return res.status(500).json({ success: false, message: error.message });
    }
};

// Helper functions for safe parsing of nested bank and upi objects
const parseBankObj = (val) => {
    if (!val || typeof val !== 'object') return {};
    return {
        accountHolderName: val.accountHolderName || null,
        accountNumber: val.accountNumber || null,
        ifscCode: val.ifscCode || null,
        bankVerified: Boolean(val.bankVerified)
    };
};

const parseUpiObj = (val) => {
    if (!val) return {};
    if (typeof val === 'string') return { upiId: val, upiVerified: false };
    if (typeof val === 'object') {
        return {
            upiId: val.upiId || val.upi || null,
            upiVerified: Boolean(val.upiVerified)
        };
    }
    return {};
};

const parseCategoryRates = (rawInput, defaultCategory = 'General', defaultRate = 0) => {
    if (!rawInput && rawInput !== 0) return null;
    let input = rawInput;
    if (typeof input === 'string') {
        try {
            input = JSON.parse(input);
        } catch (e) {
            // Not a JSON string
        }
    }

    if (Array.isArray(input)) {
        return input.map(item => {
            if (typeof item === 'object' && item !== null) {
                const cat = item.category || item.name || defaultCategory;
                const r = Number(item.rate ?? item.price ?? defaultRate) || 0;
                return { category: String(cat).trim(), rate: r };
            } else if (typeof item === 'number' || (typeof item === 'string' && !isNaN(Number(item)))) {
                return { category: String(defaultCategory).trim(), rate: Number(item) || 0 };
            }
            return null;
        }).filter(Boolean);
    }

    if (typeof input === 'object' && input !== null) {
        const cat = input.category || defaultCategory;
        const r = Number(input.rate ?? defaultRate) || 0;
        return [{ category: String(cat).trim(), rate: r }];
    }

    if (typeof input === 'number' || (typeof input === 'string' && input && !isNaN(Number(input)))) {
        return [{ category: String(defaultCategory).trim(), rate: Number(input) || 0 }];
    }

    return null;
};

// Helper: Upload Base64 / File / URL to Cloudinary with Folder Support
const uploadBase64ToCloudinary = async (inputSource, folder = 'gigconnect') => {
    if (!inputSource) return null;

    if (typeof inputSource === 'string' && (inputSource.startsWith('http://') || inputSource.startsWith('https://'))) {
        return inputSource;
    }

    if (typeof inputSource === 'string' && (inputSource.startsWith('data:image') || inputSource.startsWith('data:application/pdf') || inputSource.startsWith('data:application/'))) {
        try {
            const result = await uploadToCloudinary(inputSource, folder);
            return result.secure_url;
        } catch (error) {
            console.error(`Cloudinary Base64 Upload Error (${folder}):`, error);
            throw new Error('Image upload failed. Please try again.');
        }
    }

    if (typeof inputSource === 'object' && (inputSource.path || inputSource.buffer)) {
        try {
            const source = inputSource.path || inputSource.buffer;
            const result = await uploadToCloudinary(source, folder);
            if (inputSource.path && fs.existsSync(inputSource.path)) {
                await fs.promises.unlink(inputSource.path).catch(() => { });
            }
            return result.secure_url;
        } catch (error) {
            console.error(`Cloudinary Multer File Upload Error (${folder}):`, error);
            throw new Error('File upload failed. Please try again.');
        }
    }

    if (typeof inputSource === 'string' && inputSource.trim()) {
        const cleanPath = inputSource.replace(/^file:\/\//, '');
        if (fs.existsSync(cleanPath)) {
            try {
                const result = await uploadToCloudinary(cleanPath, folder);
                return result.secure_url;
            } catch (error) {
                console.error(`Cloudinary File Path Upload Error (${folder}):`, error);
            }
        }
    }

    return null;
};

// 4. DYNAMIC WORKER PROFILE SETUP & UPDATE (Asynchronous BullMQ & Controlled Upload Queue)
export const updateUserProfile = async (req, res) => {
    /*  #swagger.tags = ['Auth']
        #swagger.summary = 'Setup & Update Worker Profile (Supports File Picker Uploads & Base64 JSON via Queue)'
        #swagger.consumes = ['multipart/form-data', 'application/json']
        #swagger.parameters['avatar'] = { in: 'formData', type: 'file', description: 'Profile Photo / Selfie Image' }
        #swagger.parameters['aadhaarFrontPhoto'] = { in: 'formData', type: 'file', description: 'Aadhaar Card Front Photo' }
        #swagger.parameters['aadhaarBackPhoto'] = { in: 'formData', type: 'file', description: 'Aadhaar Card Back Photo' }
        #swagger.parameters['panFrontPhoto'] = { in: 'formData', type: 'file', description: 'PAN Card Front Photo' }
        #swagger.parameters['panBackPhoto'] = { in: 'formData', type: 'file', description: 'PAN Card Back Photo' }
        #swagger.parameters['certificate'] = { in: 'formData', type: 'file', description: 'Certificate Document / Image' }
        #swagger.parameters['name'] = { in: 'formData', type: 'string', description: 'Full Name' }
        #swagger.parameters['phone'] = { in: 'formData', type: 'string', description: 'Phone Number' }
        #swagger.parameters['dateOfBirth'] = { in: 'formData', type: 'string', description: 'Date of Birth (YYYY-MM-DD)' }
        #swagger.parameters['gender'] = { in: 'formData', type: 'string', description: 'Gender (male/female/other)' }
        #swagger.parameters['category'] = { in: 'formData', type: 'string', description: 'Primary Category (e.g. electrician)' }
        #swagger.parameters['categories'] = { in: 'formData', type: 'string', description: 'Categories list' }
        #swagger.parameters['rate'] = { in: 'formData', type: 'number', description: 'Base Rate / Minimum Service Cost' }
        #swagger.parameters['categoryRates'] = { in: 'formData', type: 'string', description: 'Category Rates array JSON' }
        #swagger.parameters['experienceYears'] = { in: 'formData', type: 'number', description: 'Years of Experience' }
        #swagger.parameters['bio'] = { in: 'formData', type: 'string', description: 'Worker Bio' }
        #swagger.parameters['skills'] = { in: 'formData', type: 'string', description: 'Skills list' }
        #swagger.parameters['aadhaarNumber'] = { in: 'formData', type: 'string', description: 'Aadhaar Card Number' }
        #swagger.parameters['panNumber'] = { in: 'formData', type: 'string', description: 'PAN Card Number' }
        #swagger.parameters['workAddress'] = { in: 'formData', type: 'string', description: 'Work Address' }
        #swagger.parameters['payoutMethod'] = { in: 'formData', type: 'string', description: 'Payout Method (bank/upi)' }
        #swagger.parameters['bank'] = { in: 'formData', type: 'string', description: 'Bank Details JSON' }
        #swagger.parameters['upi'] = { in: 'formData', type: 'string', description: 'UPI Details JSON' }
    */
    try {
        const userId = req.user.id;
        const user = await User.findById(userId);
        if (!user) return res.status(404).json({ success: false, message: 'User not found' });

        // Body preprocessing (JSON string parsing for multipart form-data)
        const body = { ...req.body };
        ['categoryRates', 'categories', 'skills', 'certifications', 'certificates', 'location', 'bank', 'upi', 'workerProfile'].forEach(key => {
            if (typeof body[key] === 'string') {
                try {
                    body[key] = JSON.parse(body[key]);
                } catch (e) {
                    if (['categories', 'skills', 'certifications', 'certificates'].includes(key)) {
                        body[key] = body[key].split(',').map(s => s.trim()).filter(Boolean);
                    }
                }
            }
        });

        // Helper to extract file object from req.files/req.file or fall back to body field
        const getFileInput = (bodyField, possibleFieldNames = []) => {
            const namesLower = possibleFieldNames.map(n => n.toLowerCase());
            if (req.files && Array.isArray(req.files)) {
                const found = req.files.find(f => namesLower.includes(f.fieldname.toLowerCase()));
                if (found) return found;
            } else if (req.files && typeof req.files === 'object') {
                const allFiles = Object.values(req.files).flat();
                const found = allFiles.find(f => f && f.fieldname && namesLower.includes(f.fieldname.toLowerCase()));
                if (found) return found;
            } else if (req.file && namesLower.includes(req.file.fieldname.toLowerCase())) {
                return req.file;
            }
            return bodyField;
        };

        const avatarInput = getFileInput(body.avatar || body.avatarUrl || body.profilePhoto || body.selfie || body.selfieImageUrl, ['avatar', 'avatarUrl', 'profilePhoto', 'profilephoto', 'selfie', 'selfieImageUrl']);
        const aadhaarFrontInput = getFileInput(body.aadhaarFrontPhoto || body.aadhaarFront, ['aadhaarFrontPhoto', 'aadhaarFront', 'aadhaar_front', 'frontphoto']);
        const aadhaarBackInput = getFileInput(body.aadhaarBackPhoto || body.aadhaarBack, ['aadhaarBackPhoto', 'aadhaarBack', 'aadhaar_back', 'backphoto']);
        const panFrontInput = getFileInput(body.panFrontPhoto || body.panFront, ['panFrontPhoto', 'panFront', 'pan_front']);
        const panBackInput = getFileInput(body.panBackPhoto || body.panBack, ['panBackPhoto', 'panBack', 'pan_back']);

        let certInputs = [];
        const rawCerts = body.certifications || body.certificates || body.certificate;
        if (Array.isArray(rawCerts)) {
            certInputs = rawCerts;
        } else if (rawCerts) {
            certInputs = [rawCerts];
        }
        if (req.files) {
            const certFiles = (Array.isArray(req.files) ? req.files : Object.values(req.files).flat())
                .filter(f => f && f.fieldname && ['certificate', 'certifications', 'certificates'].includes(f.fieldname.toLowerCase()));
            certInputs.push(...certFiles);
        }

        // 1. Process all file and image uploads via sequential uploadQueueManager
        const [
            avatarUrl,
            aadhaarFrontUrl,
            aadhaarBackUrl,
            panFrontUrl,
            panBackUrl,
            uploadedCertUrls
        ] = await Promise.all([
            uploadQueueManager.add(avatarInput, 'gigconnect/avatars'),
            uploadQueueManager.add(aadhaarFrontInput, 'gigconnect/documents'),
            uploadQueueManager.add(aadhaarBackInput, 'gigconnect/documents'),
            uploadQueueManager.add(panFrontInput, 'gigconnect/documents'),
            uploadQueueManager.add(panBackInput, 'gigconnect/documents'),
            Promise.all(certInputs.map(c => uploadQueueManager.add(c, 'gigconnect/certificates')))
        ]);

        const validUploadedCertUrls = (uploadedCertUrls || []).filter(Boolean);

        // 2. Existing Data Retain
        const currentProfile = user.workerProfile ? (typeof user.workerProfile.toObject === 'function' ? user.workerProfile.toObject() : user.workerProfile) : {};
        const existingDocs = currentProfile.identityDocuments || [];
        const existingAadhaar = existingDocs.find(d => d.docType === 'Aadhaar Card') || {};
        const existingPan = existingDocs.find(d => d.docType === 'PAN Card') || {};

        // 3. User Level Updates (Basic Info & Avatar)
        const userUpdates = {};
        if (body.name || body.fullName) userUpdates.name = body.name || body.fullName;
        if (body.phone) userUpdates.phone = body.phone;

        const finalAvatar = avatarUrl || user.avatar || currentProfile.selfieImageUrl || null;
        if (finalAvatar) userUpdates.avatar = finalAvatar;

        if (body.location) {
            if (body.location.coordinates) {
                userUpdates.location = { type: 'Point', coordinates: body.location.coordinates };
            } else if (Array.isArray(body.location)) {
                userUpdates.location = { type: 'Point', coordinates: body.location };
            } else if (typeof body.location === 'object' && body.location.type === 'Point') {
                userUpdates.location = body.location;
            }
        }

        // 4. Category & Rates resolution
        const categoryVal = body.category || currentProfile.category || null;
        let categoriesVal = body.categories || currentProfile.categories || [];
        if (!Array.isArray(categoriesVal)) {
            categoriesVal = typeof categoriesVal === 'string' ? categoriesVal.split(',').map(s => s.trim()).filter(Boolean) : [];
        }
        if (categoryVal && !categoriesVal.includes(categoryVal)) {
            categoriesVal = [categoryVal, ...categoriesVal];
        }

        const inputRate = body.rate || body.hourlyRate;
        const finalRate = inputRate !== undefined ? Number(inputRate) : (currentProfile.rate || 0);

        const resolvedCategoryRates = parseCategoryRates(body.categoryRates, categoryVal || 'General', finalRate) || currentProfile.categoryRates || [];

        let skillsVal = body.skills || currentProfile.skills || [];
        if (!Array.isArray(skillsVal)) {
            skillsVal = typeof skillsVal === 'string' ? skillsVal.split(',').map(s => s.trim()).filter(Boolean) : [];
        }

        let finalCertifications = [...(currentProfile.certifications || [])];
        validUploadedCertUrls.forEach(url => {
            if (url && !finalCertifications.includes(url)) {
                finalCertifications.push(url);
            }
        });

        // 4.5 Resolve Cooperative Society & Regional Federation
        const rawSocietyId = body.societyId || body.society || currentProfile.society || null;
        let finalSocietyId = null;
        let resolvedFederationId = body.federationId || body.federation || user.federation || null;
        let generatedMemberId = body.societyMemberId || currentProfile.societyMemberId || null;
        let workerState = body.state || currentProfile.state || null;
        let workerDistrict = body.district || currentProfile.district || null;

        if (rawSocietyId) {
            try {
                const soc = await CooperativeSociety.findById(rawSocietyId);
                if (soc) {
                    finalSocietyId = soc._id;
                    if (soc.federation) {
                        resolvedFederationId = soc.federation;
                    }
                    if (!workerState && soc.state) workerState = soc.state;
                    if (!workerDistrict && soc.district) workerDistrict = soc.district;
                    if (!generatedMemberId) {
                        const distCode = (soc.district || 'GEN').toUpperCase().slice(0, 3);
                        generatedMemberId = `MEM-${distCode}-${Math.floor(1000 + Math.random() * 9000)}`;
                    }
                    // Sync active member count on society
                    CooperativeSociety.countDocuments({ role: 'worker', 'workerProfile.society': soc._id })
                        .then(cnt => CooperativeSociety.findByIdAndUpdate(soc._id, { activeMembersCount: cnt }))
                        .catch(() => {});
                }
            } catch (err) {
                console.warn('Could not resolve society in updateUserProfile:', err.message);
            }
        }

        if (resolvedFederationId) {
            userUpdates.federation = resolvedFederationId;
        }

        // 5. Build Worker Profile Object with resolved Cloudinary URLs
        userUpdates.workerProfile = {
            ...currentProfile,
            state: workerState,
            district: workerDistrict,
            society: finalSocietyId,
            societyMemberId: generatedMemberId,
            dateOfBirth: body.dateOfBirth || body.dob || currentProfile.dateOfBirth || null,
            gender: body.gender || currentProfile.gender || 'male',
            selfieImageUrl: finalAvatar,
            
            category: categoryVal,
            categories: categoriesVal,
            rate: finalRate,
            hourlyRate: finalRate,
            categoryRates: resolvedCategoryRates,
            experienceYears: body.experienceYears !== undefined ? Number(body.experienceYears) : (currentProfile.experienceYears || 0),
            bio: body.bio || currentProfile.bio || null,
            skills: skillsVal,
            certifications: finalCertifications,
            rating: currentProfile.rating !== undefined ? currentProfile.rating : 0.0,
            totalJobs: currentProfile.totalJobs !== undefined ? currentProfile.totalJobs : 0,
            workAddress: body.workAddress || currentProfile.workAddress || null,
            eshramUan: body.eshramUan || currentProfile.eshramUan || null,
            
            identityDocuments: [
                {
                    docType: 'Aadhaar Card',
                    docNumber: body.aadhaarNumber || existingAadhaar.docNumber || null,
                    frontPhotoUrl: aadhaarFrontUrl || existingAadhaar.frontPhotoUrl || null,
                    backPhotoUrl: aadhaarBackUrl || existingAadhaar.backPhotoUrl || null,
                    status: existingAadhaar.status || 'PENDING'
                },
                {
                    docType: 'PAN Card',
                    docNumber: body.panNumber || existingPan.docNumber || null,
                    frontPhotoUrl: panFrontUrl || existingPan.frontPhotoUrl || null,
                    backPhotoUrl: panBackUrl || existingPan.backPhotoUrl || null,
                    status: existingPan.status || 'PENDING'
                }
            ],

            payoutMethod: body.payoutMethod || currentProfile.payoutMethod || 'bank',
            bank: {
                accountHolderName: body.bank?.accountHolderName || currentProfile.bank?.accountHolderName || null,
                accountNumber: body.bank?.accountNumber || currentProfile.bank?.accountNumber || null,
                ifscCode: body.bank?.ifscCode || currentProfile.bank?.ifscCode || null
            },
            upi: {
                upiId: body.upi?.upiId || (typeof body.upi === 'string' ? body.upi : null) || body.upiId || currentProfile.upi?.upiId || null
            },

            isOnline: currentProfile.isOnline !== undefined ? currentProfile.isOnline : false,
            lastActiveAt: currentProfile.lastActiveAt || null,
            serviceRadiusKm: body.serviceRadiusKm != null
                ? Number(body.serviceRadiusKm)
                : (currentProfile.serviceRadiusKm || 10),
            availabilitySchedule: (body.availabilitySchedule && typeof body.availabilitySchedule === 'object')
                ? {
                    days: Array.isArray(body.availabilitySchedule.days) ? body.availabilitySchedule.days : [],
                    startTime: body.availabilitySchedule.startTime || '09:00',
                    endTime: body.availabilitySchedule.endTime || '18:00',
                }
                : (currentProfile.availabilitySchedule || { days: [], startTime: '09:00', endTime: '18:00' }),
            recentWorkPhotos: Array.isArray(body.recentWorkPhotos)
                ? body.recentWorkPhotos
                : (currentProfile.recentWorkPhotos || []),
            walletBalance: currentProfile.walletBalance || 0,
            totalEarnings: currentProfile.totalEarnings || 0,
            walletTransactions: currentProfile.walletTransactions || []
        };

        // Also sync kycDocuments for Flutter verification/admin compatibility
        userUpdates.kycDocuments = {
            aadhaarNumber: body.aadhaarNumber || existingAadhaar.docNumber || user.kycDocuments?.aadhaarNumber || null,
            aadhaarFrontPhoto: aadhaarFrontUrl || existingAadhaar.frontPhotoUrl || user.kycDocuments?.aadhaarFrontPhoto || null,
            aadhaarBackPhoto: aadhaarBackUrl || existingAadhaar.backPhotoUrl || user.kycDocuments?.aadhaarBackPhoto || null,
            panNumber: body.panNumber || existingPan.docNumber || user.kycDocuments?.panNumber || null,
            panFrontPhoto: panFrontUrl || existingPan.frontPhotoUrl || user.kycDocuments?.panFrontPhoto || null,
            panBackPhoto: panBackUrl || existingPan.backPhotoUrl || user.kycDocuments?.panBackPhoto || null,
            selfieImageUrl: finalAvatar || user.kycDocuments?.selfieImageUrl || null,
            certificateUrl: validUploadedCertUrls[0] || user.kycDocuments?.certificateUrl || null,
            govermentIdType: body.govermentIdType || user.kycDocuments?.govermentIdType || 'Aadhaar Card',
            govermentIdNumber: body.govermentIdNumber || body.aadhaarNumber || user.kycDocuments?.govermentIdNumber || null,
            status: user.kycDocuments?.status === 'approved' ? 'approved' : 'submitted',
            declineReason: user.kycDocuments?.declineReason || null
        };

        // 6. Save in DB
        const updatedUser = await User.findByIdAndUpdate(
            userId,
            { $set: userUpdates },
            { returnDocument: 'after', runValidators: true }
        )
            .populate('workerProfile.society', 'name registrationNumber state district')
            .populate('federation', 'name federationName state district')
            .select('-password');

        // 7. Clear Redis Cache & Sync User Cache
        if (redis) {
            const updatedUserObj = updatedUser.toObject ? updatedUser.toObject() : updatedUser;
            await syncUserCache(updatedUserObj.email, updatedUserObj);
            await redis.del(`user:profile:${userId}`);
            await redis.del(`worker:profile:${userId}`);
        }

        return res.status(200).json({
            success: true,
            message: 'Profile and documents uploaded successfully via queue',
            user: updatedUser
        });

    } catch (error) {
        console.error('Profile Setup Error:', error);
        return res.status(500).json({ success: false, message: error.message });
    }
};

// 5. GOOGLE AUTH
export const googleLogin = async (req, res) => {
    try {
        const { email, name, avatar, role, deviceId, location, phone } = req.body;
        let userDoc = await User.findOne({ email }).select('-password');

        const userRole = role || 'customer';
        if (!userDoc) {
            userDoc = await User.create({
                name,
                email,
                avatar: avatar || null,
                role: userRole,
                authProvider: 'google',
                isEmailVerified: true,
                isVerified: userRole === 'customer', // Customer verified, Worker requires Admin approval
                phone: phone || null,
                location: location || undefined
            });
        }

        const user = userDoc.toObject ? userDoc.toObject() : userDoc;
        delete user.password;

        const tokens = await createSession(user, deviceId);
        await syncUserCache(email, user);

        return res.status(200).json({ success: true, user, ...tokens });
    } catch (error) {
        console.error('Google Auth Error:', error);
        return res.status(500).json({ success: false, message: 'Google Auth Failed' });
    }
};

// 6. REFRESH TOKEN (WITH ROTATION: Returns new access and refresh tokens, updates session in Redis)
export const refreshToken = async (req, res) => {
    // #swagger.tags = ['Auth']
    // #swagger.parameters['body'] = { in: 'body', description: 'Refresh token session credentials', required: true, schema: { $ref: '#/definitions/RefreshTokenInput' } }
    try {
        const { userId, deviceId, refreshToken } = req.body;

        if (!refreshToken) return res.status(401).json({ success: false, message: 'Refresh Token required' });

        let decoded;
        try {
            decoded = jwt.verify(refreshToken, process.env.REFRESH_SECRET);
        } catch (jwtErr) {
            return res.status(401).json({ success: false, message: 'Invalid or expired refresh token' });
        }

        const effectiveUserId = decoded.id || userId;
        const user = await User.findById(effectiveUserId).select('role activeDeviceId').lean();
        if (!user) return res.status(404).json({ success: false, message: 'User no longer exists' });

        // Check Redis session
        let savedToken = null;
        if (redis && effectiveUserId && deviceId) {
            try {
                savedToken = await redis.get(`session:${effectiveUserId}:${deviceId}`);
            } catch (_) {}
        }

        // If Redis has a record for this device and it does not match, reject (revoked or rotated token replay)
        if (savedToken && savedToken !== refreshToken) {
            return res.status(403).json({ success: false, message: 'Invalid session. Token already rotated or revoked.' });
        }

        // If Redis key missing (e.g. Redis reboot/eviction), enforce single-device check via MongoDB activeDeviceId
        if (!savedToken && user.activeDeviceId && deviceId && user.activeDeviceId !== deviceId) {
            return res.status(403).json({ success: false, message: 'Session expired. Account logged in on another device.' });
        }

        const newAccessToken = jwt.sign(
            { id: effectiveUserId, role: user.role },
            process.env.JWT_SECRET,
            { expiresIn: process.env.JWT_ACCESS_EXPIRY || '15m' }
        );

        const newRefreshToken = jwt.sign(
            { id: effectiveUserId },
            process.env.REFRESH_SECRET,
            { expiresIn: process.env.JWT_REFRESH_EXPIRY || '7d' }
        );

        const sessionTtl = parseInt(process.env.REDIS_SESSION_TTL_SEC, 10) || 7 * 24 * 60 * 60;
        if (redis && deviceId) {
            try {
                const pipeline = redis.pipeline();
                pipeline.set(`user:active-device:${effectiveUserId}`, deviceId, 'EX', sessionTtl);
                pipeline.set(`session:${effectiveUserId}:${deviceId}`, newRefreshToken, 'EX', sessionTtl);
                await pipeline.exec();
            } catch (err) {
                console.warn('Redis sync error during refreshToken:', err.message);
            }
        }

        return res.status(200).json({
            success: true,
            accessToken: newAccessToken,
            refreshToken: newRefreshToken
        });
    } catch (error) {
        console.error('Refresh Token Error:', error);
        return res.status(403).json({ success: false, message: 'Invalid session' });
    }
};

// 7. FORGOT PASSWORD
export const forgotPassword = async (req, res) => {
    try {
        const { email } = req.body;
        if (!email) return res.status(400).json({ success: false, message: 'Email is required' });

        const emailNormalized = email.toLowerCase().trim();
        const user = await User.findOne({ email: emailNormalized });

        if (!user) return res.status(404).json({ success: false, message: 'No account found with this email address.' });
        if (user.authProvider === 'google') return res.status(400).json({ success: false, message: 'Google accounts cannot reset password here' });

        const otp = generateOTP();
        const resetOtpExpiry = parseInt(process.env.RESET_OTP_EXPIRY_SEC, 10) || 300;
        await redis.set(`reset_otp:${emailNormalized}`, otp, 'EX', resetOtpExpiry);

        await emailQueue.add('sendOtpEmail', {
            to: emailNormalized,
            subject: 'Password Reset Verification Code',
            html: generateOtpEmailHtml(otp)
        });

        return res.status(200).json({ success: true, message: 'Password reset OTP sent to email' });
    } catch (error) {
        console.error('Forgot Password Error:', error);
        return res.status(500).json({ success: false, message: error.message });
    }
};

// 8. RESET PASSWORD
export const resetPassword = async (req, res) => {
    try {
        const { email, otp, newPassword } = req.body;

        if (!email || !otp || !newPassword) {
            return res.status(400).json({ success: false, message: 'Email, OTP, and new password are required.' });
        }

        const emailNormalized = email.toLowerCase().trim();
        const cachedOtp = await redis.get(`reset_otp:${emailNormalized}`);

        if (!cachedOtp || cachedOtp !== otp.toString()) {
            return res.status(400).json({ success: false, message: 'Invalid or expired OTP' });
        }

        const user = await User.findOne({ email: emailNormalized });
        if (!user) return res.status(404).json({ success: false, message: 'User not found' });

        user.password = newPassword; // Hashed automatically by pre-save hook
        await user.save();

        const pipeline = redis.pipeline();
        pipeline.del(`reset_otp:${emailNormalized}`);
        pipeline.del(`user:email:${emailNormalized}`);
        await pipeline.exec();

        return res.status(200).json({ success: true, message: 'Password reset successful. Please login.' });
    } catch (error) {
        console.error('Reset Password Error:', error);
        return res.status(500).json({ success: false, message: error.message });
    }
};

// 9. LOGOUT
export const logoutUser = async (req, res) => {
    // #swagger.tags = ['Auth']
    // #swagger.parameters['body'] = { in: 'body', description: 'Logout session details', required: true, schema: { $ref: '#/definitions/LogoutInput' } }
    try {
        const { userId, deviceId } = req.body;

        const pipeline = redis.pipeline();
        pipeline.del(`session:${userId}:${deviceId}`);
        pipeline.del(`user:active-device:${userId}`);
        await pipeline.exec();

        // Also reset activeDeviceId in MongoDB upon logout
        await User.findByIdAndUpdate(userId, { activeDeviceId: null });

        return res.status(200).json({ success: true, message: 'Logged out successfully' });
    } catch (error) {
        console.error('Logout Error:', error);
        return res.status(500).json({ success: false, message: error.message });
    }
};