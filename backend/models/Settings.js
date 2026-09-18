import mongoose from 'mongoose';

const settingsSchema = new mongoose.Schema({
    // Dynamic Customer & Worker Margins (Customizable from Admin Panel)
    customerPlatformFee: { type: Number, default: 0 }, // ₹ amount charged to customer on booking (if 0, ₹0)
    workerCommissionPercent: { type: Number, default: 0 }, // % margin deducted from worker earnings (if 0, 0% deducted)
    cooperativeWelfarePercent: { type: Number, default: 0 }, // % welfare contribution deducted from worker (if 0, 0% deducted)
    platformCommissionPercent: { type: Number, default: 0 }, // Backward compatibility alias
    
    // Dynamic Operation Parameters (No hardcoded process.env fallbacks)
    workerSearchRadiusKm: { type: Number, default: 15 },
    serviceRadiusKm: { type: Number, default: 15 },
    defaultLaborRatePerHour: { type: Number, default: 50 },
    defaultLaborRatePerBooking: { type: Number, default: 50 },
    emergencySurchargePercent: { type: Number, default: 20 },
    emergencySurchargeFixed: { type: Number, default: 50 },

    autoDispatchEnabled: { type: Boolean, default: true },
    emergencyHotline: { type: String, default: '+91 98765 43210' },
    emailNotifications: { type: Boolean, default: true },
    smsAlerts: { type: Boolean, default: true },
    payoutSchedule: { type: String, default: 'Instant Automated UPI' },
    twoFactorAuth: { type: Boolean, default: false },
    enabledLanguages: {
        type: [String],
        default: ['en', 'hi', 'ta', 'te', 'kn', 'bn', 'mr', 'gu'],
        enum: ['en', 'hi', 'ta', 'te', 'kn', 'bn', 'mr', 'gu']
    },
    apiKeys: {
        groqApiKey: { type: String, default: '' },
        geminiApiKey: { type: String, default: '' },
        cloudinaryUrl: { type: String, default: '' },
        fixlySupportNumber: { type: String, default: '1800-123-4567' }
    }
}, { timestamps: true });

export default mongoose.model('Settings', settingsSchema);
