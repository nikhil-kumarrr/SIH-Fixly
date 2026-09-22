import SupportTicket from '../models/SupportTicket.js';
import User from '../models/User.js';
import { fail, ok, isObjectId } from '../utils/http.js';
import { notifyUser, safeNotify } from '../services/notificationService.js';
import {
    processSupportMessageWithAI,
    getDefaultQuickReplies,
} from '../services/aiSupportService.js';

const CATEGORIES = new Set([
    'SERVICE_DISPUTE', 'WORKER_CUSTOMER_ISSUE', 'PAYMENT', 'SAFETY', 'BOOKING', 'ACCOUNT', 'OTHER',
]);

/**
 * Helper: emit socket events safely
 */
const emitSocketEvent = (req, room, event, data) => {
    try {
        const io = req?.app?.get('io');
        if (io) {
            io.to(room).emit(event, data);
        }
    } catch (e) {
        console.warn('Socket emit error:', e.message);
    }
};

/**
 * Get active support ticket for current user, or create one with AI welcome message
 */
export const getActiveOrCreateTicket = async (req, res) => {
    try {
        const userId = req.user.id;
        const userRole = req.user.role === 'worker' ? 'worker' : 'customer';

        // Check for an active open ticket
        let ticket = await SupportTicket.findOne({
            createdBy: userId,
            status: { $nin: ['RESOLVED', 'CLOSED'] },
        }).populate('assignedTo', 'name email role');

        if (!ticket) {
            // Generate welcome message tailored to role
            const welcomeText = userRole === 'worker'
                ? `Hello ${req.user.name || 'Partner'}! I'm Fixly AI Assistant. I'm here 24/7 to help you with job payouts, KYC verification, safety, or order disputes. How can I assist you today?`
                : `Hello ${req.user.name || 'there'}! I'm Fixly AI Assistant. How can I help you with your booking, technician tracking, invoice, or refund today?`;

            const quickReplies = getDefaultQuickReplies(userRole);

            ticket = await SupportTicket.create({
                ticketNumber: `TKT-${Date.now().toString(36).toUpperCase()}`,
                createdBy: userId,
                userRole,
                subject: 'Fixly Help & Support',
                description: 'Support chat initiated',
                handledBy: 'BOT',
                status: 'BOT_ACTIVE',
                quickReplies,
                messages: [
                    {
                        sender: null,
                        senderName: 'Fixly AI',
                        role: 'ai',
                        body: welcomeText,
                        quickReplies,
                    },
                ],
            });
        }

        return ok(res, { data: ticket });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

/**
 * User sends a message in the support chat
 */
/**
 * Reset / Start a fresh support chat
 */
export const resetUserTicket = async (req, res) => {
    try {
        const userId = req.user.id;
        const userRole = req.user.role === 'worker' ? 'worker' : 'customer';

        // Close any active tickets
        await SupportTicket.updateMany(
            { createdBy: userId, status: { $nin: ['RESOLVED', 'CLOSED'] } },
            { $set: { status: 'RESOLVED', resolvedAt: new Date() } }
        );

        // Create a fresh new ticket
        const welcomeText = userRole === 'worker'
            ? `Hello ${req.user.name || 'Partner'}! I'm Fixly AI Assistant. I'm here 24/7 to help you with job payouts, KYC verification, safety, or order disputes. How can I assist you today?`
            : `Hello ${req.user.name || 'there'}! I'm Fixly AI Assistant. How can I help you with your booking, technician tracking, invoice, or refund today?`;

        const quickReplies = getDefaultQuickReplies(userRole);

        const ticket = await SupportTicket.create({
            ticketNumber: `TKT-${Date.now().toString(36).toUpperCase()}`,
            createdBy: userId,
            userRole,
            subject: 'Fixly Help & Support',
            description: 'New support conversation started',
            handledBy: 'BOT',
            status: 'BOT_ACTIVE',
            quickReplies,
            messages: [
                {
                    sender: null,
                    senderName: 'Fixly AI',
                    role: 'ai',
                    body: welcomeText,
                    quickReplies,
                },
            ],
        });

        emitSocketEvent(req, `support_${ticket._id}`, 'support:new_ticket', { ticket });

        return ok(res, { data: ticket });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

/**
 * User sends a message in the support chat
 */
export const sendUserMessage = async (req, res) => {
    try {
        const { message, text, ticketId, attachments, mediaType } = req.body || {};
        const attList = Array.isArray(attachments) ? attachments : (attachments ? [attachments] : []);
        let msgText = (message || text || '').trim();
        if (!msgText && attList.length > 0) {
            msgText = mediaType === 'image' ? '[Photo Attachment]' : (mediaType === 'video' ? '[Video Attachment]' : (mediaType === 'audio' ? '[Voice Note]' : '[Media Attachment]'));
        }
        if (!msgText && attList.length === 0) {
            return fail(res, 400, 'VALIDATION_ERROR', 'Message text or attachment is required');
        }

        const userId = req.user.id;
        const userRole = req.user.role === 'worker' ? 'worker' : 'customer';

        // Find target ticket
        let ticket = null;
        if (ticketId && isObjectId(ticketId)) {
            ticket = await SupportTicket.findOne({ _id: ticketId, createdBy: userId });
        } else {
            ticket = await SupportTicket.findOne({
                createdBy: userId,
                status: { $nin: ['RESOLVED', 'CLOSED'] },
            });
        }

        // If no open ticket exists, create one
        if (!ticket) {
            ticket = await SupportTicket.create({
                ticketNumber: `TKT-${Date.now().toString(36).toUpperCase()}`,
                createdBy: userId,
                userRole,
                subject: msgText.slice(0, 50),
                description: msgText,
                handledBy: 'BOT',
                status: 'BOT_ACTIVE',
                messages: [],
            });
        }

        // Check if user is asking to switch back to bot
        const isSwitchToBot = ['switch to bot', 'talk to ai', 'start fresh', 'restart bot', 'ai assistant'].some(k => msgText.toLowerCase().includes(k));
        if (isSwitchToBot) {
            ticket.handledBy = 'BOT';
            ticket.status = 'BOT_ACTIVE';
        }

        // 1. Add User's message
        const userMsg = {
            sender: userId,
            senderName: req.user.name || (userRole === 'worker' ? 'Worker' : 'Customer'),
            role: userRole,
            body: msgText,
            attachments: attList,
            mediaType: mediaType || null,
            createdAt: new Date(),
        };
        ticket.messages.push(userMsg);
        ticket.lastMessageAt = new Date();

        // 2. If already handled by HUMAN / AGENT and not switching to bot
        if ((ticket.handledBy === 'HUMAN' || ticket.status === 'AGENT_ACTIVE' || ticket.status === 'ESCALATED') && !isSwitchToBot) {
            await ticket.save();

            // Notify Admin Desk in real-time
            emitSocketEvent(req, 'admin_support', 'support:new_user_message', {
                ticketId: ticket._id,
                message: userMsg,
                ticket,
            });
            emitSocketEvent(req, `support_${ticket._id}`, 'support:message_received', {
                ticketId: ticket._id,
                message: userMsg,
            });

            return ok(res, { data: ticket });
        }

        // 3. Otherwise, handled by AI BOT
        const aiResult = await processSupportMessageWithAI({
            user: req.user,
            message: msgText,
            conversationHistory: ticket.messages,
        });

        if (aiResult.shouldEscalate) {
            // Escalate to human support desk
            ticket.handledBy = 'HUMAN';
            ticket.status = 'ESCALATED';
            ticket.quickReplies = aiResult.quickReplies || ['Check status', 'Cancel request'];

            const escalationMsg = {
                sender: null,
                senderName: 'Fixly AI (Escalation)',
                role: 'system',
                body: aiResult.reply,
                quickReplies: ticket.quickReplies,
                createdAt: new Date(),
            };
            ticket.messages.push(escalationMsg);
            await ticket.save();

            // Broadcast to Admin real-time alerts
            emitSocketEvent(req, 'admin_support', 'support:ticket_escalated', {
                ticketId: ticket._id,
                ticket,
                user: {
                    id: req.user.id,
                    name: req.user.name,
                    role: userRole,
                    phone: req.user.phone,
                },
            });
            emitSocketEvent(req, `support_${ticket._id}`, 'support:message_received', {
                ticketId: ticket._id,
                message: escalationMsg,
                status: 'ESCALATED',
            });

            return ok(res, { data: ticket });
        }

        // Normal AI Bot reply
        ticket.quickReplies = aiResult.quickReplies;
        const aiReplyMsg = {
            sender: null,
            senderName: 'Fixly AI',
            role: 'ai',
            body: aiResult.reply,
            quickReplies: aiResult.quickReplies,
            createdAt: new Date(),
        };
        ticket.messages.push(aiReplyMsg);
        await ticket.save();

        // Broadcast to client socket
        emitSocketEvent(req, `support_${ticket._id}`, 'support:message_received', {
            ticketId: ticket._id,
            message: aiReplyMsg,
            quickReplies: aiResult.quickReplies,
        });

        return ok(res, { data: ticket });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

/**
 * Escalate active ticket to Human Support Agent
 */
export const escalateActiveTicket = async (req, res) => {
    try {
        const userId = req.user.id;
        const { ticketId } = req.body || {};

        let ticket = null;
        if (ticketId && isObjectId(ticketId)) {
            ticket = await SupportTicket.findOne({ _id: ticketId, createdBy: userId });
        } else {
            ticket = await SupportTicket.findOne({
                createdBy: userId,
                status: { $nin: ['RESOLVED', 'CLOSED'] },
            });
        }

        if (!ticket) {
            return fail(res, 404, 'NOT_FOUND', 'No active ticket found to escalate');
        }

        ticket.handledBy = 'HUMAN';
        ticket.status = 'ESCALATED';
        ticket.quickReplies = ['Check queue position', 'Add more details'];

        const systemMsg = {
            sender: null,
            senderName: 'System',
            role: 'system',
            body: 'You have requested to speak with a human support agent. Our support desk has received your ticket and an agent will take over shortly.',
            createdAt: new Date(),
        };
        ticket.messages.push(systemMsg);
        ticket.lastMessageAt = new Date();
        await ticket.save();

        // Broadcast to admin
        emitSocketEvent(req, 'admin_support', 'support:ticket_escalated', {
            ticketId: ticket._id,
            ticket,
            user: {
                id: req.user.id,
                name: req.user.name,
                role: req.user.role,
                phone: req.user.phone,
            },
        });
        emitSocketEvent(req, `support_${ticket._id}`, 'support:status_changed', {
            ticketId: ticket._id,
            status: 'ESCALATED',
            handledBy: 'HUMAN',
        });

        return ok(res, { data: ticket });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

/**
 * Create a formal ticket (with subject & description)
 */
export const createTicket = async (req, res) => {
    try {
        const { subject, description, category, bookingId, attachments } = req.body || {};
        if (!subject || !description) {
            return fail(res, 400, 'VALIDATION_ERROR', 'subject and description required');
        }
        const cat = CATEGORIES.has(category) ? category : 'OTHER';
        const userRole = req.user.role === 'worker' ? 'worker' : 'customer';

        const ticket = await SupportTicket.create({
            ticketNumber: `TKT-${Date.now().toString(36).toUpperCase()}`,
            createdBy: req.user.id,
            userRole,
            booking: bookingId && isObjectId(bookingId) ? bookingId : null,
            category: cat,
            subject,
            description,
            handledBy: 'BOT',
            status: 'BOT_ACTIVE',
            attachments: Array.isArray(attachments) ? attachments : [],
            messages: [{
                sender: req.user.id,
                senderName: req.user.name,
                role: userRole,
                body: description,
            }],
        });

        // Run through AI assistant
        const aiResult = await processSupportMessageWithAI({
            user: req.user,
            message: description,
        });

        ticket.quickReplies = aiResult.quickReplies;
        ticket.messages.push({
            sender: null,
            senderName: 'Fixly AI',
            role: 'ai',
            body: aiResult.reply,
            quickReplies: aiResult.quickReplies,
        });
        if (aiResult.shouldEscalate) {
            ticket.status = 'ESCALATED';
            ticket.handledBy = 'HUMAN';
        }
        await ticket.save();

        return ok(res, { data: ticket }, 201);
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

export const listMyTickets = async (req, res) => {
    try {
        const tickets = await SupportTicket.find({ createdBy: req.user.id }).sort({ updatedAt: -1 });
        return ok(res, { data: tickets });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

export const getTicket = async (req, res) => {
    try {
        const ticket = await SupportTicket.findById(req.params.id)
            .populate('createdBy', 'name email phone role')
            .populate('assignedTo', 'name email role')
            .populate('booking', 'bookingId status service category invoice');
        if (!ticket) return fail(res, 404, 'NOT_FOUND', 'Ticket not found');
        const owner = String(ticket.createdBy?._id || ticket.createdBy) === String(req.user.id);
        if (!owner && req.user.role !== 'admin') {
            return fail(res, 403, 'FORBIDDEN', 'You do not have access to this resource');
        }
        return ok(res, { data: ticket });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

export const addTicketMessage = async (req, res) => {
    try {
        const { body, message } = req.body || {};
        const text = (body || message || '').trim();
        if (!text) return fail(res, 400, 'VALIDATION_ERROR', 'body/message required');

        const ticket = await SupportTicket.findById(req.params.id);
        if (!ticket) return fail(res, 404, 'NOT_FOUND', 'Ticket not found');

        const owner = String(ticket.createdBy) === String(req.user.id);
        const isAdmin = req.user.role === 'admin';
        if (!owner && !isAdmin) {
            return fail(res, 403, 'FORBIDDEN', 'You do not have access to this resource');
        }

        const msgRole = isAdmin ? 'admin' : (ticket.userRole || req.user.role);
        const newMsg = {
            sender: req.user.id,
            senderName: req.user.name || (isAdmin ? 'Support Agent' : 'User'),
            role: msgRole,
            body: text,
            createdAt: new Date(),
        };

        ticket.messages.push(newMsg);
        ticket.lastMessageAt = new Date();

        if (isAdmin) {
            ticket.status = 'AGENT_ACTIVE';
            ticket.handledBy = 'HUMAN';
            ticket.assignedTo = req.user.id;
        }

        await ticket.save();

        if (isAdmin) {
            safeNotify(() => notifyUser({
                recipient: ticket.createdBy,
                eventType: 'SUPPORT_REPLY',
                entityId: ticket._id,
                dedupeKey: `SUPPORT_REPLY:${ticket._id}:${ticket.messages.length}`,
            }));
            emitSocketEvent(req, `support_${ticket._id}`, 'support:agent_message', {
                ticketId: ticket._id,
                message: newMsg,
            });
        } else {
            emitSocketEvent(req, 'admin_support', 'support:new_user_message', {
                ticketId: ticket._id,
                message: newMsg,
                ticket,
            });
        }

        return ok(res, { data: ticket });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

export const closeTicket = async (req, res) => {
    try {
        const query = req.user.role === 'admin'
            ? { _id: req.params.id }
            : { _id: req.params.id, createdBy: req.user.id };

        const ticket = await SupportTicket.findOne(query);
        if (!ticket) return fail(res, 404, 'NOT_FOUND', 'Ticket not found');

        ticket.status = 'RESOLVED';
        ticket.resolvedAt = new Date();
        await ticket.save();

        emitSocketEvent(req, `support_${ticket._id}`, 'support:status_changed', {
            ticketId: ticket._id,
            status: 'RESOLVED',
        });

        return ok(res, { data: ticket });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

// =========================================================================
// ADMIN SPECIFIC ENDPOINTS
// =========================================================================

export const adminListTickets = async (req, res) => {
    try {
        const { status, handledBy, userRole, search } = req.query || {};
        const query = {};

        if (status && status !== 'ALL') {
            query.status = status;
        }
        if (handledBy) {
            query.handledBy = handledBy;
        }
        if (userRole) {
            query.userRole = userRole;
        }
        if (search) {
            query.$or = [
                { ticketNumber: { $regex: search, $options: 'i' } },
                { subject: { $regex: search, $options: 'i' } },
                { description: { $regex: search, $options: 'i' } },
            ];
        }

        const tickets = await SupportTicket.find(query)
            .populate('createdBy', 'name email phone role avatar')
            .populate('assignedTo', 'name email role')
            .sort({ lastMessageAt: -1, updatedAt: -1 });

        return ok(res, { data: tickets });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

export const adminTakeoverTicket = async (req, res) => {
    try {
        const ticket = await SupportTicket.findById(req.params.id);
        if (!ticket) return fail(res, 404, 'NOT_FOUND', 'Ticket not found');

        ticket.handledBy = 'HUMAN';
        ticket.status = 'AGENT_ACTIVE';
        ticket.assignedTo = req.user.id;

        const takeoverMsg = {
            sender: req.user.id,
            senderName: req.user.name || 'Support Agent',
            role: 'system',
            body: `Admin Support Agent (${req.user.name || 'Support Desk'}) has joined the chat and taken over from AI. How can we help?`,
            createdAt: new Date(),
        };
        ticket.messages.push(takeoverMsg);
        ticket.lastMessageAt = new Date();
        await ticket.save();

        emitSocketEvent(req, `support_${ticket._id}`, 'support:takeover', {
            ticketId: ticket._id,
            agent: {
                id: req.user.id,
                name: req.user.name || 'Support Agent',
            },
            message: takeoverMsg,
        });

        emitSocketEvent(req, 'admin_support', 'support:ticket_updated', {
            ticketId: ticket._id,
            ticket,
        });

        return ok(res, { data: ticket });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

export const adminPatchTicket = async (req, res) => {
    try {
        const { status, assignedTo, priority, handledBy } = req.body || {};
        const ticket = await SupportTicket.findById(req.params.id);
        if (!ticket) return fail(res, 404, 'NOT_FOUND', 'Ticket not found');

        if (status) ticket.status = status;
        if (assignedTo) ticket.assignedTo = assignedTo;
        if (priority) ticket.priority = priority;
        if (handledBy) ticket.handledBy = handledBy;
        if (status === 'RESOLVED' || status === 'CLOSED') ticket.resolvedAt = new Date();

        await ticket.save();

        if (status) {
            safeNotify(() => notifyUser({
                recipient: ticket.createdBy,
                eventType: 'SUPPORT_STATUS_UPDATED',
                entityId: ticket._id,
                dedupeKey: `SUPPORT_STATUS_UPDATED:${ticket._id}:${ticket.status}`,
            }));

            emitSocketEvent(req, `support_${ticket._id}`, 'support:status_changed', {
                ticketId: ticket._id,
                status: ticket.status,
                handledBy: ticket.handledBy,
            });
        }

        return ok(res, { data: ticket });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};
