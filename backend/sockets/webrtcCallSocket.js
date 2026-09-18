import Booking from '../models/Booking.js';
import WebRTCCallLog from '../models/WebRTCCallLog.js';
import redis from '../config/redis.js';
import { sendCancelCallPush } from '../services/webrtcCallPushService.js';
import { buildBookingQuery } from '../controllers/webrtcCallController.js';

export const getCanonicalBookingKey = (bookingId) => {
    if (!bookingId) return '';
    return String(bookingId).trim().replace(/^#/, '');
};

/**
 * Normalizes booking ID into all valid room name aliases (with and without '#').
 * Ensures socket emissions reach the peer regardless of which variant is sent.
 */
export const getTargetCallRooms = (bookingId) => {
    if (!bookingId) return [];
    const clean = String(bookingId).trim();
    const rooms = new Set();
    rooms.add(`webrtc_call_${clean}`);
    if (clean.startsWith('#')) {
        rooms.add(`webrtc_call_${clean.slice(1)}`);
    } else {
        rooms.add(`webrtc_call_#${clean}`);
    }
    return Array.from(rooms);
};

/**
 * Comprehensive resolution for call rooms and recipient user ID.
 * Supports both human-readable bookingId ('#BK-...') and Mongo ObjectId ('6aaa...').
 * Pulls from Redis cache or MongoDB to guarantee delivery to both the rooms and the peer's direct inbox.
 */
export const resolveAllCallTargets = async (bookingId, senderUserId) => {
    const rooms = new Set(getTargetCallRooms(bookingId));
    let peerUserId = null;
    let canonicalBookingId = bookingId;

    try {
        const canonicalKey = getCanonicalBookingKey(bookingId);
        // 1. Try Redis cache
        const cachedRaw = await redis.get(`webrtc:call:${canonicalKey}`);
        if (cachedRaw) {
            const cached = JSON.parse(cachedRaw);
            if (cached.bookingId) getTargetCallRooms(cached.bookingId).forEach(r => rooms.add(r));
            if (cached.bookingMongoId) getTargetCallRooms(cached.bookingMongoId).forEach(r => rooms.add(r));
            canonicalBookingId = cached.bookingId || canonicalBookingId;
            if (senderUserId) {
                peerUserId = String(senderUserId) === String(cached.callerId) ? cached.receiverId : cached.callerId;
            }
        }

        // 2. Fallback to Mongo query
        if (!peerUserId || rooms.size <= 2) {
            const bookingQuery = buildBookingQuery(bookingId);
            if (bookingQuery) {
                const booking = await Booking.findOne(bookingQuery).select('_id bookingId customer worker');
                if (booking) {
                    const canonical = String(booking.bookingId);
                    const mongo = String(booking._id);
                    getTargetCallRooms(canonical).forEach(r => rooms.add(r));
                    getTargetCallRooms(mongo).forEach(r => rooms.add(r));
                    canonicalBookingId = canonical;
                    if (senderUserId) {
                        const cId = String(booking.customer);
                        const wId = String(booking.worker);
                        peerUserId = String(senderUserId) === cId ? wId : cId;
                    }
                }
            }
        }
    } catch (err) {
        console.warn('[WebRTC-Socket] Error in resolveAllCallTargets:', err.message);
    }

    return {
        rooms: Array.from(rooms),
        peerUserId: peerUserId ? String(peerUserId) : null,
        canonicalBookingId
    };
};

/**
 * Registers WebRTC Audio Calling Socket.io event listeners.
 * Employs Redis Pub/Sub for seamless scaling across multi-container AWS ECS tasks.
 * Ensures strict participant authorization and Wi-Fi firewall diagnostics.
 * @param {object} io - The initialized socket.io server instance
 */
export const registerWebRTCSocketHandlers = (io) => {
    io.on('connection', (socket) => {
        // Track rooms joined by this socket for clean disconnection handling
        socket.callRooms = new Set();

        // Personal inbox so incoming-call reaches peer even before they join booking room.
        socket.on('webrtc:register', (data) => {
            const userId = data?.userId;
            if (!userId) return;
            const room = `webrtc_user_${String(userId)}`;
            socket.join(room);
            socket.callRooms.add(room);
            socket.currentUserId = String(userId);
            console.log(`[WebRTC-Socket] 👤 Registered user ${userId} to personal room ${room}`);
        });

        // =========================================================================
        // 1. Join Secure Booking Call Room (Strict Authorization: Customer & Worker only)
        // =========================================================================
        socket.on('webrtc:join-room', async (data) => {
            try {
                const { bookingId, userId } = data || {};

                if (!bookingId || !userId) {
                    console.warn('[WebRTC-Socket] ⚠️ join-room missing bookingId or userId:', data);
                    return socket.emit('webrtc:error', {
                        errorCode: 'INVALID_PARAMETERS',
                        message: 'bookingId and userId are required to join the call room'
                    });
                }

                const bookingQuery = buildBookingQuery(bookingId);
                if (!bookingQuery) {
                    return socket.emit('webrtc:error', {
                        errorCode: 'INVALID_PARAMETERS',
                        message: 'Invalid bookingId provided'
                    });
                }

                // Verify booking and participants safely (supports #BK-... and MongoDB _id)
                const booking = await Booking.findOne(bookingQuery)
                    .select('_id bookingId customer worker status');

                if (!booking) {
                    console.warn(`[WebRTC-Socket] ⚠️ join-room: booking not found for ${bookingId}`);
                    return socket.emit('webrtc:error', {
                        errorCode: 'BOOKING_NOT_FOUND',
                        message: 'Booking not found for audio call'
                    });
                }

                const customerId = String(booking.customer);
                const workerId = String(booking.worker);
                const requesterId = String(userId);

                // Strictly disallow any third person from joining the channel
                if (requesterId !== customerId && requesterId !== workerId) {
                    console.warn(`[WebRTC-Socket] 🚫 Unauthorized call room access by user ${requesterId}`);
                    return socket.emit('webrtc:error', {
                        errorCode: 'UNAUTHORIZED_CALL_PARTICIPANT',
                        message: 'Only the customer and assigned professional for this booking can join the call room.'
                    });
                }

                const canonicalId = String(booking.bookingId);
                const mongoId = String(booking._id);
                const roomsToJoin = new Set([
                    `webrtc_call_${canonicalId}`,
                    `webrtc_call_${mongoId}`
                ]);
                if (canonicalId.startsWith('#')) {
                    roomsToJoin.add(`webrtc_call_${canonicalId.slice(1)}`);
                } else {
                    roomsToJoin.add(`webrtc_call_#${canonicalId}`);
                }

                roomsToJoin.forEach((r) => {
                    socket.join(r);
                    socket.callRooms.add(r);
                });

                socket.currentUserId = requesterId;
                socket.currentBookingId = canonicalId;

                const userRole = requesterId === customerId ? 'customer' : 'worker';
                console.log(`[WebRTC-Socket] 🚪 User ${requesterId} (${userRole}) joined channel aliases: [${Array.from(roomsToJoin).join(', ')}]`);

                socket.emit('webrtc:room-joined', {
                    bookingId: canonicalId,
                    room: `webrtc_call_${canonicalId}`,
                    userId: requesterId,
                    role: userRole
                });

                // Inform counterpart across all room aliases that peer is ready
                socket.to(Array.from(roomsToJoin)).emit('webrtc:peer-ready', {
                    userId: requesterId,
                    role: userRole
                });

            } catch (err) {
                console.error('[WebRTC-Socket] ❌ join-room error:', err.message);
                socket.emit('webrtc:error', {
                    errorCode: 'ROOM_JOIN_FAILED',
                    message: 'Failed to join the call room.'
                });
            }
        });

        // =========================================================================
        // 2. Call Initiation (Rings Counterpart)
        // =========================================================================
        socket.on('webrtc:call-initiate', async (data) => {
            try {
                const { bookingId, callerId, callerName, callerAvatar, callerRole, callSessionId, serviceTitle, receiverId } = data || {};
                const targetRooms = getTargetCallRooms(bookingId);

                console.log(`[WebRTC-Socket] 📞 webrtc:call-initiate from ${callerRole} (${callerId}) to receiver (${receiverId}) in rooms: [${targetRooms.join(', ')}]`);

                const incomingPayload = {
                    bookingId,
                    callSessionId: callSessionId || null,
                    serviceTitle: serviceTitle || 'Audio Calling',
                    senderUserId: callerId || socket.currentUserId,
                    caller: {
                        id: callerId,
                        name: callerName || (callerRole === 'customer' ? 'Customer' : 'Worker'),
                        avatar: callerAvatar || null,
                        role: callerRole
                    },
                    timestamp: Date.now()
                };

                // Foreground signalling: ring peers in call rooms
                targetRooms.forEach((r) => io.to(r).emit('webrtc:incoming-call', incomingPayload));

                // Also ring receiver in their personal user inbox
                if (receiverId) {
                    console.log(`[WebRTC-Socket] 📲 Ringing personal inbox webrtc_user_${receiverId}`);
                    io.to(`webrtc_user_${String(receiverId)}`).emit(
                        'webrtc:incoming-call',
                        incomingPayload
                    );
                }
            } catch (err) {
                console.error('[WebRTC-Socket] ❌ call-initiate error:', err.message);
            }
        });

        // =========================================================================
        // 3. Call Acceptance
        // =========================================================================
        socket.on('webrtc:call-accept', async (data) => {
            try {
                const { bookingId, receiverId } = data || {};
                const { rooms, peerUserId, canonicalBookingId } = await resolveAllCallTargets(
                    bookingId,
                    receiverId || socket.currentUserId
                );
                const finalCallerId = peerUserId;

                console.log(`[WebRTC-Socket] 🟢 webrtc:call-accept by receiver: ${receiverId} for booking: ${bookingId} in rooms: [${rooms.join(', ')}], direct caller: ${finalCallerId}`);

                const acceptPayload = {
                    bookingId: canonicalBookingId,
                    receiverId,
                    senderUserId: receiverId || socket.currentUserId,
                    timestamp: Date.now()
                };

                // Notify caller in all call room aliases
                rooms.forEach((r) => {
                    io.to(r).emit('webrtc:call-accepted', acceptPayload);
                });

                // And directly to personal caller room
                if (finalCallerId) {
                    io.to(`webrtc_user_${String(finalCallerId)}`).emit('webrtc:call-accepted', acceptPayload);
                }

                // Update Redis status to CONNECTED
                try {
                    const redisCallKey = `webrtc:call:${getCanonicalBookingKey(bookingId)}`;
                    const existingCallRaw = await redis.get(redisCallKey);
                    let callObj = existingCallRaw ? JSON.parse(existingCallRaw) : {};
                    callObj.status = 'CONNECTED';
                    callObj.connectedAt = Date.now();
                    if (callObj.callerId && String(callObj.callerId) !== String(finalCallerId)) {
                        io.to(`webrtc_user_${String(callObj.callerId)}`).emit('webrtc:call-accepted', acceptPayload);
                    }
                    await redis.set(redisCallKey, JSON.stringify(callObj), 'EX', 3600); // 1 hour call max
                } catch (redisErr) {
                    console.warn('[WebRTC-Socket] ⚠️ Redis call state update warning:', redisErr.message);
                }

            } catch (err) {
                console.error('[WebRTC-Socket] ❌ call-accept error:', err.message);
            }
        });

        // =========================================================================
        // 4. Call Rejection / Busy / Decline
        // =========================================================================
        socket.on('webrtc:call-reject', async (data) => {
            try {
                const { bookingId, reason } = data || {};
                const targetRooms = getTargetCallRooms(bookingId);

                console.log(`[WebRTC-Socket] 🚫 webrtc:call-reject for booking: ${bookingId}, reason: ${reason || 'DECLINED'}`);

                const rejectPayload = {
                    bookingId,
                    reason: reason || 'DECLINED',
                    senderUserId: socket.currentUserId,
                    timestamp: Date.now()
                };
                const endPayload = {
                    bookingId,
                    durationSeconds: 0,
                    endReason: reason || 'DECLINED',
                    senderUserId: socket.currentUserId,
                    timestamp: Date.now()
                };

                // Clean up Redis
                const redisCallKey = `webrtc:call:${getCanonicalBookingKey(bookingId)}`;
                const existingCallRaw = await redis.get(redisCallKey);
                await redis.del(redisCallKey);
                let callObj = existingCallRaw ? JSON.parse(existingCallRaw) : {};

                const bookingQuery = buildBookingQuery(bookingId);
                const booking = bookingQuery
                    ? await Booking.findOne(bookingQuery).select('_id bookingId customer worker')
                    : null;

                const customerId = booking ? String(booking.customer) : String(callObj.callerId || '');
                const workerId = booking ? String(booking.worker) : String(callObj.receiverId || '');
                if (booking?._id) {
                    targetRooms.push(`webrtc_call_${booking._id}`);
                }

                // Dual broadcast: emit BOTH webrtc:call-rejected AND webrtc:call-ended to ALL call rooms & user inboxes
                console.log(`[WebRTC-Socket] 📢 Broadcasting call-rejected + call-ended to rooms: [${targetRooms.join(', ')}] and user inboxes: [webrtc_user_${customerId}, webrtc_user_${workerId}]`);
                targetRooms.forEach((r) => {
                    io.to(r).emit('webrtc:call-rejected', rejectPayload);
                    io.to(r).emit('webrtc:call-ended', endPayload);
                });
                if (customerId) {
                    io.to(`webrtc_user_${customerId}`).emit('webrtc:call-rejected', rejectPayload);
                    io.to(`webrtc_user_${customerId}`).emit('webrtc:call-ended', endPayload);
                }
                if (workerId) {
                    io.to(`webrtc_user_${workerId}`).emit('webrtc:call-rejected', rejectPayload);
                    io.to(`webrtc_user_${workerId}`).emit('webrtc:call-ended', endPayload);
                }

                // Cancel native incoming call push (CallKit / ringtone) on all targets
                const targets = new Set([callObj.callerId, callObj.receiverId, customerId, workerId].filter(Boolean).map(String));
                for (const recipientUserId of targets) {
                    sendCancelCallPush({
                        recipientUserId,
                        bookingId: booking?.bookingId || bookingId,
                        callSessionId: callObj.callSessionId || data?.callSessionId
                    }).catch(() => {});
                }

            } catch (err) {
                console.error('[WebRTC-Socket] ❌ call-reject error:', err.message);
            }
        });


        // =========================================================================
        // 5. WebRTC SDP Offer Relay
        // =========================================================================
        socket.on('webrtc:offer', async (data) => {
            try {
                const { bookingId, sdp, targetUserId } = data || {};
                if (!bookingId || !sdp) return;

                const senderUserId = String(socket.currentUserId || data?.senderUserId || '');
                const { rooms, peerUserId, canonicalBookingId } = await resolveAllCallTargets(
                    bookingId,
                    senderUserId
                );
                const finalTargetId = targetUserId || peerUserId;

                console.log(`[WebRTC-Socket] 📤 Relaying SDP offer for ${bookingId} across [${rooms.join(', ')}], direct peer: ${finalTargetId}`);

                const offerPayload = { sdp, bookingId: canonicalBookingId, senderUserId };
                rooms.forEach((r) => {
                    io.to(r).emit('webrtc:offer', offerPayload);
                });
                if (finalTargetId) {
                    io.to(`webrtc_user_${String(finalTargetId)}`).emit('webrtc:offer', offerPayload);
                }
            } catch (err) {
                console.error('[WebRTC-Socket] ❌ webrtc:offer error:', err.message);
            }
        });

        // =========================================================================
        // 6. WebRTC SDP Answer Relay
        // =========================================================================
        socket.on('webrtc:answer', async (data) => {
            try {
                const { bookingId, sdp, targetUserId } = data || {};
                if (!bookingId || !sdp) return;

                const senderUserId = String(socket.currentUserId || data?.senderUserId || '');
                const { rooms, peerUserId, canonicalBookingId } = await resolveAllCallTargets(
                    bookingId,
                    senderUserId
                );
                const finalTargetId = targetUserId || peerUserId;

                console.log(`[WebRTC-Socket] 📥 Relaying SDP answer for ${bookingId} across [${rooms.join(', ')}], direct peer: ${finalTargetId}`);

                const answerPayload = { sdp, bookingId: canonicalBookingId, senderUserId };
                rooms.forEach((r) => {
                    io.to(r).emit('webrtc:answer', answerPayload);
                });
                if (finalTargetId) {
                    io.to(`webrtc_user_${String(finalTargetId)}`).emit('webrtc:answer', answerPayload);
                }
            } catch (err) {
                console.error('[WebRTC-Socket] ❌ webrtc:answer error:', err.message);
            }
        });

        // =========================================================================
        // 7. ICE Candidate Exchange
        // =========================================================================
        socket.on('webrtc:ice-candidate', async (data) => {
            try {
                const { bookingId, candidate, targetUserId } = data || {};
                if (!bookingId || !candidate) return;

                const senderUserId = String(socket.currentUserId || data?.senderUserId || '');
                const { rooms, peerUserId, canonicalBookingId } = await resolveAllCallTargets(
                    bookingId,
                    senderUserId
                );
                const finalTargetId = targetUserId || peerUserId;

                console.log(`[WebRTC-Socket] ❄️ Relaying ICE candidate for ${bookingId} across [${rooms.join(', ')}], direct peer: ${finalTargetId}`);

                const candidatePayload = { candidate, bookingId: canonicalBookingId, senderUserId };
                rooms.forEach((r) => {
                    io.to(r).emit('webrtc:ice-candidate', candidatePayload);
                });
                if (finalTargetId) {
                    io.to(`webrtc_user_${String(finalTargetId)}`).emit('webrtc:ice-candidate', candidatePayload);
                }
            } catch (err) {
                console.error('[WebRTC-Socket] ❌ webrtc:ice-candidate error:', err.message);
            }
        });


        // =========================================================================
        // 8. Firewall Restriction & Strict NAT ICE Failure Detection
        // =========================================================================
        socket.on('webrtc:ice-failed', async (data) => {
            try {
                const { bookingId, networkType, iceState, details } = data || {};
                const targetRooms = getTargetCallRooms(bookingId);
                const isWifi = networkType === 'wifi';

                console.warn(`[WebRTC-Socket] ⚠️ ICE Failure detected in rooms [${targetRooms.join(', ')}] (Network: ${networkType}, ICE: ${iceState})`);

                if (isWifi) {
                    // Send explicit instructions for Wi-Fi Firewall block
                    const firewallError = {
                        errorCode: 'FIREWALL_BLOCKED_WIFI_RESTRICTION',
                        message: 'Your Wi-Fi or router firewall has restricted voice call traffic. Please switch to mobile data and try placing the call again.',
                        suggestion: 'SWITCH_TO_MOBILE_DATA',
                        networkType: 'wifi',
                        bookingId
                    };

                    // Send to reporting socket
                    socket.emit('webrtc:error', firewallError);

                    // Notify counterpart so they know why the call couldn't connect
                    socket.to(targetRooms).emit('webrtc:peer-network-issue', {
                        bookingId,
                        message: 'The counterpart firewall is restricting voice traffic. Waiting for network switch.',
                        suggestion: 'WAIT_FOR_PEER_NETWORK_SWITCH'
                    });

                    // Log audit event
                    try {
                        const bookingQuery = buildBookingQuery(bookingId);
                        const booking = bookingQuery ? await Booking.findOne(bookingQuery)
                            .select('_id bookingId customer worker') : null;

                        if (booking) {
                            await WebRTCCallLog.create({
                                booking: booking._id,
                                bookingId: booking.bookingId,
                                caller: booking.customer,
                                receiver: booking.worker || booking.customer,
                                callerRole: socket.currentUserId === String(booking.customer) ? 'customer' : 'worker',
                                status: 'FAILED',
                                endReason: 'FIREWALL_BLOCKED',
                                networkDiagnostics: {
                                    callerNetwork: isWifi ? 'wifi' : 'unknown',
                                    firewallBlocked: true,
                                    iceConnectionState: iceState || 'failed',
                                    details: details || 'Wi-Fi UDP/STUN firewall block detected'
                                }
                            });
                        }
                    } catch (logErr) {
                        console.warn('[WebRTC-Socket] ⚠️ Error logging firewall failure:', logErr.message);
                    }
                } else {
                    // Generic connection issue
                    socket.emit('webrtc:error', {
                        errorCode: 'WEBRTC_ICE_FAILED',
                        message: 'Unable to establish a voice connection. Please check your internet signal and try again.',
                        suggestion: 'CHECK_INTERNET_CONNECTION',
                        networkType: networkType || 'unknown'
                    });
                }

            } catch (err) {
                console.error('[WebRTC-Socket] ❌ ice-failed handler error:', err.message);
            }
        });

        // =========================================================================
        // 9. Call Hangup / Normal Termination
        // =========================================================================
        socket.on('webrtc:call-hangup', async (data) => {
            try {
                const { bookingId, durationSeconds, endReason } = data || {};
                const endedBy = socket.currentUserId || data?.endedBy;
                const targetRooms = getTargetCallRooms(bookingId);

                console.log(`[WebRTC-Socket] 🛑 webrtc:call-hangup received for booking: ${bookingId}, duration: ${durationSeconds || 0}s, reason: ${endReason || 'NORMAL_HANGUP'}, endedBy: ${endedBy}`);

                const redisCallKey = `webrtc:call:${getCanonicalBookingKey(bookingId)}`;
                const rawCall = await redis.get(redisCallKey);
                await redis.del(redisCallKey);

                let callData = rawCall ? JSON.parse(rawCall) : {};

                const bookingQuery = buildBookingQuery(bookingId);
                const booking = bookingQuery ? await Booking.findOne(bookingQuery)
                    .select('_id bookingId customer worker') : null;

                const customerId = booking ? String(booking.customer) : String(callData.callerId || '');
                const workerId = booking ? String(booking.worker) : String(callData.receiverId || '');
                if (booking?._id) {
                    targetRooms.push(`webrtc_call_${booking._id}`);
                }

                const callEndedPayload = {
                    bookingId: booking?.bookingId || bookingId,
                    durationSeconds: durationSeconds || 0,
                    endReason: endReason || 'NORMAL_HANGUP',
                    endedBy,
                    timestamp: Date.now()
                };

                // Dual broadcast: emit to ALL target room aliases AND both personal inboxes
                console.log(`[WebRTC-Socket] 📢 Broadcasting webrtc:call-ended to call rooms: [${targetRooms.join(', ')}] and user inboxes: [webrtc_user_${customerId}, webrtc_user_${workerId}]`);
                targetRooms.forEach((r) => {
                    io.to(r).emit('webrtc:call-ended', callEndedPayload);
                });
                if (customerId) {
                    io.to(`webrtc_user_${customerId}`).emit('webrtc:call-ended', callEndedPayload);
                }
                if (workerId) {
                    io.to(`webrtc_user_${workerId}`).emit('webrtc:call-ended', callEndedPayload);
                }

                // Send silent FCM push to cancel native incoming call ringtone on counterpart
                const recipientUserId = (endedBy && String(endedBy) === customerId) ? workerId : customerId;
                if (recipientUserId) {
                    sendCancelCallPush({
                        recipientUserId,
                        bookingId: booking?.bookingId || bookingId,
                        callSessionId: callData.callSessionId
                    }).catch(() => {});
                }

                // Persist completed call log
                if (booking) {
                    try {
                        await WebRTCCallLog.create({
                            booking: booking._id,
                            bookingId: booking.bookingId,
                            caller: callData.callerId || booking.customer,
                            receiver: (callData.callerId && String(callData.callerId) === String(booking.customer))
                                ? (booking.worker || booking.customer)
                                : booking.customer,
                            callerRole: callData.callerRole || 'customer',
                            status: durationSeconds > 0 ? 'COMPLETED' : 'MISSED',
                            durationSeconds: durationSeconds || 0,
                            startedAt: callData.initiatedAt ? new Date(callData.initiatedAt) : new Date(),
                            connectedAt: callData.connectedAt ? new Date(callData.connectedAt) : null,
                            endedAt: new Date(),
                            endReason: endReason || 'NORMAL_HANGUP'
                        });
                    } catch (dbErr) {
                        console.warn('[WebRTC-Socket] ⚠️ Call log save error:', dbErr.message);
                    }
                }

            } catch (err) {
                console.error('[WebRTC-Socket] ❌ call-hangup error:', err.message);
            }
        });

        // =========================================================================
        // 10. Disconnect Cleanup
        // =========================================================================
        socket.on('disconnect', () => {
            console.log(`[WebRTC-Socket] 🔌 Disconnect: socket ${socket.id}, user: ${socket.currentUserId}, booking: ${socket.currentBookingId}`);
            if (socket.callRooms && socket.callRooms.size > 0) {
                for (const room of socket.callRooms) {
                    socket.to(room).emit('webrtc:peer-disconnected', {
                        userId: socket.currentUserId,
                        bookingId: socket.currentBookingId,
                        room,
                        timestamp: Date.now()
                    });
                }
            }
        });

    });
};
