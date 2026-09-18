import User from '../models/User.js';
import Booking from '../models/Booking.js';
import redis from '../config/redis.js';
import { buildBookingQuery } from '../controllers/webrtcCallController.js';

/**
 * Resolves all valid tracking room aliases for a given bookingId.
 * Guarantees that users joining with or without '#' receive tracking events.
 * @param {string} bookingId 
 * @returns {string[]}
 */
export const getTargetBookingRooms = (bookingId) => {
    if (!bookingId) return [];
    const clean = String(bookingId).trim();
    const rooms = new Set();
    rooms.add(`booking_${clean}`);
    if (clean.startsWith('#')) {
        rooms.add(`booking_${clean.slice(1)}`);
    } else {
        rooms.add(`booking_#${clean}`);
    }
    return Array.from(rooms);
};

/**
 * Registers all real-time Socket.io event listeners and business logic (e.g. tracking and updates)
 * @param {object} io - The initialized socket.io server instance
 */
export const registerSocketHandlers = (io) => {
    io.on('connection', (socket) => {
        console.log(`User Connected: ${socket.id}`);

        // 1. Join Specific Booking Room (Customer and Worker)
        socket.on('join_booking_room', async (bookingId) => {
            if (!bookingId) return;

            const rooms = getTargetBookingRooms(bookingId);
            rooms.forEach((r) => socket.join(r));

            // Safely resolve and join both MongoDB _id and canonical bookingId rooms
            try {
                const bookingQuery = buildBookingQuery(bookingId);
                if (bookingQuery) {
                    const booking = await Booking.findOne(bookingQuery).select('_id bookingId');
                    if (booking) {
                        const canonicalId = String(booking.bookingId);
                        const mongoId = String(booking._id);
                        socket.join(`booking_${mongoId}`);
                        socket.join(`booking_${canonicalId}`);
                        if (canonicalId.startsWith('#')) {
                            socket.join(`booking_${canonicalId.slice(1)}`);
                        } else {
                            socket.join(`booking_#${canonicalId}`);
                        }
                    }
                }
            } catch (err) {
                // Non-blocking fallback
            }
        });

        // 1b. Join Worker Room (For real-time job requests, alerts, availability)
        socket.on('join_worker_room', (workerId) => {
            if (!workerId) return;
            const clean = String(workerId).trim();
            socket.join(`worker_${clean}`);
            socket.join('workers_all');
        });

        // 1c. Join Customer Room (For real-time booking updates, worker arrival, status)
        socket.on('join_customer_room', (customerId) => {
            if (!customerId) return;
            const clean = String(customerId).trim();
            socket.join(`customer_${clean}`);
            socket.join(`user_${clean}`);
            socket.join('customers_all');
        });

        socket.on('join_user_room', (userId) => {
            if (!userId) return;
            const clean = String(userId).trim();
            socket.join(`user_${clean}`);
            socket.join(`customer_${clean}`);
        });

        // 1c. Support Chat Rooms
        socket.on('join_support_ticket', (ticketId) => {
            if (!ticketId) return;
            const clean = String(ticketId).trim();
            socket.join(`support_${clean}`);
        });

        socket.on('join_admin_support', () => {
            socket.join('admin_support');
        });

        socket.on('join_user_support', (userId) => {
            if (!userId) return;
            const clean = String(userId).trim();
            socket.join(`support_user_${clean}`);
        });

        // 2. Real-time Worker Location Update (Broadcast via Socket.io & Cache in Redis with 60s TTL)
        socket.on('worker_location_update', async (data) => {
            const { bookingId, lat, lng, heading } = data || {};
            if (!bookingId) return;

            const targetRooms = getTargetBookingRooms(bookingId);

            // Broadcast real-time location to the booking room aliases (Does NOT touch MongoDB)
            io.to(targetRooms).emit('live_tracking', {
                lat: parseFloat(lat), 
                lng: parseFloat(lng), 
                heading: heading || 0, 
                timestamp: Date.now()
            });

            // Cache temporary live GPS in Redis with 60s TTL (Zero DB hits, auto-expires, zero memory leak)
            try {
                const cleanBookingId = String(bookingId).trim().replace(/^#/, '');
                await redis.set(
                    `tracking:booking:${cleanBookingId}`,
                    JSON.stringify({
                        lat: parseFloat(lat),
                        lng: parseFloat(lng),
                        heading: heading || 0,
                        timestamp: Date.now()
                    }),
                    'EX',
                    60
                );
            } catch (err) {
                console.warn('Redis live tracking cache warning:', err.message);
            }

            // Sync worker live location in User model if workerId provided
            if (data.workerId && !isNaN(lat) && !isNaN(lng)) {
                User.findByIdAndUpdate(data.workerId, {
                    location: { type: 'Point', coordinates: [parseFloat(lng), parseFloat(lat)] }
                }).catch(() => {});
            }

            // Backup unlock: first live GPS ping sets workerNavigationStartedAt
            // so customer Track works even if POST /start-navigation never landed.
            try {
                const query = buildBookingQuery(bookingId);
                if (!query) return;
                const updated = await Booking.findOneAndUpdate(
                    {
                        ...query,
                        workerNavigationStartedAt: null,
                        status: {
                            $in: [
                                'APPROVED',
                                'ACCEPTED',
                                'ARRIVED',
                                'ESTIMATION_GIVEN',
                                'READY_TO_START',
                                'IN_PROGRESS',
                            ],
                        },
                    },
                    { $set: { workerNavigationStartedAt: new Date() } },
                    { new: true }
                );
                if (updated) {
                    const customerId = String(updated.customer);
                    const rooms = [
                        ...getTargetBookingRooms(String(updated._id)),
                        ...getTargetBookingRooms(updated.bookingId),
                        `user_${customerId}`,
                        `customer_${customerId}`,
                    ];
                    io.to(rooms).emit('booking_status_update', {
                        bookingId: String(updated._id),
                        canonicalBookingId: updated.bookingId,
                        status: updated.status,
                        workerNavigationStarted: true,
                        workerNavigationStartedAt: updated.workerNavigationStartedAt,
                    });
                }
            } catch (err) {
                console.warn('workerNavigationStartedAt GPS unlock warning:', err.message);
            }
        });

        // 3. User Disconnection
        socket.on('disconnect', () => {
            console.log(`User Disconnected: ${socket.id}`);
        });
    });
};

