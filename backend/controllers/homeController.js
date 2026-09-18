import dotenv from 'dotenv';
dotenv.config();

import redis from '../config/redis.js';
import Service from '../models/Service.js';
import Banner from '../models/Banner.js';
import { uploadToCloudinary } from '../utils/cloudinary.js';
import { getRequestLanguage, localizeServices, localizeService, localizeCategories } from '../utils/i18nHelper.js';
import { invalidateHomeCache } from '../utils/homeCache.js';

// Screen 1: Home Dashboard Data (Redis Cached per language)
export const getHomeData = async (req, res) => {
    try {
        const lang = getRequestLanguage(req);
        const cacheKey = `app:home:dashboard:${lang}`;
        const cachedData = await redis.get(cacheKey);

        if (cachedData) {
            return res.status(200).json({ success: true, source: 'cache', data: JSON.parse(cachedData) });
        }

        const limit = parseInt(process.env.HOME_SERVICES_LIMIT, 10) || 6;
        const ttl = parseInt(process.env.CACHE_TTL_HOME, 10) || 3600;

        const rawCategories = await Service.distinct('category');
        const rawTopServices = await Service.find({ isActive: true }).limit(limit).lean();
        const banners = await Banner.find({ isActive: true }).sort({ priority: -1, createdAt: -1 }).lean();

        const topServices = await localizeServices(rawTopServices, lang);
        const categories = localizeCategories(rawCategories, lang);

        const responsePayload = {
            categories,
            rawCategories,
            topServices,
            banners,
            featuredOffers: banners,
        };

        await redis.set(cacheKey, JSON.stringify(responsePayload), 'EX', ttl);

        return res.status(200).json({ success: true, source: 'db', data: responsePayload });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

// Screen 2: All Categories & Sub-Services (Redis Cached per language)
export const getCategories = async (req, res) => {
    try {
        const lang = getRequestLanguage(req);
        const cacheKey = `app:services:categories:${lang}`;
        let cachedData = await redis.get(cacheKey);
        if (!cachedData && (lang === 'en' || !lang)) {
            cachedData = await redis.get('app:services:categories');
        }

        if (cachedData) {
            return res.status(200).json({ success: true, source: 'cache', categories: JSON.parse(cachedData) });
        }

        const ttl = parseInt(process.env.CACHE_TTL_CATEGORIES, 10) || 86400;

        const rawServices = await Service.find({ isActive: true }).lean();
        const services = await localizeServices(rawServices, lang);

        const groupedCategories = services.reduce((acc, service) => {
            const catKey = service.category;
            acc[catKey] = acc[catKey] || [];
            acc[catKey].push(service);
            return acc;
        }, {});

        try {
            await redis.set(cacheKey, JSON.stringify(groupedCategories), 'EX', ttl);
        } catch (redisErr) {
            console.warn('Redis SET error for categories in homeController:', redisErr.message);
        }

        return res.status(200).json({ success: true, source: 'db', categories: groupedCategories });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

// Screen 3: Service Pricing & Details (Localized)
export const getServiceDetails = async (req, res) => {
    try {
        const { serviceId } = req.params;
        const lang = getRequestLanguage(req);
        const cacheKey = `service:details:${serviceId}:${lang}`;

        const cachedService = await redis.get(cacheKey);
        if (cachedService) {
            return res.status(200).json({ success: true, service: JSON.parse(cachedService) });
        }

        const ttl = parseInt(process.env.CACHE_TTL_SERVICE_DETAILS, 10) || 1800;

        const rawService = await Service.findById(serviceId).lean();
        if (!rawService) return res.status(404).json({ success: false, message: 'Service not found' });

        const service = await localizeService(rawService, lang);

        await redis.set(cacheKey, JSON.stringify(service), 'EX', ttl);

        return res.status(200).json({ success: true, service });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

export const getExtraPartsCatalog = async (req, res) => {
    try {
        // Yahan extra parts ka catalog fetch karne ka logic likhein
        res.status(200).json({
            success: true,
            message: 'Extra parts catalog fetched successfully',
            data: []
        });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

// POST: Create New Category (Accepts all schema fields from frontend)
export const createCategory = async (req, res) => {
    try {
        const { title, category, basePrice, estimatedTime, whatsIncluded } = req.body;

        if (!title || !category || !basePrice) {
            return res.status(400).json({ success: false, message: 'Title, category, and base price are required.' });
        }

        if (!req.file) {
            return res.status(400).json({ success: false, message: 'Category image file is required.' });
        }

        // Upload image buffer to Cloudinary
        const uploadResult = await uploadToCloudinary(req.file.buffer);
        const imageUrl = uploadResult.secure_url;

        // Parse whatsIncluded list
        let whatsIncludedArray = [];
        if (whatsIncluded) {
            if (Array.isArray(whatsIncluded)) {
                whatsIncludedArray = whatsIncluded;
            } else {
                whatsIncludedArray = whatsIncluded.split(',').map(item => item.trim());
            }
        }

        // Create a service entry matching the schema
        const newService = await Service.create({
            title,
            category: category.toLowerCase().trim(),
            image: imageUrl,
            basePrice: parseFloat(basePrice),
            estimatedTime: estimatedTime || '1 Hour',
            whatsIncluded: whatsIncludedArray
        });

        // 24 Hours Cache Mechanism: Push new category if cache exists, otherwise clear key
        const categoriesCacheKey = 'app:services:categories';
        try {
            const cachedData = await redis.get(categoriesCacheKey);
            if (cachedData) {
                const groupedCategories = JSON.parse(cachedData);
                const catKey = newService.category;

                if (!groupedCategories[catKey]) {
                    groupedCategories[catKey] = [];
                }
                const serviceObj = newService.toObject ? newService.toObject() : newService;
                groupedCategories[catKey].push(serviceObj);

                const remainingTtl = await redis.ttl(categoriesCacheKey);
                const ttl = remainingTtl > 0 ? remainingTtl : (parseInt(process.env.CACHE_TTL_CATEGORIES, 10) || 86400);

                await redis.set(categoriesCacheKey, JSON.stringify(groupedCategories), 'EX', ttl);
            } else {
                await redis.del(categoriesCacheKey);
            }
        } catch (cacheErr) {
            console.error('Redis cache update error in createCategory:', cacheErr.message);
            try {
                await redis.del(categoriesCacheKey);
            } catch (_) {}
        }

        // Clear dashboard cache (keys are app:home:dashboard:{lang})
        try {
            await invalidateHomeCache();
        } catch (_) {}

        return res.status(201).json({
            success: true,
            message: 'Category created successfully',
            service: newService
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};