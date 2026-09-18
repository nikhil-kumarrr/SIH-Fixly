import WorkerCertificate from '../models/WorkerCertificate.js';
import User from '../models/User.js';
import { fail, ok, isObjectId } from '../utils/http.js';
import { notifyUser, safeNotify } from '../services/notificationService.js';
import { extractTextFromImageURL } from '../utils/geminiVisionClient.js';
import { getFuzzyMatchRatio } from '../utils/stringUtils.js';
import { syncWorkerToRedis } from '../utils/homeCache.js';

export const createCertificate = async (req, res) => {
    try {
        if (req.user.role !== 'worker') return fail(res, 403, 'FORBIDDEN', 'Worker role required');
        const { serviceCategory, certificateType, certificateNumber, fileUrl, issuer, issuedOn, expiresOn } = req.body || {};
        if (!certificateType || !fileUrl) {
            return fail(res, 400, 'VALIDATION_ERROR', 'certificateType and fileUrl required');
        }

        // LLM Name Extraction & Fuzzy Match
        const extractedText = await extractTextFromImageURL(
            fileUrl,
            "Extract ONLY the full name of the person this certificate is issued to. Return nothing else."
        );
        
        const extractedName = extractedText.trim();
        const matchRatio = getFuzzyMatchRatio(extractedName, req.user.name || '');
        
        // If match ratio is too low, reject
        if (extractedName && matchRatio < 0.6) { // arbitrary threshold 0.6
            return fail(res, 400, 'NAME_MISMATCH', 'The name on the certificate does not match the registered user name.');
        }

        const cert = await WorkerCertificate.create({
            worker: req.user.id,
            serviceCategory: serviceCategory || null,
            certificateType,
            certificateNumber: certificateNumber || null,
            fileUrl,
            issuer: issuer || null,
            issuedOn: issuedOn || null,
            expiresOn: expiresOn || null,
            status: 'submitted',
        });
        return ok(res, { data: cert }, 201);
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

export const listMyCertificates = async (req, res) => {
    try {
        const items = await WorkerCertificate.find({ worker: req.user.id }).sort({ createdAt: -1 });
        return ok(res, { data: items });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

export const getCertificate = async (req, res) => {
    try {
        const item = await WorkerCertificate.findOne({ _id: req.params.id, worker: req.user.id });
        if (!item) return fail(res, 404, 'NOT_FOUND', 'Certificate not found');
        return ok(res, { data: item });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

export const deleteCertificate = async (req, res) => {
    try {
        const item = await WorkerCertificate.findOneAndDelete({ _id: req.params.id, worker: req.user.id });
        if (!item) return fail(res, 404, 'NOT_FOUND', 'Certificate not found');
        return ok(res, { data: { deleted: true } });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

export const adminListCertificates = async (req, res) => {
    try {
        if (!isObjectId(req.params.workerId)) return fail(res, 400, 'VALIDATION_ERROR', 'Invalid worker id');
        const items = await WorkerCertificate.find({ worker: req.params.workerId }).sort({ createdAt: -1 });
        return ok(res, { data: items });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

export const adminReviewCertificate = async (req, res) => {
    try {
        const { status, reviewNote } = req.body || {};
        const allowed = ['pending', 'submitted', 'approved', 'rejected'];
        if (!allowed.includes(status)) return fail(res, 400, 'VALIDATION_ERROR', 'Invalid status');
        const item = await WorkerCertificate.findOne({
            _id: req.params.certificateId,
            worker: req.params.workerId,
        });
        if (!item) return fail(res, 404, 'NOT_FOUND', 'Certificate not found');
        item.status = status;
        item.reviewNote = reviewNote || null;
        await item.save();
        if (status === 'approved' || status === 'rejected') {
            safeNotify(() => notifyUser({
                recipient: item.worker,
                eventType: status === 'approved' ? 'CERTIFICATE_APPROVED' : 'CERTIFICATE_REJECTED',
                entityId: item._id,
                dedupeKey: `CERTIFICATE_${status.toUpperCase()}:${item._id}`,
            }));
        }
        return ok(res, { data: item });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

export const adminGetWorkerVerification = async (req, res) => {
    try {
        const worker = await User.findById(req.params.id).select('name role isVerified kycDocuments');
        if (!worker || worker.role !== 'worker') return fail(res, 404, 'NOT_FOUND', 'Worker not found');
        return ok(res, { data: { worker, kycDocuments: worker.kycDocuments } });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

export const adminReviewWorkerVerification = async (req, res) => {
    try {
        const { status, declineReason } = req.body || {};
        const allowed = ['pending', 'submitted', 'approved', 'rejected'];
        if (!allowed.includes(status)) return fail(res, 400, 'VALIDATION_ERROR', 'Invalid status');
        const worker = await User.findById(req.params.id);
        if (!worker || worker.role !== 'worker') return fail(res, 404, 'NOT_FOUND', 'Worker not found');
        worker.kycDocuments = worker.kycDocuments || {};
        worker.kycDocuments.status = status === 'pending' ? 'none' : status;
        worker.kycDocuments.declineReason = status === 'rejected' ? (declineReason || 'Rejected') : null;
        worker.isVerified = status === 'approved';
        await worker.save();
        if (status === 'approved' || status === 'rejected') {
            safeNotify(() => notifyUser({
                recipient: worker._id,
                eventType: status === 'approved' ? 'KYC_APPROVED' : 'KYC_REJECTED',
                entityId: worker._id,
                dedupeKey: `KYC_${status.toUpperCase()}:${worker._id}:${worker.kycDocuments?.updatedAt || Date.now()}`,
            }));
        }

        // Instantly synchronize worker profile and cache in Redis
        await syncWorkerToRedis(worker._id, worker);

        // Broadcast real-time event to mobile apps and admin panels
        const io = req.app?.get('io');
        if (io) {
            io.emit('worker:verification_updated', {
                workerId: worker._id,
                status: worker.kycDocuments.status,
                isVerified: worker.isVerified
            });
            io.emit('worker:updated', { worker });
        }

        return ok(res, { data: { status: worker.kycDocuments.status, isVerified: worker.isVerified } });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};
