import mongoose from 'mongoose';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';

// 1. Saved Address Schema (Sub-document)
const addressSchema = new mongoose.Schema({
    label: { type: String, enum: ['Home', 'Work', 'Other', 'Apartment', 'Work Base', 'Hub'], default: 'Home' },
    addressLine: { type: String, required: true },
    city: { type: String, required: true },
    pincode: { type: String, required: true },
    location: {
        type: { type: String, enum: ['Point'], default: 'Point' },
        coordinates: { type: [Number], required: true }
    }
});

// Wallet Transaction Schema for Worker
const walletTransactionSchema = new mongoose.Schema({
    transactionId: { type: String },
    bookingId: { type: mongoose.Schema.Types.ObjectId, ref: 'Booking' },
    amount: { type: Number, required: true }, // Net amount credited/debited
    grossAmount: { type: Number, default: 0 }, // Total job amount before deductions
    platformFeeDeducted: { type: Number, default: 0 }, // Platform/fair charges cut
    welfareDeducted: { type: Number, default: 0 }, // Welfare fund contribution cut
    type: { type: String, enum: ['CREDIT', 'DEBIT'], default: 'CREDIT' },
    description: { type: String },
    createdAt: { type: Date, default: Date.now }
}, { _id: true });

// Identity Document Sub-document Schema for Workers
const identityDocumentSchema = new mongoose.Schema({
    docType: { type: String, default: 'Aadhaar Card' }, // Aadhaar Card, PAN Card, Driving License, Voter ID, Passport
    docNumber: { type: String, default: null }, // Unique ID Number
    frontPhotoUrl: { type: String, default: null }, // Front side photo
    backPhotoUrl: { type: String, default: null }, // Back side photo
    status: { type: String, enum: ['PENDING', 'APPROVED', 'REJECTED'], default: 'PENDING' },
    uploadedAt: { type: Date, default: Date.now }
}, { _id: true });

// Bank Details Sub-document Schema for Worker Payout
const bankDetailsSchema = new mongoose.Schema({
    accountHolderName: { type: String, default: null },
    accountNumber: { type: String, default: null },
    ifscCode: { type: String, default: null }
}, { _id: false });

// UPI Details Sub-document Schema for Worker Payout
const upiDetailsSchema = new mongoose.Schema({
    upiId: { type: String, default: null }
}, { _id: false });

// 2. Category Rate Schema (Per-category rate structure)
const categoryRateSchema = new mongoose.Schema({
    category: { type: String, required: true, trim: true },
    rate: { type: Number, required: true, default: 0 }
}, { _id: false });

// 3. Worker Profile Schema (Sub-document)
const workerProfileSchema = new mongoose.Schema({
    // Step 1: Identity & Legal Docs
    dateOfBirth: { type: String, default: null }, // e.g. "1998-05-12"
    gender: { type: String, enum: ['male', 'female', 'other'], default: 'male' },
    selfieImageUrl: { type: String, default: null },
    identityDocuments: { type: [identityDocumentSchema], default: [] }, // Multiple ID Documents Array (Aadhaar & PAN)

    // Step 2: Work Profile & Skills
    category: { type: String, default: null }, // e.g., 'Plumbing' (Primary)
    categories: [{ type: String }], // Array of categories offered
    rate: { type: Number, default: 0 }, // General / Primary minimum service rate
    hourlyRate: { type: Number, default: 0 }, // Hourly rate alias
    categoryRates: [categoryRateSchema], // Individual rate for each category e.g., [{ category: 'Plumbing', rate: 350 }]
    experienceYears: { type: Number, default: 0 },
    bio: { type: String, default: null },
    skills: [{ type: String }],
    certifications: [{ type: String }],
    workAddress: { type: String, default: null },
    rating: { type: Number, default: 0.0 },
    totalJobs: { type: Number, default: 0 },
    recentWorkPhotos: [{ type: String }],
    badges: [{ type: String }], // e.g., 'Background Checked', 'Top Rated'

    // Step 3: Payout & Welfare & Cooperative Society
    state: { type: String, default: null, trim: true },
    district: { type: String, default: null, trim: true },
    society: { type: mongoose.Schema.Types.ObjectId, ref: 'CooperativeSociety', default: null },
    societyMemberId: { type: String, default: null }, // Unique Member ID issued by Primary Labour Cooperative Society
    eshramUan: { type: String, default: null },
    payoutMethod: { type: String, enum: ['bank', 'upi'], default: 'bank' },
    bank: { type: bankDetailsSchema, default: {} },
    upi: { type: upiDetailsSchema, default: {} },

    // Availability & Radius
    isOnline: { type: Boolean, default: false },
    lastActiveAt: { type: Date, default: null },
    serviceRadiusKm: { type: Number, default: 15 },
    availabilitySchedule: {
        days: { type: [Number], default: [] },
        startTime: { type: String, default: '09:00' },
        endTime: { type: String, default: '18:00' },
    },

    // Wallet Balances
    walletBalance: { type: Number, default: 0 },
    totalEarnings: { type: Number, default: 0 },
    walletTransactions: { type: [walletTransactionSchema], default: [] }
}, { _id: false });

// KYC Document Schema for Worker Verification
const kycDocumentSchema = new mongoose.Schema({
    aadhaarNumber: { type: String, default: null },
    aadhaarFrontPhoto: { type: String, default: null },
    aadhaarBackPhoto: { type: String, default: null },
    panNumber: { type: String, default: null },
    panFrontPhoto: { type: String, default: null },
    panBackPhoto: { type: String, default: null },
    selfieImageUrl: { type: String, default: null },
    certificateUrl: { type: String, default: null },
    govermentIdType: { type: String, default: null },
    govermentIdNumber: { type: String, default: null },
    status: {
        type: String,
        default: 'NOT_STARTED'
    },
    livenessScore: { type: Number, default: null },
    faceMatchScore: { type: Number, default: null },
    documentFaceDetected: { type: Boolean, default: null },
    selfieFaceDetected: { type: Boolean, default: null },
    aiDecision: { type: String, default: null },
    // Admin message shown on Flutter verification screen when rejected or manual review requested
    declineReason: { type: String, default: null },
    manualReviewReason: { type: String, default: null },
}, { _id: false });

const userSchema = new mongoose.Schema({
    name: {
        type: String,
        required: [true, 'Please add a name'],
        trim: true
    },
    email: {
        type: String,
        required: [true, 'Please add an email'],
        unique: true,
        match: [
            /^\w+([\.-]?\w+)*@\w+([\.-]?\w+)*(\.\w{2,3})+$/,
            'Please add a valid email'
        ]
    },
    password: {
        type: String,
        select: false, // Default query me password field return nahi hoga
        minlength: 6
    },
    phone: {
        type: String,
        default: null
    },
    avatar: {
        type: String,
        default: null
    },
    role: {
        type: String,
        enum: ['customer', 'worker', 'admin'],
        default: 'customer'
    },
    federation: { type: mongoose.Schema.Types.ObjectId, ref: 'Cooperative' },
    adminRole: { type: String, enum: ['super_admin', 'federation_admin'], default: null },
    authProvider: {
        type: String,
        enum: ['local', 'google'],
        default: 'local'
    },
    isVerified: {
        type: Boolean,
        default: false // Admin approval status (Must be explicitly approved by admin for workers)
    },
    isEmailVerified: {
        type: Boolean,
        default: false // OTP verification status
    },

    // GeoJSON Live Location (Optional, without defaults to prevent index errors when location is off)
    location: {
        type: {
            type: String,
            enum: ['Point']
        },
        coordinates: {
            type: [Number] // [longitude, latitude] format
        }
    },

    // Saved Addresses
    savedAddresses: [addressSchema],

    // Embedded Worker Details
    workerProfile: {
        type: workerProfileSchema,
        default: null // Frontend check: if (user.role === 'worker' && !user.workerProfile) -> Redirect to Worker Setup Screen
    },

    // KYC docs — Only for workers
    kycDocuments: {
        type: kycDocumentSchema,
        default: null
    },

    payoutDetails: { type: mongoose.Schema.Types.Mixed, default: null },
    preferredLanguage: { type: String, default: 'en' },
    emergencyContact: {
        name: { type: String, default: null },
        phone: { type: String, default: null },
        relation: { type: String, default: null },
    },
    pushTokens: [{ type: String }],

    // Single-device login security tracking
    activeDeviceId: {
        type: String,
        default: null
    },

    // User notification preferences (promotions, system, push)
    notificationPreferences: {
        marketing: { type: Boolean, default: true },
        system: { type: Boolean, default: true },
        push: { type: Boolean, default: true }
    }
}, {
    timestamps: true
});

// Spatial index for 5km radius queries
userSchema.index({ location: '2dsphere' });

userSchema.index(
  { 'kycDocuments.aadhaarNumber': 1 },
  { unique: true, sparse: true, partialFilterExpression: { 'kycDocuments.aadhaarNumber': { $exists: true, $ne: null, $ne: '' } } }
);
userSchema.index(
  { 'kycDocuments.panNumber': 1 },
  { unique: true, sparse: true, partialFilterExpression: { 'kycDocuments.panNumber': { $exists: true, $ne: null, $ne: '' } } }
);

// PRE HOOK: Strip worker-only KYC documents if user is a customer
userSchema.pre('validate', function () {
    if (this.role === 'customer') {
        this.kycDocuments = undefined;
    }
});

// PRE HOOK: Hash Password before saving
userSchema.pre('save', async function () {
    if (this.role === 'customer') {
        this.kycDocuments = undefined;
    }
    if (!this.isModified('password') || !this.password) {
        return;
    }

    const salt = await bcrypt.genSalt(10);
    this.password = await bcrypt.hash(this.password, salt);
});

// METHOD: Compare Password
userSchema.methods.comparePassword = async function (enteredPassword) {
    return await bcrypt.compare(enteredPassword, this.password);
};

// METHOD: Generate Access Token (Dynamic Expiry)
userSchema.methods.generateAccessToken = function () {
    return jwt.sign(
        { id: this._id, role: this.role },
        process.env.JWT_SECRET,
        { expiresIn: process.env.JWT_ACCESS_EXPIRY || '15m' }
    );
};

// METHOD: Generate Refresh Token (Dynamic Expiry)
userSchema.methods.generateRefreshToken = function () {
    return jwt.sign(
        { id: this._id },
        process.env.REFRESH_SECRET,
        { expiresIn: process.env.JWT_REFRESH_EXPIRY || '7d' }
    );
};

const User = mongoose.model('User', userSchema);

export default User;