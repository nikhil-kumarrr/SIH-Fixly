import React, { useState } from 'react';
import { useApp } from '../../context/AppContext';
import {
  CreditCard,
  IndianRupee,
  Search,
  Download,
  FileText,
  Eye,
  CheckCircle,
  Clock,
  RotateCcw,
  ArrowUpDown
} from 'lucide-react';
import Badge from '../../components/common/Badge';
import Pagination from '../../components/common/Pagination';
import InvoiceModal from '../../components/modals/InvoiceModal';

export default function PaymentsPage() {
  const { payments, paymentsPagination, fetchPayments, paymentStats } = useApp();

  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('All');
  const [selectedPaymentForInvoice, setSelectedPaymentForInvoice] = useState(null);
  const [currentPage, setCurrentPage] = useState(1);
  const pageSize = 10;

  React.useEffect(() => {
    fetchPayments({
      page: currentPage,
      limit: pageSize,
      status: statusFilter === 'Completed' ? 'success' : (statusFilter === 'Failed' ? 'failed' : '')
    });
  }, [fetchPayments, currentPage, statusFilter]);

  // Calculate dynamic financial stats with Indian Rupee formatting (en-IN)
  const totalVolume = paymentStats?.totalVolume || payments.reduce((acc, p) => acc + (p.rawAmount || 0), 0);
  const completedSettlements = paymentStats?.workerSettlements || Math.round(totalVolume * 0.95);
  const welfarePool = paymentStats?.welfareFundPool || Math.round(totalVolume * 0.05);
  const escrowPending = paymentStats?.totalPending || 0;
  const refundsProcessed = paymentStats?.totalFailed || 0;

  const formatINR = (val) => `₹${Number(val || 0).toLocaleString('en-IN')}`;

  let filtered = [...payments];

  if (statusFilter && statusFilter !== 'All') {
    const tStat = statusFilter.toUpperCase();
    filtered = filtered.filter((p) => {
      const s = (p.status || '').toUpperCase();
      if (tStat === 'COMPLETED' || tStat === 'SUCCESS') return s === 'COMPLETED' || s === 'SUCCESS' || s === 'PAID';
      if (tStat === 'PENDING') return s === 'PENDING';
      if (tStat === 'REFUNDED' || tStat === 'FAILED') return s === 'REFUNDED' || s === 'FAILED';
      return s === tStat;
    });
  }

  if (search && search.trim() !== '') {
    const q = search.toLowerCase().trim();
    filtered = filtered.filter((p) => {
      const id = (p.id || p._id || '').toLowerCase();
      const bId = (p.bookingId || '').toLowerCase();
      const cust = (p.customer || p.customerName || '').toLowerCase();
      const wrk = (p.worker || p.workerName || '').toLowerCase();
      return id.includes(q) || bId.includes(q) || cust.includes(q) || wrk.includes(q);
    });
  }

  const paginated = filtered;

  return (
    <div style={{ padding: '0 32px 32px 32px', animation: 'fadeIn 0.2s ease' }}>
      {/* Header */}
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          marginBottom: '20px',
          flexWrap: 'wrap',
          gap: '12px',
        }}
      >
        <div>
          <h2 style={{ fontSize: '20px', fontWeight: '700', color: '#111827' }}>
            Payments & Cooperative Escrow Treasury
          </h2>
          <p style={{ fontSize: '13px', color: '#64748b' }}>
            Digital payment reconciliation, direct UPI worker settlements, and 5% social welfare pool audits
          </p>
        </div>

        <button
          onClick={() => {
            const csvContent =
              'data:text/csv;charset=utf-8,' +
              ['Transaction ID,Booking ID,Customer,Worker,Amount,Welfare 5%,Worker Net,Status,Date']
                .concat(
                  payments.map(
                    (p) => `${p.id},${p.bookingId},${p.customer},${p.worker},${p.amount},${p.welfareCut},${p.workerPayout},${p.status},${p.date}`
                  )
                )
                .join('\n');
            const encodedUri = encodeURI(csvContent);
            const link = document.createElement('a');
            link.setAttribute('href', encodedUri);
            link.setAttribute('download', 'Cooperative_Financial_Ledger.csv');
            document.body.appendChild(link);
            link.click();
          }}
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: '6px',
            padding: '8px 14px',
            backgroundColor: '#ffffff',
            border: '1px solid var(--border-light)',
            borderRadius: '8px',
            fontSize: '13px',
            fontWeight: '600',
            color: '#334155',
          }}
        >
          <Download size={15} />
          <span>Export Financial Audit</span>
        </button>
      </div>

      {/* 5 Financial Summary KPI Cards (Dynamic Indian Rupee Values) */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(5, 1fr)', gap: '14px', marginBottom: '22px' }}>
        <div style={{ backgroundColor: '#ffffff', padding: '16px', borderRadius: '14px', border: '1px solid var(--border-light)' }}>
          <div style={{ fontSize: '11.5px', color: '#64748b' }}>Total Processed GTV</div>
          <div style={{ fontSize: '20px', fontWeight: '800', color: '#111827', marginTop: '3px' }}>{formatINR(totalVolume)}</div>
          <div style={{ fontSize: '11px', color: '#15803d', fontWeight: '600', marginTop: '2px' }}>↑ Live Treasury</div>
        </div>

        <div style={{ backgroundColor: '#ffffff', padding: '16px', borderRadius: '14px', border: '1px solid var(--border-light)' }}>
          <div style={{ fontSize: '11.5px', color: '#64748b' }}>Completed Settlements</div>
          <div style={{ fontSize: '20px', fontWeight: '800', color: '#15803d', marginTop: '3px' }}>{formatINR(completedSettlements)}</div>
          <div style={{ fontSize: '11px', color: '#64748b', marginTop: '2px' }}>Direct Worker UPI</div>
        </div>

        <div style={{ backgroundColor: '#ffffff', padding: '16px', borderRadius: '14px', border: '1px solid var(--border-light)' }}>
          <div style={{ fontSize: '11.5px', color: '#64748b' }}>Escrow Pending</div>
          <div style={{ fontSize: '20px', fontWeight: '800', color: '#d97706', marginTop: '3px' }}>{formatINR(escrowPending)}</div>
          <div style={{ fontSize: '11px', color: '#64748b', marginTop: '2px' }}>Under Verification</div>
        </div>

        <div style={{ backgroundColor: '#ffffff', padding: '16px', borderRadius: '14px', border: '1px solid var(--border-light)' }}>
          <div style={{ fontSize: '11.5px', color: '#64748b' }}>Welfare Fund Pool (5%)</div>
          <div style={{ fontSize: '20px', fontWeight: '800', color: '#0284c7', marginTop: '3px' }}>{formatINR(welfarePool)}</div>
          <div style={{ fontSize: '11px', color: '#64748b', marginTop: '2px' }}>Worker Insurance Aid</div>
        </div>

        <div style={{ backgroundColor: '#ffffff', padding: '16px', borderRadius: '14px', border: '1px solid var(--border-light)' }}>
          <div style={{ fontSize: '11.5px', color: '#64748b' }}>Refunds Processed</div>
          <div style={{ fontSize: '20px', fontWeight: '800', color: '#dc2626', marginTop: '3px' }}>{formatINR(refundsProcessed)}</div>
          <div style={{ fontSize: '11px', color: '#64748b', marginTop: '2px' }}>0% Refund Rate</div>
        </div>
      </div>

      {/* Filters Bar */}
      <div
        style={{
          backgroundColor: '#ffffff',
          padding: '12px 18px',
          borderRadius: '12px',
          border: '1px solid var(--border-light)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          marginBottom: '16px',
          gap: '12px',
          flexWrap: 'wrap',
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: '8px', width: '280px' }}>
          <Search size={15} color="#94a3b8" />
          <input
            type="text"
            placeholder="Search txn ID, customer, worker..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            style={{ border: 'none', outline: 'none', width: '100%', fontSize: '13px' }}
          />
        </div>

        <div style={{ display: 'flex', gap: '6px' }}>
          {['All', 'Completed', 'Pending', 'Refunded'].map((st) => (
            <button
              key={st}
              onClick={() => setStatusFilter(st)}
              style={{
                padding: '6px 12px',
                borderRadius: '8px',
                fontSize: '12.5px',
                fontWeight: '600',
                backgroundColor: statusFilter === st ? '#eaf7ee' : 'transparent',
                color: statusFilter === st ? '#15803d' : '#64748b',
                border: `1px solid ${statusFilter === st ? '#86efac' : 'transparent'}`,
              }}
            >
              {st}
            </button>
          ))}
        </div>
      </div>

      {/* Transaction Table */}
      <div
        className="table-responsive"
        style={{
          backgroundColor: '#ffffff',
          borderRadius: '14px',
          border: '1px solid var(--border-light)',
          overflowX: 'auto',
          WebkitOverflowScrolling: 'touch',
          width: '100%',
          boxShadow: 'var(--shadow-card)',
        }}
      >
        <table style={{ minWidth: '880px', width: '100%', borderCollapse: 'collapse', textAlign: 'left' }}>
          <thead>
            <tr style={{ backgroundColor: '#f8faf9', borderBottom: '1px solid #e6ede8', color: '#55695e', fontSize: '12px', fontWeight: '700', whiteSpace: 'nowrap' }}>
              <th style={{ padding: '14px 18px', whiteSpace: 'nowrap' }}>Transaction ID</th>
              <th style={{ padding: '14px 18px', whiteSpace: 'nowrap' }}>Parties & Booking</th>
              <th style={{ padding: '14px 18px', whiteSpace: 'nowrap' }}>Gross Amount</th>
              <th style={{ padding: '14px 18px', whiteSpace: 'nowrap' }}>Coupon</th>
              <th style={{ padding: '14px 18px', whiteSpace: 'nowrap' }}>Welfare Split (5%)</th>
              <th style={{ padding: '14px 18px', whiteSpace: 'nowrap' }}>Worker Net (95%)</th>
              <th style={{ padding: '14px 18px', whiteSpace: 'nowrap' }}>Payment Method</th>
              <th style={{ padding: '14px 18px', whiteSpace: 'nowrap' }}>Status</th>
              <th style={{ padding: '14px 18px', textAlign: 'right', whiteSpace: 'nowrap' }}>Invoice</th>
            </tr>
          </thead>
          <tbody>
            {paginated.length === 0 ? (
              <tr>
                <td colSpan="9" style={{ padding: '30px', textAlign: 'center', color: '#64748b', fontSize: '13px' }}>
                  No transactions found.
                </td>
              </tr>
            ) : (
              paginated.map((p) => (
                <tr key={p.id} style={{ borderBottom: '1px solid #f1f5f3', fontSize: '13px' }}>
                  <td style={{ padding: '14px 18px' }}>
                    <span style={{ fontWeight: '700', color: '#0284c7' }}>{p.id}</span>
                    <div style={{ fontSize: '11px', color: '#94a3b8' }}>{p.date} • {p.time}</div>
                  </td>

                  <td style={{ padding: '14px 18px' }}>
                    <div style={{ fontWeight: '600', color: '#1e293b' }}>
                      {p.customer} → {p.worker}
                    </div>
                    <div style={{ fontSize: '11.5px', color: '#64748b' }}>
                      {p.service} (Ref: {p.bookingId})
                    </div>
                  </td>

                  <td style={{ padding: '14px 18px', fontWeight: '800', color: '#0f172a' }}>
                    {p.amount}
                  </td>

                  <td style={{ padding: '14px 18px', fontSize: '12px' }}>
                    {p.couponCode ? (
                      <div>
                        <div style={{ fontWeight: '700', color: '#15803d' }}>{p.couponCode}</div>
                        <div style={{ color: '#64748b' }}>−₹{p.couponDiscount || 0}</div>
                      </div>
                    ) : (
                      <span style={{ color: '#94a3b8' }}>—</span>
                    )}
                  </td>

                  <td style={{ padding: '14px 18px', fontWeight: '600', color: '#15803d' }}>
                    {p.welfareCut}
                  </td>

                  <td style={{ padding: '14px 18px', fontWeight: '700', color: '#1e293b' }}>
                    {p.workerPayout}
                  </td>

                  <td style={{ padding: '14px 18px', color: '#475569' }}>
                    {p.paymentMethod}
                  </td>

                  <td style={{ padding: '14px 18px' }}>
                    <Badge status={p.status} />
                  </td>

                  <td style={{ padding: '14px 18px', textAlign: 'right' }}>
                    <button
                      onClick={() => setSelectedPaymentForInvoice(p)}
                      style={{
                        display: 'inline-flex',
                        alignItems: 'center',
                        gap: '4px',
                        padding: '6px 12px',
                        backgroundColor: '#f1f8f3',
                        color: '#15803d',
                        borderRadius: '6px',
                        fontSize: '12px',
                        fontWeight: '600',
                      }}
                    >
                      <FileText size={13} />
                      <span>View Invoice</span>
                    </button>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>

        <Pagination
          currentPage={currentPage}
          totalItems={paymentsPagination?.total || filtered.length}
          pageSize={pageSize}
          onPageChange={(p) => setCurrentPage(p)}
        />
      </div>

      <InvoiceModal
        payment={selectedPaymentForInvoice}
        isOpen={!!selectedPaymentForInvoice}
        onClose={() => setSelectedPaymentForInvoice(null)}
      />
    </div>
  );
}
