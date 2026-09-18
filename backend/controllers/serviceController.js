import Service from '../models/Service.js';
import { uploadToCloudinary } from '../utils/cloudinary.js';
import redis from '../config/redis.js';
import { getRequestLanguage, localizeServices, localizeService } from '../utils/i18nHelper.js';
import { invalidateHomeCache, syncServiceToRedis } from '../utils/homeCache.js';

// 1. Create New Service / Category (Uses Multer + Cloudinary)
export const createService = async (req, res) => {
    try {
        const { title, category, basePrice, estimatedTime, whatsIncluded } = req.body;

        if (!title || !category || !basePrice) {
            return res.status(400).json({ success: false, message: 'Title, category, and base price are required.' });
        }

        if (!req.file) {
            return res.status(400).json({ success: false, message: 'Service image upload is required.' });
        }

        // Upload to Cloudinary using utility helper
        const uploadResult = await uploadToCloudinary(req.file.buffer);
        const imageUrl = uploadResult.secure_url;

        // Parse whatsIncluded list safely (supports string or array)
        let whatsIncludedArray = [];
        if (whatsIncluded) {
            if (Array.isArray(whatsIncluded)) {
                whatsIncludedArray = whatsIncluded;
            } else {
                whatsIncludedArray = whatsIncluded.split(',').map(item => item.trim());
            }
        }

        const cleanCategory = (category || '').toString().toLowerCase().trim();
        const cleanTitle = (title || '').toString().toLowerCase().trim();

        const newService = await Service.create({
            title: cleanTitle,
            category: cleanCategory,
            image: imageUrl,
            basePrice: parseFloat(basePrice),
            estimatedTime: estimatedTime || '1 Hour',
            whatsIncluded: whatsIncludedArray
        });

        // Direct Redis Push: Synchronize categories & services directly to Redis cache
        await syncServiceToRedis(newService);

        // Realtime Socket Broadcast
        const io = req.app.get('io');
        if (io) {
            io.emit('category:created', { category: newService.category, service: newService });
            io.emit('services:updated', { action: 'created', service: newService });
        }

        return res.status(201).json({
            success: true,
            message: 'Service/Category created successfully and pushed to Redis cache',
            service: newService
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

// 2. Search Services (Localized)
export const searchServices = async (req, res) => {
    try {
        const { query } = req.query;
        if (!query) {
            return res.status(400).json({ success: false, message: 'Search query string is required' });
        }

        const lang = getRequestLanguage(req);
        const rawServices = await Service.find({
            isActive: true,
            $or: [
                { title: { $regex: query, $options: 'i' } },
                { category: { $regex: query, $options: 'i' } }
            ]
        }).sort({ createdAt: 1, _id: 1 }).lean();

        const services = await localizeServices(rawServices, lang);

        return res.status(200).json({ success: true, services });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

// 3. Get All Categories (Grouped - 24 Hours Redis Cache per language)
export const getCategories = async (req, res) => {
    // #swagger.tags = ['Services']
    try {
        const lang = getRequestLanguage(req);
        const cacheKey = `app:services:categories:${lang}`;
        let cachedData = null;

        // Redis cache check
        try {
            cachedData = await redis.get(cacheKey);
            if (!cachedData && (lang === 'en' || !lang)) {
                cachedData = await redis.get('app:services:categories');
            }
        } catch (redisErr) {
            console.warn('Redis GET error for categories:', redisErr.message);
        }

        if (cachedData) {
            return res.status(200).json({
                success: true,
                source: 'cache',
                categories: JSON.parse(cachedData)
            });
        }

        // Cache miss: Hit DB directly one time sorted by creation order (stable sequence)
        const rawServices = await Service.find({ isActive: true }).sort({ createdAt: 1, _id: 1 }).lean();
        const services = await localizeServices(rawServices, lang);
        const groupedCategories = services.reduce((acc, service) => {
            const catKey = (service.category || 'general').toString().toLowerCase().trim();
            acc[catKey] = acc[catKey] || [];
            acc[catKey].push(service);
            return acc;
        }, {});

        // 24 Hours Cache TTL (86400 seconds)
        const ttl = parseInt(process.env.CACHE_TTL_CATEGORIES, 10) || 86400;

        try {
            await redis.set(cacheKey, JSON.stringify(groupedCategories), 'EX', ttl);
        } catch (redisErr) {
            console.warn('Redis SET error for categories:', redisErr.message);
        }

        return res.status(200).json({
            success: true,
            source: 'db',
            categories: groupedCategories
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

// 4. Get Service Details
export const getServiceDetails = async (req, res) => {
    // #swagger.tags = ['Services']
    try {
        const { serviceId } = req.params;
        const cacheKey = `service:details:${serviceId}`;

        const cachedService = await redis.get(cacheKey);
        if (cachedService) {
            return res.status(200).json({ success: true, source: 'cache', service: JSON.parse(cachedService) });
        }

        const service = await Service.findById(serviceId).lean();
        if (!service) return res.status(404).json({ success: false, message: 'Service details not found' });

        const ttl = parseInt(process.env.CACHE_TTL_SERVICE_DETAILS, 10) || 1800;
        await redis.set(cacheKey, JSON.stringify(service), 'EX', ttl);

        return res.status(200).json({ success: true, source: 'db', service });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

// 5. Extra Parts Catalog
export const getExtraPartsCatalog = async (req, res) => {
    try {
        const mockParts = [
            { id: 'part_1', title: 'U-bend Pipe Replacement', price: 25 },
            { id: 'part_2', title: 'Extra Gasket Seals', price: 5 },
            { id: 'part_3', title: 'Disposal Cleaning Fluid', price: 15 },
            { id: 'part_4', title: 'PVC Connection Adapter', price: 10 }
        ];
        return res.status(200).json({ success: true, catalog: mockParts });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};