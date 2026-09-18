import User from '../models/User.js';
import { authorize } from '../middleware/authMiddleware.js';
import { fail, ok, maskId } from '../utils/http.js';

export const requireRole = authorize;

const workerOnly = (req, res) => {
    if (req.user?.role !== 'worker') {
        fail(res, 403, 'FORBIDDEN', 'Worker role required');
        return false;
    }
    return true;
};

const mapStatus = (kyc = {}) => {
    const raw = (kyc.status || 'none').toLowerCase();
    if (raw === 'none') return 'pending';
    return raw;
};

export const submitVerification = async (req, res) => {
    try {
        if (!workerOnly(req, res)) return;
        const {
            governmentIdType,
            governmentIdNumber,
            governmentIdFrontUrl,
            governmentIdBackUrl,
            selfieImageUrl,
            additionalDocuments = [],
        } = req.body || {};

        if (!governmentIdType || !governmentIdNumber || !governmentIdFrontUrl || !selfieImageUrl) {
            return fail(res, 400, 'VALIDATION_ERROR', 'Required verification fields missing');
        }

        const duplicateUser = await User.findOne({
            _id: { $ne: req.user.id },
            $or: [
                { 'kycDocuments.aadhaarNumber': governmentIdNumber },
                { 'kycDocuments.panNumber': governmentIdNumber },
                { 'kycDocuments.govermentIdNumber': governmentIdNumber },
                { 'workerProfile.identityDocuments.docNumber': governmentIdNumber }
            ]
        });

        if (duplicateUser) {
            return fail(res, 409, 'DUPLICATE_DOCUMENT', `This ${governmentIdType} is already registered with another account`);
        }

        const user = await User.findById(req.user.id);
        if (!user) return fail(res, 404, 'NOT_FOUND', 'User not found');

        user.kycDocuments = {
            ...(user.kycDocuments?.toObject?.() || user.kycDocuments || {}),
            govermentIdType: governmentIdType,
            govermentIdNumber: governmentIdNumber,
            aadhaarFrontPhoto: governmentIdFrontUrl,
            aadhaarBackPhoto: governmentIdBackUrl || null,
            selfieImageUrl,
            status: 'PROCESSING',
            declineReason: null,
            manualReviewReason: null,
        };
        await user.save();

        const isAiVerifyEnabled = String(process.env.AI_VERIFY_ENABLED ?? process.env.ENABLE_AI_VERIFY ?? 'false').toLowerCase() === 'true';

        let aiResult = null;
        if (isAiVerifyEnabled) {
            try {
                const rawUrl = process.env.IDENTITY_VERIFY_URL || process.env.AI_VERIFY_URL || 'http://127.0.0.1:8004';
                const verifyUrl = rawUrl.replace(/\/verify\/?$/, '').replace(/\/$/, '');
                const aiRes = await fetch(`${verifyUrl}/verify`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ documentUrl: governmentIdFrontUrl, selfieUrl: selfieImageUrl })
                });
                if (aiRes.ok) {
                    aiResult = await aiRes.json();
                }
            } catch (err) {
                console.error('AI KYC Service failed:', err.message);
            }
        } else {
            console.log('[KYC Verification] AI verification is disabled via ENV (AI_VERIFY_ENABLED=false). Routed directly to manual admin review.');
        }

        let newStatus = 'MANUAL_REVIEW';
        let reason = isAiVerifyEnabled ? 'AI service unavailable or failed' : 'Pending manual admin verification';
        
        if (aiResult && aiResult.success) {
            user.kycDocuments.livenessScore = aiResult.selfie.livenessScore;
            user.kycDocuments.faceMatchScore = aiResult.faceMatch.score;
            user.kycDocuments.documentFaceDetected = aiResult.document.faceDetected;
            user.kycDocuments.selfieFaceDetected = aiResult.selfie.faceDetected;

            const livenessPassed = aiResult.selfie.livenessPassed;
            const faceMatch = aiResult.faceMatch.score;

            if (!livenessPassed) {
                newStatus = 'REJECTED';
                reason = 'Liveness check failed';
            } else if (!aiResult.document.faceDetected) {
                newStatus = 'MANUAL_REVIEW';
                reason = 'Document face missing';
            } else if (faceMatch >= 85) {
                newStatus = 'APPROVED';
                reason = 'High AI confidence';
            } else if (faceMatch >= 40) {
                newStatus = 'MANUAL_REVIEW';
                reason = 'Moderate AI confidence';
            } else {
                newStatus = 'REJECTED';
                reason = 'Low AI face match score';
            }
        }

        user.kycDocuments.status = newStatus;
        if (newStatus === 'APPROVED') {
            user.isVerified = true;
        } else if (newStatus === 'REJECTED') {
            user.kycDocuments.declineReason = reason;
        } else if (newStatus === 'MANUAL_REVIEW') {
            user.kycDocuments.manualReviewReason = reason;
        }
        await user.save();

        const VerificationAuditLog = (await import('../models/VerificationAuditLog.js')).default;
        await VerificationAuditLog.create({
            workerId: user._id,
            action: 'AI_EVALUATED',
            actorType: 'AI',
            oldStatus: 'PROCESSING',
            newStatus,
            reason,
            metadata: aiResult || {}
        });

        return ok(res, {
            verification: {
                status: newStatus,
                message: reason,
                submittedAt: new Date().toISOString(),
            },
        });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

export const getMyVerification = async (req, res) => {
    try {
        if (!workerOnly(req, res)) return;
        const user = await User.findById(req.user.id).select('kycDocuments isVerified workerProfile');
        if (!user) return fail(res, 404, 'NOT_FOUND', 'User not found');
        const kyc = user.kycDocuments || {};
        const status = user.isVerified ? 'approved' : mapStatus(kyc);
        const hasSelfie = Boolean(kyc.selfieImageUrl);
        const hasId = Boolean(kyc.aadhaarFrontPhoto || kyc.govermentIdNumber);
        return ok(res, {
            verification: {
                status,
                identity: hasId ? (status === 'approved' ? 'approved' : 'submitted') : 'pending',
                selfie: hasSelfie ? (status === 'approved' ? 'approved' : 'submitted') : 'pending',
                certificates: 'pending',
                declineReason: kyc.declineReason || null,
                lastUpdatedAt: user.updatedAt,
                governmentIdType: kyc.govermentIdType || null,
                governmentIdNumber: maskId(kyc.govermentIdNumber || kyc.aadhaarNumber),
            },
        });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

export const resubmitVerification = async (req, res) => {
    try {
        if (!workerOnly(req, res)) return;
        const user = await User.findById(req.user.id);
        if (!user) return fail(res, 404, 'NOT_FOUND', 'User not found');
        const status = mapStatus(user.kycDocuments);
        if (status !== 'rejected') {
            return fail(res, 400, 'VALIDATION_ERROR', 'Resubmit allowed only after rejection');
        }
        req.body = req.body || {};
        return submitVerification(req, res);
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};
