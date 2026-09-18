import mongoose from 'mongoose';
import Booking from '../models/Booking.js';
import User from '../models/User.js';
import WebRTCCallLog from '../models/WebRTCCallLog.js';
import redis from '../config/redis.js';
import { sendIncomingCallPush, sendCancelCallPush } from '../services/webrtcCallPushService.js';
import { getIO } from '../config/socket.js';
import { getTargetCallRooms } from '../sockets/webrtcCallSocket.js';


/**
 * Normalizes booking ID into a canonical Redis key (without leading '#').
 */
export const getCanonicalBookingKey = (bookingId) => {
    if (!bookingId) return '';
    return String(bookingId).trim().replace(/^#/, '');
};

/**
 * Resolves a booking query safely across MongoDB _id or string bookingId formats.
 * Normalizes prefix '#' so both '#BK-260906-...' and 'BK-260906-...' work flawlessly.
 */
export const buildBookingQuery = (idInput) => {
    if (!idInput) return null;
    const str = String(idInput).trim();
    const orConditions = [];

    if (/^[0-9a-fA-F]{24}$/.test(str)) {
        orConditions.push({ _id: str });
    }
    orConditions.push({ bookingId: str });

    if (!str.startsWith('#')) {
        orConditions.push({ bookingId: `#${str}` });
    } else {
        orConditions.push({ bookingId: str.slice(1) });
    }

    return { $or: orConditions };
};

/**
 * Initiates a new WebRTC audio call session for a valid booking.
 * Guarantees phone number privacy (masked identities only).
 * @route POST /api/webrtc/call/initiate
 */
export const initiateWebRTCCall = async (req, res) => {
    try {
        const { bookingId } = req.body;
        const currentUserId = req.user.id;

        if (!bookingId) {
            return res.status(400).json({
                success: false,
                message: 'Booking ID is required to initiate an audio call'
            });
        }

        const bookingQuery = buildBookingQuery(bookingId);
        if (!bookingQuery) {
            return res.status(400).json({
                success: false,
                message: 'Invalid Booking ID provided'
            });
        }

        // Find booking by MongoDB _id or string bookingId (safely normalized)
        const booking = await Booking.findOne(bookingQuery)
            .populate('customer', 'name avatar role')
            .populate('worker', 'name avatar role')
            .populate('service', 'title category');

        if (!booking) {
            return res.status(404).json({
                success: false,
                message: 'Booking not found'
            });
        }

        // Validate booking status (calling is only permitted on active/confirmed jobs)
        const disallowedStatuses = ['CANCELLED', 'COMPLETED'];
        if (disallowedStatuses.includes(booking.status)) {
            return res.status(400).json({
                success: false,
                message: `Audio calling is not allowed for booking in '${booking.status}' status`
            });
        }

        // Worker must be assigned
        if (!booking.worker) {
            return res.status(400).json({
                success: false,
                message: 'Worker is not yet assigned for this booking. Call cannot be placed.'
            });
        }

        const customerId = String(booking.customer._id || booking.customer);
        const workerId = String(booking.worker._id || booking.worker);

        // Security check: Only the customer or assigned worker can join or initiate
        if (currentUserId !== customerId && currentUserId !== workerId) {
            return res.status(403).json({
                success: false,
                message: 'Access denied. You are not a participant in this booking.'
            });
        }

        const isCallerCustomer = currentUserId === customerId;
        const caller = isCallerCustomer ? booking.customer : booking.worker;
        const receiver = isCallerCustomer ? booking.worker : booking.customer;

        const callSessionId = `call_${booking.bookingId}_${Date.now()}`;
        const roomName = `webrtc_call_${booking.bookingId}`;

        // Masked caller & receiver profiles (Strictly NO phone numbers exposed)
        const maskedCaller = {
            id: caller._id,
            name: caller.name || (isCallerCustomer ? 'Customer' : 'Worker'),
            role: caller.role,
            avatar: caller.avatar || null
        };

        const maskedReceiver = {
            id: receiver._id,
            name: receiver.name || (isCallerCustomer ? 'Worker' : 'Customer'),
            role: receiver.role,
            avatar: receiver.avatar || null
        };

        // Cache active call state in Redis with 180-second TTL (Ringing phase)
        const redisCallKey = `webrtc:call:${getCanonicalBookingKey(booking.bookingId)}`;
        const callPayload = {
            callSessionId,
            bookingId: booking.bookingId,
            bookingMongoId: String(booking._id),
            room: roomName,
            status: 'RINGING',
            callerId: String(caller._id),
            receiverId: String(receiver._id),
            callerRole: caller.role,
            serviceTitle: booking.service?.title || 'Gig Service',
            initiatedAt: Date.now()
        };

        try {
            await redis.set(redisCallKey, JSON.stringify(callPayload), 'EX', 180);
        } catch (redisErr) {
            console.warn('Redis WebRTC call cache warning:', redisErr.message);
        }

        // Trigger High-Priority FCM Push Notification (Wakes up closed/background app with ringtone)
        sendIncomingCallPush({
            recipientUserId: receiver._id,
            bookingId: booking.bookingId,
            callSessionId,
            callerId: caller._id,
            callerName: maskedCaller.name,
            callerAvatar: maskedCaller.avatar,
            callerRole: caller.role,
            serviceTitle: booking.service?.title || 'Gig Service'
        }).catch((pushErr) => {
            console.warn('[WebRTC Call Push] Background dispatch warning:', pushErr.message);
        });

        return res.status(200).json({
            success: true,
            message: 'Call session initialized successfully',
            callSessionId,
            room: roomName,
            bookingId: booking.bookingId,
            serviceTitle: booking.service?.title || 'Gig Service',
            caller: maskedCaller,
            receiver: maskedReceiver
        });
    } catch (error) {
        console.error('initiateWebRTCCall error:', error);
        return res.status(500).json({
            success: false,
            message: 'Internal server error while initiating call'
        });
    }
};

/**
 * Accepts an active WebRTC audio call session via HTTP REST API.
 * Ensures 100% two-way connection even if socket event dropped across AWS ALB nodes.
 * @route POST /api/webrtc/call/accept
 */
export const acceptWebRTCCall = async (req, res) => {
    try {
        const { bookingId } = req.body;
        const currentUserId = String(req.user.id || req.user._id);

        if (!bookingId) {
            return res.status(400).json({
                success: false,
                message: 'Booking ID is required to accept call'
            });
        }

        const canonicalBookingId = getCanonicalBookingKey(bookingId);
        const redisCallKey = `webrtc:call:${canonicalBookingId}`;
        const rawCall = await redis.get(redisCallKey);
        let callData = rawCall ? JSON.parse(rawCall) : {};

        callData.status = 'CONNECTED';
        callData.connectedAt = Date.now();
        await redis.set(redisCallKey, JSON.stringify(callData), 'EX', 3600);

        const bookingQuery = buildBookingQuery(bookingId);
        let booking = null;
        if (bookingQuery && mongoose.connection.readyState === 1) {
            try {
                booking = await Booking.findOne(bookingQuery).select('_id bookingId customer worker');
            } catch (queryErr) {
                console.warn('[WebRTC-API] Booking query warning on accept:', queryErr.message);
            }
        }

        const customerId = booking ? String(booking.customer) : String(callData.callerId || '');
        const workerId = booking ? String(booking.worker) : String(callData.receiverId || '');
        const callerId = String(callData.callerId || (currentUserId === customerId ? workerId : customerId));

        const targetRooms = getTargetCallRooms(booking?.bookingId || bookingId);
        if (booking?._id) targetRooms.push(`webrtc_call_${booking._id}`);

        const io = req.app.get('io') || getIO();
        const acceptPayload = {
            bookingId: booking?.bookingId || bookingId,
            receiverId: currentUserId,
            senderUserId: currentUserId,
            timestamp: Date.now()
        };

        if (io) {
            targetRooms.forEach((r) => io.to(r).emit('webrtc:call-accepted', acceptPayload));
            if (callerId) io.to(`webrtc_user_${callerId}`).emit('webrtc:call-accepted', acceptPayload);
            if (customerId) io.to(`webrtc_user_${customerId}`).emit('webrtc:call-accepted', acceptPayload);
            if (workerId) io.to(`webrtc_user_${workerId}`).emit('webrtc:call-accepted', acceptPayload);
        }

        return res.status(200).json({
            success: true,
            message: 'Call session accepted successfully',
            callSession: callData
        });
    } catch (error) {
        console.error('acceptWebRTCCall error:', error);
        return res.status(500).json({
            success: false,
            message: 'Internal server error while accepting call'
        });
    }
};

/**
 * Returns dynamic ICE servers (STUN + TURN credentials) for NAT traversal.
 * @route GET /api/webrtc/config/ice-servers
 */
export const getIceServers = async (req, res) => {
    try {
        const iceServers = [
            { urls: 'stun:stun.l.google.com:19302' },
            { urls: 'stun:stun1.l.google.com:19302' },
            { urls: 'stun:stun2.l.google.com:19302' },
            { urls: 'stun:stun3.l.google.com:19302' },
            { urls: 'stun:stun4.l.google.com:19302' },
            { urls: 'stun:stun.services.mozilla.com' },
            { urls: 'stun:stun.cloudflare.com:3478' },
            // Public high-availability TURN relay (Metered OpenRelay) for Symmetric NAT / 4G/5G mobile carriers
            {
                urls: 'turn:openrelay.metered.ca:80',
                username: 'openrelay',
                credential: 'openrelay'
            },
            {
                urls: 'turn:openrelay.metered.ca:443',
                username: 'openrelay',
                credential: 'openrelay'
            },
            {
                urls: 'turn:openrelay.metered.ca:443?transport=tcp',
                username: 'openrelay',
                credential: 'openrelay'
            },
            {
                urls: 'turns:openrelay.metered.ca:443?transport=tcp',
                username: 'openrelay',
                credential: 'openrelay'
            },
            {
                urls: 'turns:openrelay.metered.ca:5349',
                username: 'openrelay',
                credential: 'openrelay'
            },
            {
                urls: 'turns:openrelay.metered.ca:5349?transport=tcp',
                username: 'openrelay',
                credential: 'openrelay'
            }
        ];

        // If custom TURN server is provided in environment variables (e.g. AWS coturn / Twilio)
        if (process.env.TURN_URL && process.env.TURN_USERNAME && process.env.TURN_CREDENTIAL) {
            iceServers.unshift({
                urls: process.env.TURN_URL,
                username: process.env.TURN_USERNAME,
                credential: process.env.TURN_CREDENTIAL
            });
        }


        return res.status(200).json({
            success: true,
            iceServers
        });
    } catch (error) {
        console.error('getIceServers error:', error);
        return res.status(500).json({
            success: false,
            message: 'Failed to fetch ICE server configuration'
        });
    }
};

/**
 * Network diagnostics & Wi-Fi firewall restriction detection.
 * When ICE fails due to restrictive Wi-Fi or router UDP blocking,
 * backend returns structured instructions to switch to mobile data.
 * @route POST /api/webrtc/call/network-diagnostics
 */
export const reportNetworkDiagnostics = async (req, res) => {
    try {
        const {
            bookingId,
            networkType, // 'wifi' | 'cellular' | 'ethernet'
            iceConnectionState, // 'failed' | 'disconnected' | 'checking'
            candidateType, // 'host' | 'srflx' | 'relay'
            details
        } = req.body;

        const isWifi = networkType === 'wifi';
        const isIceFailed = iceConnectionState === 'failed' || iceConnectionState === 'disconnected';

        // Check if strict Wi-Fi firewall / NAT blocked WebRTC UDP packets
        if (isWifi && isIceFailed) {
            return res.status(400).json({
                success: false,
                errorCode: 'FIREWALL_BLOCKED_WIFI_RESTRICTION',
                message: 'Your Wi-Fi or router firewall has restricted voice call traffic. Please switch to mobile data and try placing the call again.',
                suggestion: 'SWITCH_TO_MOBILE_DATA',
                networkType: 'wifi',
                retryable: true
            });
        }

        if (isIceFailed) {
            return res.status(400).json({
                success: false,
                errorCode: 'WEBRTC_ICE_CONNECTION_FAILED',
                message: 'Unable to establish a reliable voice connection. Please check your internet connection and try again.',
                suggestion: 'CHECK_INTERNET_CONNECTION',
                networkType: networkType || 'unknown',
                retryable: true
            });
        }

        return res.status(200).json({
            success: true,
            status: 'HEALTHY',
            networkType: networkType || 'unknown'
        });
    } catch (error) {
        console.error('reportNetworkDiagnostics error:', error);
        return res.status(500).json({
            success: false,
            message: 'Error processing network diagnostics'
        });
    }
};

/**
 * Fetches current WebRTC call state from Redis.
 * @route GET /api/webrtc/call/status/:bookingId
 */
export const getCallStatus = async (req, res) => {
    try {
        const { bookingId } = req.params;
        const redisCallKey = `webrtc:call:${getCanonicalBookingKey(bookingId)}`;

        const callDataRaw = await redis.get(redisCallKey);
        if (!callDataRaw) {
            return res.status(200).json({
                success: true,
                status: 'IDLE',
                message: 'No active call session in progress'
            });
        }

        const callData = JSON.parse(callDataRaw);
        return res.status(200).json({
            success: true,
            status: callData.status,
            callSession: callData
        });
    } catch (error) {
        console.error('getCallStatus error:', error);
        return res.status(500).json({
            success: false,
            message: 'Error fetching call status'
        });
    }
};

/**
 * Fetches call history for the authenticated user (without exposing phone numbers).
 * @route GET /api/webrtc/call/history
 */
export const getCallHistory = async (req, res) => {
    try {
        const currentUserId = req.user.id;

        const calls = await WebRTCCallLog.find({
            $or: [{ caller: currentUserId }, { receiver: currentUserId }]
        })
        .sort({ createdAt: -1 })
        .limit(30)
        .populate('caller', 'name avatar role')
        .populate('receiver', 'name avatar role')
        .select('-caller.phone -receiver.phone');

        return res.status(200).json({
            success: true,
            count: calls.length,
            calls
        });
    } catch (error) {
        console.error('getCallHistory error:', error);
        return res.status(500).json({
            success: false,
            message: 'Error fetching call history'
        });
    }
};

/**
 * Terminates an active or ringing WebRTC audio call session via HTTP REST API.
 * Ensures 100% two-way call termination even if socket signaling dropped or was in background.
 * @route POST /api/webrtc/call/hangup
 */
export const hangupWebRTCCall = async (req, res) => {
    try {
        const { bookingId, endReason, durationSeconds } = req.body;
        const currentUserId = String(req.user.id || req.user._id);

        console.log(`[WebRTC-API] 🛑 Received POST /api/webrtc/call/hangup for booking: ${bookingId}, user: ${currentUserId}, reason: ${endReason || 'HANGUP'}`);

        if (!bookingId) {
            return res.status(400).json({
                success: false,
                message: 'Booking ID is required to terminate call'
            });
        }

        const canonicalBookingId = getCanonicalBookingKey(bookingId);
        const redisCallKey = `webrtc:call:${canonicalBookingId}`;
        const rawCall = await redis.get(redisCallKey);
        await redis.del(redisCallKey);

        let callData = rawCall ? JSON.parse(rawCall) : {};

        // Safely resolve booking if DB connected
        const bookingQuery = buildBookingQuery(bookingId);
        let booking = null;
        if (bookingQuery && mongoose.connection.readyState === 1) {
            try {
                booking = await Booking.findOne(bookingQuery).select('_id bookingId customer worker status');
            } catch (queryErr) {
                console.warn('[WebRTC-API] Booking query warning:', queryErr.message);
            }
        }

        const customerId = booking ? String(booking.customer) : String(callData.callerId || '');
        const workerId = booking ? String(booking.worker) : String(callData.receiverId || '');
        const targetRooms = getTargetCallRooms(booking?.bookingId || bookingId);
        if (booking?._id) {
            targetRooms.push(`webrtc_call_${booking._id}`);
        }

        const io = req.app.get('io') || getIO();
        const callEndedPayload = {
            bookingId: booking?.bookingId || bookingId,
            durationSeconds: durationSeconds || 0,
            endReason: endReason || 'NORMAL_HANGUP',
            endedBy: currentUserId,
            timestamp: Date.now()
        };

        if (io) {
            console.log(`[WebRTC-API] 📢 Emitting webrtc:call-ended to call rooms: [${targetRooms.join(', ')}] and user inboxes: [webrtc_user_${customerId}, webrtc_user_${workerId}]`);
            // Emit to call room aliases
            targetRooms.forEach((room) => io.to(room).emit('webrtc:call-ended', callEndedPayload));

            // Emit to personal user inboxes for BOTH customer and worker
            if (customerId) io.to(`webrtc_user_${customerId}`).emit('webrtc:call-ended', callEndedPayload);
            if (workerId) io.to(`webrtc_user_${workerId}`).emit('webrtc:call-ended', callEndedPayload);
        } else {
            console.warn('[WebRTC-API] ⚠️ Socket.io instance not available during hangup emit');
        }

        // Send silent FCM push to cancel native incoming call ringtone on counterpart
        const recipientUserId = (currentUserId === customerId) ? workerId : customerId;
        if (recipientUserId) {
            sendCancelCallPush({
                recipientUserId,
                bookingId: booking?.bookingId || bookingId,
                callSessionId: callData.callSessionId
            }).catch((err) => console.warn('[WebRTC-API] Push cancel error:', err.message));
        }

        // Persist call log if booking exists and DB connected
        if (booking && mongoose.connection.readyState === 1) {
            try {
                await WebRTCCallLog.create({
                    booking: booking._id,
                    bookingId: booking.bookingId,
                    caller: callData.callerId || (currentUserId === customerId ? customerId : workerId),
                    receiver: callData.receiverId || (currentUserId === customerId ? workerId : customerId),
                    callerRole: callData.callerRole || (currentUserId === customerId ? 'customer' : 'worker'),
                    status: (durationSeconds && durationSeconds > 0) ? 'COMPLETED' : 'MISSED',
                    durationSeconds: durationSeconds || 0,
                    startedAt: callData.initiatedAt ? new Date(callData.initiatedAt) : new Date(),
                    connectedAt: callData.connectedAt ? new Date(callData.connectedAt) : null,
                    endedAt: new Date(),
                    endReason: endReason || 'NORMAL_HANGUP'
                });
            } catch (logErr) {
                console.warn('[WebRTC-API] Call log persistence warning:', logErr.message);
            }
        }


        return res.status(200).json({
            success: true,
            message: 'Call session successfully terminated'
        });
    } catch (error) {
        console.error('[WebRTC-API] ❌ hangupWebRTCCall error:', error);
        return res.status(500).json({
            success: false,
            message: 'Internal server error while hanging up call'
        });
    }
};

