import React from 'react';
import Modal from '../common/Modal';
import { Download, Printer, ShieldCheck, CheckCircle } from 'lucide-react';

export default function InvoiceModal({ payment, isOpen, onClose }) {
  if (!payment) return null;

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Official GST Tax Invoice & Cooperative Escrow Receipt"
      subtitle={`Invoice #${payment.invoiceNumber || 'INV-2025-8891'} • Ref: ${payment.gatewayRef || 'UPI/ESCROW'}`}
      maxWidth="640px"
      footer={
        <>
          <button
            onClick={() => window.print()}
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '6px',
              padding: '8px 16px',
              borderRadius: '8px',
              border: '1px solid #cbd5e1',
              color: '#334155',
              fontSize: '13px',
              fontWeight: '600',
            }}
          >
            <Printer size={15} />
            <span>Print</span>
          </button>
          <button
            onClick={() => {
              alert(`Downloading PDF for ${payment.invoiceNumber}`);
              onClose();
            }}
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '6px',
              padding: '8px 20px',
              borderRadius: '8px',
              backgroundColor: 'var(--primary-brand)',
              color: '#ffffff',
              fontSize: '13px',
              fontWeight: '600',
            }}
          >
            <Download size={15} />
            <span>Download PDF</span>
          </button>
        </>
      }
    >
      <div style={{ display: 'flex', flexDirection: 'column', gap: '18px' }}>
        {/* Invoice Header */}
        <div style={{ display: 'flex', justifyContent: 'space-between', borderBottom: '1.5px solid #e6ede8', paddingBottom: '14px' }}>
          <div>
            <div style={{ fontWeight: '800', fontSize: '18px', color: '#14532d' }}>
              Cooperative Gig Services Platform
            </div>
            <div style={{ fontSize: '12px', color: '#64748b' }}>
              Govt. Registered Multi-State Gig Cooperative Society
            </div>
            <div style={{ fontSize: '12px', color: '#64748b' }}>
              GSTIN: 07AAATC1234F1Z5 • PAN: AAATC1234F
            </div>
          </div>
          <div style={{ textAlign: 'right' }}>
            <div style={{ fontSize: '12px', color: '#64748b' }}>Date of Issue</div>
            <div style={{ fontWeight: '700', fontSize: '14px', color: '#0f172a' }}>{payment.date}</div>
            <div style={{ fontSize: '12px', color: '#15803d', fontWeight: '600', marginTop: '2px' }}>
              Status: {payment.status}
            </div>
          </div>
        </div>

        {/* Bill To / Service Provider Grid */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '14px', fontSize: '12.5px' }}>
          <div style={{ backgroundColor: '#f8fafc', padding: '12px', borderRadius: '10px' }}>
            <div style={{ fontWeight: '700', color: '#475569', textTransform: 'uppercase', fontSize: '11px', marginBottom: '4px' }}>
              Billed To (Customer)
            </div>
            <div style={{ fontWeight: '700', color: '#1e293b', fontSize: '14px' }}>{payment.customer}</div>
            <div style={{ color: '#64748b', marginTop: '2px' }}>Booking Reference: {payment.bookingId}</div>
          </div>

          <div style={{ backgroundColor: '#f0fdf4', padding: '12px', borderRadius: '10px', border: '1px solid #bbf7d0' }}>
            <div style={{ fontWeight: '700', color: '#15803d', textTransform: 'uppercase', fontSize: '11px', marginBottom: '4px' }}>
              Service Provider (Cooperative Member)
            </div>
            <div style={{ fontWeight: '700', color: '#14532d', fontSize: '14px' }}>{payment.worker}</div>
            <div style={{ color: '#55695e', marginTop: '2px' }}>Service: {payment.service}</div>
          </div>
        </div>

        {/* Itemized Table */}
        <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '13px' }}>
          <thead>
            <tr style={{ backgroundColor: '#f1f5f3', borderBottom: '1px solid #d1dbd4', color: '#334155', fontWeight: '700', textAlign: 'left' }}>
              <th style={{ padding: '8px 12px' }}>Description</th>
              <th style={{ padding: '8px 12px', textAlign: 'right' }}>Amount</th>
            </tr>
          </thead>
          <tbody>
            <tr style={{ borderBottom: '1px solid #f1f5f3' }}>
              <td style={{ padding: '10px 12px' }}>
                <strong>{payment.service}</strong> — Standard On-Demand Fulfillment
              </td>
              <td style={{ padding: '10px 12px', textAlign: 'right', fontWeight: '600' }}>
                {payment.amount}
              </td>
            </tr>
            {payment.couponCode && (
              <tr style={{ borderBottom: '1px solid #f1f5f3', color: '#15803d', fontSize: '12px' }}>
                <td style={{ padding: '6px 12px' }}>
                  Coupon discount ({payment.couponCode})
                </td>
                <td style={{ padding: '6px 12px', textAlign: 'right', fontWeight: '700' }}>
                  −₹{payment.couponDiscount || 0}
                </td>
              </tr>
            )}
            <tr style={{ borderBottom: '1px solid #f1f5f3', color: '#64748b', fontSize: '12px' }}>
              <td style={{ padding: '6px 12px' }}>Cooperative Welfare Reserve Allocation (5%)</td>
              <td style={{ padding: '6px 12px', textAlign: 'right' }}>{payment.welfareCut}</td>
            </tr>
            <tr style={{ borderBottom: '1px solid #f1f5f3', color: '#15803d', fontSize: '12px' }}>
              <td style={{ padding: '6px 12px' }}>Net Disbursed to Worker via UPI (95%)</td>
              <td style={{ padding: '6px 12px', textAlign: 'right', fontWeight: '700' }}>{payment.workerPayout}</td>
            </tr>
            <tr style={{ fontWeight: '800', fontSize: '15px', backgroundColor: '#f8faf9' }}>
              <td style={{ padding: '10px 12px' }}>Total Paid via {payment.paymentMethod}</td>
              <td style={{ padding: '10px 12px', textAlign: 'right', color: '#0f172a' }}>{payment.amount}</td>
            </tr>
          </tbody>
        </table>

        {/* Security / Escrow Seal */}
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: '8px',
            padding: '10px 14px',
            backgroundColor: '#eaf8ef',
            borderRadius: '8px',
            fontSize: '12px',
            color: '#15803d',
            fontWeight: '600',
          }}
        >
          <ShieldCheck size={16} />
          <span>This payment is protected under Cooperative Fair Payout Guarantee and Social Security Pool.</span>
        </div>
      </div>
    </Modal>
  );
}
