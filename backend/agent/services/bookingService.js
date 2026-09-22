import Booking from "../../models/Booking.js";
import User from "../../models/User.js";
import Service from "../../models/Service.js";
import { llm } from "../config/llmModel.js";

/**
 * Auto-generate a clear, concise professional job description using AI if missing or for SOS
 */
export const generateAutoDescription = async ({ category, promptText = "", isEmergency = false }) => {
    try {
        const aiPrompt = `Write a short 1-sentence professional job description for a ${category || "Home Service"} service request.
User input: "${promptText || "None"}"
Is emergency: ${isEmergency}
Reply with ONLY the 1-sentence description.`;
        const res = await llm.invoke(aiPrompt);
        const desc = res.content.trim().replace(/^["']|["']$/g, '');
        if (desc && desc.length > 5) return desc;
    } catch (e) {
        // Fallback description template
    }

    if (isEmergency) {
        return `Emergency SOS ${category || "Home"} repair requested immediately.`;
    }
    return promptText && promptText.length > 5
        ? promptText
        : `Standard ${category || "Home"} maintenance and repair request via Fixly AI.`;
};

/**
 * Atomically create confirmed booking in MongoDB and emit real-time socket
 */
export const createBookingInDB = async ({
    userId,
    category,
    bookingType = "STANDARD",
    isEmergency = false,
    scheduledTime = null,
    workerId = null,
    problemDescription = "",
    addressLine = null,
    coordinates = null,
    estimate = null,
    io = null
}) => {
    // 1. Resolve User & Address
    let user = null;
    if (userId) {
        user = await User.findById(userId).lean();
    }

    const coords = coordinates || user?.savedAddresses?.[0]?.location?.coordinates || [77.2090, 28.6139];
    const resolvedAddress = addressLine || user?.savedAddresses?.[0]?.addressLine || "User Location Address";

    // 2. Resolve Service
    let service = null;
    if (category) {
        service = await Service.findOne({ category: new RegExp(`^${category}$`, 'i') }).lean();
    }
    if (!service) {
        service = await Service.findOne({ isActive: true }).lean();
    }

    const basePrice = estimate?.baseServiceFee || 250;
    const urgentFee = isEmergency ? 50 : 0;
    const totalAmount = estimate?.totalAmount || (basePrice + urgentFee);

    // 3. Create Booking Document
    const newBooking = await Booking.create({
        customer: userId || null,
        worker: workerId || null,
        service: service?._id || null,
        bookingType: bookingType || (isEmergency ? "EMERGENCY_SOS" : "STANDARD"),
        isEmergency: Boolean(isEmergency),
        timeSlot: isEmergency ? "Immediate (SOS Emergency)" : (scheduledTime || "Standard Service"),
        scheduledTime: scheduledTime ? new Date(Date.now() + 86400000) : null,
        problemDescription: problemDescription || `${category || "General"} service request via Fixly AI Assistant`,
        serviceAddress: {
            addressLine: resolvedAddress,
            location: { type: "Point", coordinates: coords }
        },
        status: "PENDING",
        invoice: {
            baseServiceFee: basePrice,
            platformFee: 0,
            urgentFee: urgentFee,
            totalAmount: totalAmount,
            paymentStatus: "PENDING",
            paymentMethod: "UPI"
        }
    });

    // 4. Populate Booking Details
    const populated = await Booking.findById(newBooking._id)
        .populate('worker', 'name avatar workerProfile rating')
        .populate('service', 'name title category icon basePrice')
        .populate('customer', 'name avatar')
        .lean();

    const resultBooking = populated || newBooking.toObject();
    if (resultBooking && resultBooking.worker && typeof resultBooking.worker === 'object') {
        // AI chat must never receive worker phone — in-app WebRTC only.
        const { phone, ...workerSafe } = resultBooking.worker;
        resultBooking.worker = workerSafe;
        resultBooking.worker.toString = function() {
            return String(this._id);
        };
    } else if (resultBooking && !resultBooking.worker && workerId) {
        resultBooking.worker = workerId;
    }

    // 5. Emit Socket Events for real-time dispatch
    if (io) {
        try {
            if (workerId) {
                io.emit('worker:booking_requested', {
                    workerId: String(workerId),
                    booking: populated || newBooking
                });
            } else {
                io.emit('booking:new_available', {
                    bookingId: newBooking._id,
                    coordinates: coords,
                    category,
                    isEmergency,
                    bookingType: newBooking.bookingType
                });
            }
        } catch (sockErr) {
            console.warn("[BookingService] Socket emit error:", sockErr.message);
        }
    }

    return resultBooking;
};

export default {
    generateAutoDescription,
    createBookingInDB
};
