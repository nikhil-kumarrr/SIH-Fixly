import Settings from '../models/Settings.js';
import redis from '../config/redis.js';

const SETTINGS_CACHE_KEY = 'app:platform:settings';

export const getPlatformSettings = async () => {
    try {
        const cached = await redis.get(SETTINGS_CACHE_KEY);
        if (cached) {
            return JSON.parse(cached);
        }
    } catch (_) {
        // Redis not reachable or bypassed
    }

    let settings = await Settings.findOne().lean();
    if (!settings) {
        settings = await Settings.create({
            customerPlatformFee: 0,
            workerCommissionPercent: 0,
            cooperativeWelfarePercent: 0,
            workerSearchRadiusKm: 10,
            defaultLaborRatePerHour: 50,
            emergencySurchargePercent: 20,
            emergencySurchargeFixed: 50,
            autoDispatchEnabled: true,
            emergencyHotline: '+91 98765 43210',
            emailNotifications: true,
            smsAlerts: true,
            payoutSchedule: 'Instant Automated UPI',
            twoFactorAuth: false
        });
        if (settings.toObject) settings = settings.toObject();
    }

    try {
        await redis.set(SETTINGS_CACHE_KEY, JSON.stringify(settings), 'EX', 3600);
    } catch (_) {}

    return settings;
};

export const clearSettingsCache = async (newSettings = null) => {
    try {
        if (newSettings) {
            const val = newSettings.toObject ? newSettings.toObject() : newSettings;
            await redis.set(SETTINGS_CACHE_KEY, JSON.stringify(val), 'EX', 3600);
        } else {
            await redis.del(SETTINGS_CACHE_KEY);
        }
    } catch (_) {}
};
