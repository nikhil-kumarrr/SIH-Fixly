import { Server } from 'socket.io';
import { createAdapter } from '@socket.io/redis-adapter';
import redis from './redis.js';
import { registerSocketHandlers } from '../sockets/tracking.js';
import { registerWebRTCSocketHandlers } from '../sockets/webrtcCallSocket.js';

let ioInstance = null;

/**
 * Initializes the Socket.io server and configures Redis Pub/Sub adapters
 * @param {object} httpServer - The native node HTTP server instance
 * @returns {object} - The initialized socket.io server instance
 */
export const initSocket = (httpServer) => {
    const io = new Server(httpServer, {
        cors: { origin: '*' }
    });

    ioInstance = io;

    // Redis Pub/Sub instances for horizontal scaling
    const pubClient = redis.duplicate();
    const subClient = redis.duplicate();

    pubClient.on('error', (err) => console.warn('[Socket.io Redis PubClient Error]', err.message));
    subClient.on('error', (err) => console.warn('[Socket.io Redis SubClient Error]', err.message));

    io.adapter(createAdapter(pubClient, subClient));

    // Delegate tracking and real-time business logic to sockets handler
    registerSocketHandlers(io);

    // Delegate WebRTC audio calling signaling & room management
    registerWebRTCSocketHandlers(io);

    return io;
};

/**
 * Returns the active Socket.io server instance
 * @returns {object|null}
 */
export const getIO = () => ioInstance;