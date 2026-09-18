import Razorpay from 'razorpay';
import crypto from 'crypto';
import Transaction from '../models/Transaction.js';
import Booking from '../models/Booking.js';
import User from '../models/User.js';
import Settings from '../models/Settings.js';
import WelfareAccount from '../models/WelfareAccount.js';
import WelfareTransaction from '../models/WelfareTransaction.js';
import { getPlatformSettings } from '../services/settingsService.js';
import { notifyUser, safeNotify } from '../services/notificationService.js';
import { getTargetBookingRooms } from '../sockets/tracking.js';
import { markCouponUsed } from '../services/couponService.js';

let razorpay = null;
if (process.env.RAZORPAY_KEY_ID && process.env.RAZORPAY_KEY_SECRET) {
    razorpay = new Razorpay({
        key_id: process.env.RAZORPAY_KEY_ID,
        key_secret: process.env.RAZORPAY_KEY_SECRET,
    });
}

const razorpayMode = () =>
    process.env.RAZORPAY_KEY_ID?.startsWith('rzp_live') ? 'live' : 'test';

const finalizeJobAfterPayment = async (booking, io) => {
    if (io) {
        const targetRooms = [
            ...getTargetBookingRooms(booking._id),
            ...getTargetBookingRooms(booking.bookingId),
        ];
        io.to(targetRooms).emit('booking_status_update', {
            bookingId: booking._id,
            canonicalBookingId: booking.bookingId,
            status: booking.status,
            paymentStatus: 'PAID',
            transactionId: booking.invoice?.transactionId,
            invoice: booking.invoice,
        });
    }

    safeNotify(async () => {
        await notifyUser({
            recipient: booking.customer,
            eventType: 'PAYMENT_SUCCESS',
            entityId: booking._id,
            bookingId: booking._id,
            dedupeKey: `PAYMENT_SUCCESS:${booking._id}`,
        });
        if (booking.worker) {
            await notifyUser({
                recipient: booking.worker,
                eventType: 'PAYMENT_RECEIVED',
                entityId: booking._id,
                bookingId: booking._id,
                dedupeKey: `PAYMENT_RECEIVED:${booking._id}:${booking.worker}`,
            });
        }
    });
};

const creditWorkerWallet = async ({
    workerId,
    booking,
    transaction,
    paymentId,
}) => {
    if (!workerId) return 0;
    const worker = await User.findById(workerId);
    if (!worker) return 0;
    if (!worker.workerProfile) worker.workerProfile = {};
    if (!worker.workerProfile.walletTransactions) {
        worker.workerProfile.walletTransactions = [];
    }

    const alreadyCredited = worker.workerProfile.walletTransactions.some(
        (tx) => tx.transactionId === paymentId
    );
    if (alreadyCredited) {
        return worker.workerProfile.walletBalance || 0;
    }

    const settings = await getPlatformSettings();
    const commPercent = settings.workerCommissionPercent !== undefined && settings.workerCommissionPercent !== null
        ? Number(settings.workerCommissionPercent)
        : (Number(settings.platformCommissionPercent) || 0);
    const welfarePercent = settings.cooperativeWelfarePercent !== undefined && settings.cooperativeWelfarePercent !== null
        ? Number(settings.cooperativeWelfarePercent)
        : 0;

    // Coupon is Fixly → customer subsidy. Worker gross = pre-coupon invoice.
    const inv = booking.invoice || {};
    const couponDiscount = Number(inv.couponDiscount) || 0;
    const preCouponFromLines =
        (Number(inv.baseServiceFee) || 0) +
        (Number(inv.extraPartsTotal) || 0) +
        (Number(inv.platformFee) || 0) +
        (Number(inv.urgentFee) || 0);
    const customerPaid = Number(transaction.amount || inv.totalAmount || 0);
    const totalAmt =
        preCouponFromLines > 0
            ? preCouponFromLines
            : Math.max(0, customerPaid + couponDiscount);
    const platformCommissionDeducted = Math.round(totalAmt * (commPercent / 100));
    const welfareAmount = Math.round(totalAmt * (welfarePercent / 100));
    const totalDeductions = platformCommissionDeducted + welfareAmount;
    const workerPayout = Math.max(0, totalAmt - totalDeductions);

    worker.workerProfile.walletBalance = Number(
        (worker.workerProfile.walletBalance || 0) + workerPayout
    );
    worker.workerProfile.totalEarnings = Number(
        (worker.workerProfile.totalEarnings || 0) + workerPayout
    );
    worker.workerProfile.totalJobs = Number(
        (worker.workerProfile.totalJobs || 0) + 1
    );
    const couponNote =
        couponDiscount > 0
            ? `, Coupon subsidy (Fixly): ₹${couponDiscount} (customer paid ₹${customerPaid})`
            : '';
    worker.workerProfile.walletTransactions.push({
        transactionId: paymentId,
        bookingId: booking._id,
        amount: workerPayout,
        grossAmount: totalAmt,
        platformFeeDeducted: platformCommissionDeducted,
        welfareDeducted: welfareAmount,
        type: 'CREDIT',
        description: `Job earnings credited. Gross: ₹${totalAmt}, Platform fee cut: -₹${platformCommissionDeducted} (${commPercent}%), Welfare contribution cut: -₹${welfareAmount} (${welfarePercent}%), Net Payout: ₹${workerPayout}${couponNote}`,
        createdAt: new Date(),
    });
    await worker.save();

    // Cooperative Welfare Fund Accounting Sync
    if (welfareAmount > 0) {
        try {
            let welfareAcc = await WelfareAccount.findOne({ worker: workerId });
            if (!welfareAcc) {
                welfareAcc = await WelfareAccount.create({ worker: workerId });
            }
            welfareAcc.balance = (welfareAcc.balance || 0) + welfareAmount;
            welfareAcc.totalContributed = (welfareAcc.totalContributed || 0) + welfareAmount;
            welfareAcc.lastContribution = new Date();
            if (welfareAcc.totalContributed >= 500) {
                welfareAcc.trainingEligible = true;
                welfareAcc.insuranceActive = true;
            }
            await welfareAcc.save();

            await WelfareTransaction.create({
                worker: workerId,
                amount: welfareAmount,
                type: 'contribution',
                note: `Cooperative welfare contribution for Booking ${booking.bookingId || booking._id}`,
                booking: booking._id,
            });
        } catch (welfareErr) {
            console.warn('Welfare account sync warning:', welfareErr.message);
        }
    }

    return workerPayout;
};

export const getPaymentConfig = (_req, res) => {
    const keyId = process.env.RAZORPAY_KEY_ID;
    if (!keyId) {
        return res.status(503).json({
            success: false,
            message: 'Razorpay is not configured',
        });
    }
    return res.status(200).json({
        success: true,
        keyId,
        currency: 'INR',
        mode: razorpayMode(),
    });
};

export const createOrder = async (req, res) => {
    try {
        if (!razorpay || !process.env.RAZORPAY_KEY_ID) {
            return res.status(503).json({
                success: false,
                message: 'Razorpay is not configured',
            });
        }

        const { bookingId, amount } = req.body;
        const customerId = req.user.id;
        const booking = await Booking.findById(bookingId);
        if (!booking) {
            return res.status(404).json({ success: false, message: 'Booking not found' });
        }
        if (String(booking.customer) !== String(customerId) && req.user.role !== 'admin') {
            return res.status(403).json({ success: false, message: 'Not your booking' });
        }
        if (booking.invoice?.paymentStatus === 'PAID') {
            return res.status(400).json({ success: false, message: 'This booking has already been paid.' });
        }

        if (booking.status === 'CANCELLED') {
            return res.status(400).json({
                success: false,
                message: 'This booking has been cancelled. Payment cannot be initiated.',
            });
        }

        if (booking.status === 'IN_PROGRESS') {
            return res.status(400).json({
                success: false,
                message: 'The service is currently in progress. You cannot make a payment while the worker is actively working. Please wait until the worker completes the service.',
            });
        }

        if (!['PAYMENT_PENDING', 'COMPLETED'].includes(booking.status)) {
            return res.status(400).json({
                success: false,
                message: 'Payment can only be initiated after the worker has completed the service. The service is not yet marked as completed.',
            });
        }

        const orderAmount = Math.round(Number(amount) * 100);
        if (!Number.isFinite(orderAmount) || orderAmount < 100) {
            return res.status(400).json({ success: false, message: 'Invalid payment amount' });
        }

        const existing = await Transaction.findOne({
            bookingId,
            status: 'pending',
        }).sort({ createdAt: -1 });

        let orderId = existing?.orderId;
        if (!orderId || String(orderId).startsWith('order_test_')) {
            const order = await razorpay.orders.create({
                amount: orderAmount,
                currency: 'INR',
                receipt: `receipt_booking_${bookingId}`.slice(0, 40),
            });
            orderId = order.id;
        }

        const description = `Fixly payment for ${booking.bookingId || bookingId}`;
        const transaction = existing
            ? await Transaction.findByIdAndUpdate(
                existing._id,
                {
                    orderId,
                    amount: Number(amount),
                    description,
                    workerId: booking.worker || existing.workerId,
                    paymentMethod: 'Razorpay',
                    status: 'pending',
                },
                { returnDocument: 'after' }
            )
            : await Transaction.create({
                customerId,
                workerId: booking.worker || customerId,
                bookingId,
                orderId,
                amount: Number(amount),
                status: 'pending',
                paymentMethod: 'Razorpay',
                description,
            });

        return res.status(200).json({
            success: true,
            orderId,
            transactionId: transaction._id,
            amount: orderAmount,
            currency: 'INR',
            keyId: process.env.RAZORPAY_KEY_ID,
            mode: razorpayMode(),
        });
    } catch (error) {
        console.error('Create order error:', error);
        return res.status(500).json({ success: false, message: error.message });
    }
};

export const verifyPayment = async (req, res) => {
    try {
        const {
            razorpay_order_id,
            razorpay_payment_id,
            razorpay_signature,
            bookingId,
        } = req.body;

        if (!process.env.RAZORPAY_KEY_SECRET) {
            return res.status(503).json({
                success: false,
                message: 'Razorpay is not configured',
            });
        }

        const body = `${razorpay_order_id}|${razorpay_payment_id}`;
        const expectedSignature = crypto
            .createHmac('sha256', process.env.RAZORPAY_KEY_SECRET)
            .update(body)
            .digest('hex');
        const isAuthentic = expectedSignature === razorpay_signature;

        let transaction = await Transaction.findOne({ orderId: razorpay_order_id });
        if (!transaction && bookingId) {
            transaction = await Transaction.findOne({ bookingId }).sort({ createdAt: -1 });
        }
        if (!transaction) {
            return res.status(404).json({
                success: false,
                message: 'Transaction not found for this order/booking',
            });
        }

        if (!isAuthentic) {
            transaction.status = 'failed';
            await transaction.save();
            if (bookingId || transaction.bookingId) {
                await Booking.findByIdAndUpdate(bookingId || transaction.bookingId, {
                    'invoice.paymentStatus': 'FAILED',
                });
            }
            safeNotify(() => notifyUser({
                recipient: transaction.customerId || req.user.id,
                eventType: 'PAYMENT_FAILED',
                entityId: bookingId || transaction.bookingId,
                bookingId: bookingId || transaction.bookingId,
                dedupeKey: `PAYMENT_FAILED:${transaction._id}`,
            }));
            return res.status(400).json({
                success: false,
                message: 'Invalid Razorpay payment signature',
                status: 'failed',
            });
        }

        const finalPaymentId = razorpay_payment_id;
        if (transaction.status === 'success' && transaction.paymentId) {
            return res.status(200).json({
                success: true,
                message: 'Payment already verified',
                paymentId: transaction.paymentId,
                transactionId: transaction._id,
                status: 'success',
            });
        }

        transaction.paymentId = finalPaymentId;
        transaction.signature = razorpay_signature;
        transaction.status = 'success';
        transaction.description =
            transaction.description || `Razorpay ${finalPaymentId}`;
        await transaction.save();

        const booking = await Booking.findById(bookingId || transaction.bookingId);
        if (booking) {
            booking.invoice = booking.invoice || {};
            booking.invoice.paymentStatus = 'PAID';
            booking.invoice.paymentMethod = 'Razorpay';
            booking.invoice.transactionId = finalPaymentId;
            booking.status = 'COMPLETED';
            booking.jobCompletedAt = booking.jobCompletedAt || new Date();

            const couponDiscount = Number(booking.invoice.couponDiscount) || 0;
            const calculatedTotal = Math.max(
                0,
                (Number(booking.invoice.baseServiceFee) || 0) +
                    (Number(booking.invoice.extraPartsTotal) || 0) +
                    (Number(booking.invoice.platformFee) || 0) +
                    (Number(booking.invoice.urgentFee) || 0) -
                    couponDiscount,
            );

            if (calculatedTotal > 0) {
                booking.invoice.totalAmount = calculatedTotal;
                transaction.amount = calculatedTotal;
                await transaction.save();
            }

            await booking.save();

            // Redeem coupon only after payment succeeds.
            if (booking.invoice.couponCode) {
                await markCouponUsed(
                    booking.invoice.couponCode,
                    booking.customer || transaction.customerId || req.user?.id,
                );
            }

            await creditWorkerWallet({
                workerId: booking.worker || transaction.workerId,
                booking,
                transaction,
                paymentId: finalPaymentId,
            });

            await finalizeJobAfterPayment(booking, req.app.get('io'));

            safeNotify(async () => {
                await notifyUser({
                    recipient: booking.customer,
                    eventType: 'PAYMENT_SUCCESS',
                    entityId: booking._id,
                    bookingId: booking._id,
                    dedupeKey: `PAYMENT_SUCCESS:${booking._id}:${finalPaymentId}`,
                });
                if (booking.worker) {
                    await notifyUser({
                        recipient: booking.worker,
                        eventType: 'PAYMENT_RECEIVED',
                        entityId: booking._id,
                        bookingId: booking._id,
                        dedupeKey: `PAYMENT_RECEIVED:${booking._id}:${finalPaymentId}`,
                    });
                    await notifyUser({
                        recipient: booking.worker,
                        eventType: 'WALLET_CREDITED',
                        entityId: booking._id,
                        bookingId: booking._id,
                        dedupeKey: `WALLET_CREDITED:${finalPaymentId}`,
                    });
                }
            });
        }

        return res.status(200).json({
            success: true,
            message: 'Payment verified, job completed, worker wallet credited',
            paymentId: finalPaymentId,
            transactionId: transaction._id,
            status: 'success',
        });
    } catch (error) {
        console.error('Verify Payment Error:', error);
        return res.status(500).json({ success: false, message: error.message });
    }
};

export const getCustomerWalletAndHistory = async (req, res) => {
    try {
        const customerId = req.user.id;
        const transactions = await Transaction.find({ customerId })
            .populate('workerId', 'name phone')
            .populate('bookingId', 'bookingId status invoice addOns')
            .sort({ createdAt: -1 });

        const history = transactions.map((t) => {
            const json = t.toObject();
            const booking = json.bookingId;

            let effectiveAmount = Number(json.amount) || 0;
            if (booking && booking.invoice) {
                const inv = booking.invoice;
                const calculatedTotal =
                    (Number(inv.baseServiceFee) || 0) +
                    (Number(inv.extraPartsTotal) || 0) +
                    (Number(inv.platformFee) || 0) +
                    (Number(inv.urgentFee) || 0);

                if (calculatedTotal > 0) {
                    inv.totalAmount = calculatedTotal;
                }

                // If invoice is marked PAID, booking status should show COMPLETED
                if (inv.paymentStatus === 'PAID' && (booking.status === 'PAYMENT_PENDING' || booking.status === 'IN_PROGRESS')) {
                    booking.status = 'COMPLETED';
                }

                // Authoritative transaction amount matches the invoice breakdown
                if (inv.totalAmount > 0) {
                    effectiveAmount = inv.totalAmount;
                }
            }

            return {
                ...json,
                amount: effectiveAmount,
                transactionId: json.paymentId || json.orderId || String(json._id),
                description:
                    json.description ||
                    `Razorpay payment${json.paymentId ? ` • ${json.paymentId}` : ''}`,
                type: 'DEBIT',
            };
        });

        const successfulTxs = history.filter((t) => t.status === 'success');
        const totalSpent = successfulTxs.reduce((acc, curr) => acc + (Number(curr.amount) || 0), 0);

        return res.status(200).json({
            success: true,
            walletBalance: 0,
            totalSpent,
            history,
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

export const getWorkerWalletAndHistory = async (req, res) => {
    try {
        const workerId = req.user.id;
        const worker = await User.findById(workerId);
        if (!worker) {
            return res.status(404).json({ success: false, message: 'Worker not found' });
        }

        const transactions = await Transaction.find({ workerId, status: 'success' })
            .populate('customerId', 'name phone email')
            .populate('bookingId', 'bookingId status invoice')
            .sort({ createdAt: -1 });

        const profile = worker.workerProfile || {};
        const walletTransactions = (profile.walletTransactions || [])
            .slice()
            .reverse()
            .map((t) => ({
                _id: t._id,
                transactionId: t.transactionId,
                description: t.description,
                type: t.type || 'CREDIT',
                amount: t.amount,
                grossAmount: t.grossAmount || t.amount,
                platformFeeDeducted: t.platformFeeDeducted || 0,
                welfareDeducted: t.welfareDeducted || 0,
                bookingId: t.bookingId,
                createdAt: t.createdAt,
            }));

        return res.status(200).json({
            success: true,
            walletBalance: profile.walletBalance || 0,
            totalEarnings: profile.totalEarnings || 0,
            totalJobs: profile.totalJobs || 0,
            walletTransactions,
            transactions: walletTransactions,
            history: walletTransactions,
            adminTransactions: transactions,
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};
