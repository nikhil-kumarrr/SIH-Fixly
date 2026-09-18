import express from 'express';
import jwt from 'jsonwebtoken';
import upload from '../middleware/uploadMiddleware.js';
import {
} from "../controllers/emergencyController.js";
import {
    adminLogin,
    getAdminProfile,
    updateAdminMe,
    getDashboardStats,
    getCustomers,
    getCustomerById,
    toggleCustomerStatus,
    getWorkers,
    getWorkerById,
    updateWorkerById,
    updateWorkerStatus,
    addWorker,
    getBookings,
    getBookingById,
    assignWorkerToBooking,
    updateBookingStatus,
    getServices,
    getAdminCategories,
    createCategory,
    createService,
    updateService,
    deleteService,
    getPayments,
    getPaymentStats,
    getReviews,
    deleteReview,
    sendAdminNotification,
    getNotifications,
    markAllNotificationsRead,
    deleteNotification,
    getAnalytics,
    getAIInsights,
    uploadAdminFile,
    getReportsData,
    getSettings,
    updateSettings,
    getEnabledLanguages,
    updateEnabledLanguages,
    getAllFederations,
    createFederation,
    impersonateFederation,
    getFederationDetails,
    approveFederation,
    suspendFederation,
    createWelfareResource,
    updateWelfareResource,
    deleteWelfareResource,
    getWelfareResourcesAdmin,
    syncServicesCacheAdmin
} from '../controllers/adminController.js';
import {
    adminGetWorkerVerification,
    adminReviewWorkerVerification,
    adminListCertificates,

    adminReviewCertificate,
} from '../controllers/workerCertificateController.js';
import {
    getAppVersionAdmin,
    updateAppVersion,
    clearRedisCache
} from '../controllers/appVersionController.js';

import {
    getAllEmergencyContacts,
    createEmergencyContact,
    updateEmergencyContact,
    deleteEmergencyContact,
} from '../controllers/emergencyController.js';

import {
    adminListTickets,
    getTicket,
    adminPatchTicket,
    addTicketMessage,
    adminTakeoverTicket,
} from '../controllers/supportController.js';

import {
    adminGetCooperative,
    adminUpdateCooperative,
    adminCooperativeMembers,
    adminCreateSociety,
    adminUpdateSociety,
    adminAssignWorkerToSociety,
    listSocieties,
    getSocietyById,
} from '../controllers/cooperativeController.js';
import { adminWelfareSummary } from '../controllers/welfareController.js';
import { adminListPayouts, adminUpdatePayoutStatus } from '../controllers/workerWalletController.js';
import {
    adminGetBanners,
    adminCreateBanner,
    adminUpdateBanner,
    adminDeleteBanner
} from '../controllers/bannerController.js';
import { getDemandForecast } from '../controllers/demandForecastController.js';

const router = express.Router();

// ==========================================
// ADMIN AUTH MIDDLEWARE
// ==========================================
export const adminProtect = (req, res, next) => {
    try {
        let token;
        if (req.headers.authorization && req.headers.authorization.startsWith('Bearer')) {
            token = req.headers.authorization.split(' ')[1];
        }

        if (!token) {
            return res.status(401).json({ success: false, message: 'Admin authentication required, token missing' });
        }

        const decoded = jwt.verify(token, process.env.JWT_SECRET);
        if (decoded.role !== 'admin') {
            return res.status(403).json({ success: false, message: 'Forbidden. Access restricted to admin users.' });
        }

        req.user = decoded;
        next();
    } catch (error) {
        if (error.name === 'TokenExpiredError') {
            return res.status(401).json({ success: false, message: 'Admin token expired, please login again' });
        }
        return res.status(401).json({ success: false, message: 'Invalid admin authentication token' });
    }
};

// ==========================================
// PUBLIC ADMIN ROUTES
// ==========================================
router.post('/login', adminLogin);

// ==========================================
// PROTECTED ADMIN ROUTES
// ==========================================
router.use(adminProtect);

import { federationScope } from '../middleware/federationMiddleware.js';

/** Super-admin-only gate (after adminProtect). */
export const requireSuperAdmin = (req, res, next) => {
    if (req.user?.adminRole !== 'super_admin') {
        return res.status(403).json({ success: false, message: 'Super Admin access required' });
    }
    next();
};

// Profile & Dashboard
router.get('/me', getAdminProfile);
router.put('/me', updateAdminMe);

// Mount federationScope for data routes
router.use(['/dashboard', '/customers', '/workers', '/bookings', '/analytics', '/reports', '/payments', '/reviews', '/support'], federationScope);

router.get('/dashboard', getDashboardStats);

// Customers
router.get('/customers', getCustomers);
router.get('/customers/:id', getCustomerById);
router.patch('/customers/:id/status', toggleCustomerStatus);

// Workers
router.get('/workers', getWorkers);
router.get('/workers/:id', getWorkerById);
router.post('/workers', addWorker);
router.put('/workers/:id', updateWorkerById);
router.patch('/workers/:id/status', updateWorkerStatus);

// Bookings (supports both :id and :bookingId)
router.get('/bookings', getBookings);
router.get('/bookings/:id', getBookingById);
router.patch('/bookings/:id/assign', assignWorkerToBooking);
router.patch('/bookings/:id/status', updateBookingStatus);
router.patch('/bookings/:bookingId/assign', assignWorkerToBooking);
router.patch('/bookings/:bookingId/status', updateBookingStatus);

// Categories & Services Management with Image Upload & Redis Push
const uploadCategoryMedia = (req, res, next) => {
    upload.fields([{ name: 'image', maxCount: 1 }, { name: 'file', maxCount: 1 }])(req, res, (err) => {
        if (err) return res.status(400).json({ success: false, message: err.message });
        if (req.files) {
            req.file = req.files['image']?.[0] || req.files['file']?.[0] || null;
        }
        next();
    });
};

router.get('/categories', getAdminCategories);
router.post('/categories', uploadCategoryMedia, createCategory);
router.get('/services', getServices);
router.post('/services', uploadCategoryMedia, createService);
router.put('/services/:id', updateService);
router.delete('/services/:id', deleteService);
router.post('/services/sync-cache', syncServicesCacheAdmin);
router.post('/cache/sync', syncServicesCacheAdmin);
router.post('/upload', upload.single('file'), uploadAdminFile);

// Payments & Financials
router.get('/payments', getPayments);
router.get('/payments/stats', getPaymentStats);

// Reviews Moderation
router.get('/reviews', getReviews);
router.delete('/reviews/:id', deleteReview);

// Notifications & Broadcast
router.get('/notifications', getNotifications);
router.post('/notifications/broadcast', sendAdminNotification);
router.put('/notifications/mark-read', markAllNotificationsRead);
router.delete('/notifications/:id', deleteNotification);

// Analytics & AI Insights
router.get('/analytics', getAnalytics);
router.get('/ai-insights', getAIInsights);
router.get('/ai/demand-forecast', getDemandForecast);
router.get('/reports', getReportsData);

// Platform Governance Settings
router.get('/settings', getSettings);
router.put('/settings', updateSettings);
router.get('/settings/languages', getEnabledLanguages);
router.put('/settings/languages', updateEnabledLanguages);

// Mobile App Version & Force Update Governance
router.get('/settings/app-version', getAppVersionAdmin);
router.put('/settings/app-version', updateAppVersion);

// Redis Cache Management & Instant Invalidation
router.post('/redis/clear', clearRedisCache);
router.post('/redis/clear/:type', clearRedisCache);
router.delete('/redis/clear', clearRedisCache);
router.delete('/redis/clear/:type', clearRedisCache);
router.post('/redis/flush-all', (req, res) => {
    req.params.type = 'all';
    return clearRedisCache(req, res);
});

// Worker KYC Verification & Certificates
router.get('/workers/:id/verification', adminGetWorkerVerification);
router.patch('/workers/:id/verification', adminReviewWorkerVerification);
router.get('/workers/:workerId/certificates', adminListCertificates);
router.patch('/workers/:workerId/certificates/:certificateId', adminReviewCertificate);

// Support Management
router.get('/support/tickets', adminListTickets);
router.get('/support/tickets/:id', getTicket);
router.patch('/support/tickets/:id', adminPatchTicket);
router.post('/support/tickets/:id/messages', addTicketMessage);
router.post('/support/tickets/:id/takeover', adminTakeoverTicket);

// Cooperative & Welfare Governance
router.get('/cooperative', adminGetCooperative);
router.put('/cooperative', adminUpdateCooperative);
router.get('/cooperative/members', adminCooperativeMembers);
router.get('/cooperative/societies', listSocieties);
router.post('/cooperative/societies', adminCreateSociety);
router.get('/cooperative/societies/:id', getSocietyById);
router.put('/cooperative/societies/:id', adminUpdateSociety);
router.post('/cooperative/assign-worker', adminAssignWorkerToSociety);
router.get('/welfare/summary', adminWelfareSummary);
router.get('/welfare/resources', getWelfareResourcesAdmin);
router.post('/welfare/resources/upload', upload.single('file'), uploadAdminFile);
router.post('/welfare/resources', createWelfareResource);
router.put('/welfare/resources/:id', updateWelfareResource);
router.delete('/welfare/resources/:id', deleteWelfareResource);
router.get('/worker-payouts', adminListPayouts);
router.patch('/worker-payouts/:id/status', adminUpdatePayoutStatus);

// Promotional Coupon Banners Management
router.get('/banners', adminGetBanners);
router.post('/banners', adminCreateBanner);
router.put('/banners/:id', adminUpdateBanner);
router.delete('/banners/:id', adminDeleteBanner);

// Federation Management
router.get('/federations', getAllFederations);
router.post('/federations', requireSuperAdmin, createFederation);
router.post('/federations/:id/impersonate', requireSuperAdmin, impersonateFederation);
router.get('/federations/:id', getFederationDetails);
router.patch('/federations/:id/approve', approveFederation);
router.patch('/federations/:id/suspend', suspendFederation);

// Emergency Contacts
router.get('/emergency/contacts', getAllEmergencyContacts);
router.post('/emergency/contacts', createEmergencyContact);
router.put('/emergency/contacts/:id', updateEmergencyContact);
router.delete('/emergency/contacts/:id', deleteEmergencyContact);

export default router;
