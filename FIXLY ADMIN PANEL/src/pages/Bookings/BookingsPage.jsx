import React, { useState } from 'react';
import { useApp } from '../../context/AppContext';
import {
  Search,
  Filter,
  Plus,
  Download,
  Calendar,
  Eye,
  UserCheck,
  CalendarClock,
  Ban,
  ArrowUpDown,
  Phone,
  MapPin,
  ShieldCheck,
  Zap
} from 'lucide-react';
import Badge from '../../components/common/Badge';
import Pagination from '../../components/common/Pagination';
import Modal from '../../components/common/Modal';
import ConfirmDialog from '../../components/common/ConfirmDialog';
import AssignWorkerModal from '../../components/modals/AssignWorkerModal';
import RescheduleBookingModal from '../../components/modals/RescheduleBookingModal';
import EmergencyDispatchModal from '../../components/modals/EmergencyDispatchModal';
import { getMergedCategories } from '../../data/services';

export default function BookingsPage() {
  const { bookings, bookingsPagination, fetchBookings, cancelBooking, updateBookingStatus, services } = useApp();

  const serviceOptions = React.useMemo(() => getMergedCategories(services), [services]);

  // Filter & Search states
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('All');
  const [serviceFilter, setServiceFilter] = useState('All');
  const [sortField, setSortField] = useState('date');
  const [sortAsc, setSortAsc] = useState(false);
  const [currentPage, setCurrentPage] = useState(1);
  const pageSize = 10;

  React.useEffect(() => {
    fetchBookings({
      page: currentPage,
      limit: pageSize,
      search,
      status: statusFilter !== 'All' ? statusFilter : ''
    });
  }, [fetchBookings, currentPage, search, statusFilter]);

  // Modals state
  const [selectedBookingForView, setSelectedBookingForView] = useState(null);
  const [selectedBookingForAssign, setSelectedBookingForAssign] = useState(null);
  const [selectedBookingForReschedule, setSelectedBookingForReschedule] = useState(null);
  const [selectedBookingForCancel, setSelectedBookingForCancel] = useState(null);
  const [selectedEmergency, setSelectedEmergency] = useState(null);

  let filtered = [...bookings];

  // Status Filter Pill Logic
  if (statusFilter && statusFilter !== 'All') {
    const targetStatus = statusFilter.toUpperCase();
    filtered = filtered.filter((b) => {
      const bStatus = (b.status || '').toUpperCase();
      if (targetStatus === 'CONFIRMED') return bStatus === 'CONFIRMED' || bStatus === 'ACCEPTED' || bStatus === 'BOOKED';
      if (targetStatus === 'PENDING') return bStatus === 'PENDING';
      if (targetStatus === 'IN PROGRESS') return bStatus === 'IN_PROGRESS' || bStatus === 'IN PROGRESS' || bStatus === 'ACCEPTED' || bStatus === 'ASSIGNED';
      if (targetStatus === 'COMPLETED') return bStatus === 'COMPLETED';
      if (targetStatus === 'CANCELLED') return bStatus === 'CANCELLED' || bStatus === 'REJECTED';
      if (targetStatus === 'EMERGENCY') return b.isEmergency === true || bStatus === 'EMERGENCY' || b.category === 'Emergency';
      return bStatus === targetStatus;
    });
  }

  // Service Category Filter
  if (serviceFilter && serviceFilter !== 'All' && serviceFilter !== 'All Services') {
    const sTerm = serviceFilter.toLowerCase();
    filtered = filtered.filter((b) => {
      const title = (b.serviceTitle || b.service || b.title || '').toLowerCase();
      const cat = (b.category || b.serviceCategory || '').toLowerCase();
      return title.includes(sTerm) || cat.includes(sTerm);
    });
  }

  // Search Filter
  if (search && search.trim() !== '') {
    const q = search.toLowerCase().trim();
    filtered = filtered.filter((b) => {
      const id = (b.id || b._id || b.bookingId || '').toLowerCase();
      const cust = (b.customerName || b.customer || '').toLowerCase();
      const worker = (b.workerName || b.assignedWorker || '').toLowerCase();
      const title = (b.serviceTitle || b.service || b.title || '').toLowerCase();
      return id.includes(q) || cust.includes(q) || worker.includes(q) || title.includes(q);
    });
  }

  // Sort logic
  filtered.sort((a, b) => {
    let valA = a[sortField] || '';
    let valB = b[sortField] || '';
    if (sortField === 'amount') {
      valA = a.rawAmount || 0;
      valB = b.rawAmount || 0;
    }
    if (valA < valB) return sortAsc ? -1 : 1;
    if (valA > valB) return sortAsc ? 1 : -1;
    return 0;
  });

  const paginated = filtered;

  const toggleSort = (field) => {
    if (sortField === field) {
      setSortAsc(!sortAsc);
    } else {
      setSortField(field);
      setSortAsc(true);
    }
  };

  return (
    <div style={{ padding: '0 32px 32px 32px', animation: 'fadeIn 0.2s ease' }}>
      {/* Top Header */}
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
            Bookings & Gig Dispatch Central ({bookings.length})
          </h2>
          <p style={{ fontSize: '13px', color: '#64748b' }}>
            Manage real-time customer bookings, worker allocations, cancellations, and SLA tracking
          </p>
        </div>

        <div style={{ display: 'flex', gap: '10px' }}>
          <button
            onClick={() => {
              const csvContent =
                'data:text/csv;charset=utf-8,' +
                ['Booking ID,Customer,Service,Worker,Amount,Status,Date']
                  .concat(bookings.map((b) => `${b.id},${b.customer},${b.service},${b.worker},${b.amount},${b.status},${b.date}`))
                  .join('\n');
              const encodedUri = encodeURI(csvContent);
              const link = document.createElement('a');
              link.setAttribute('href', encodedUri);
              link.setAttribute('download', 'Cooperative_Bookings_Report.csv');
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
            <span>Export CSV</span>
          </button>
        </div>
      </div>

      {/* Filter and Search Bar */}
      <div
        style={{
          backgroundColor: '#ffffff',
          padding: '14px 18px',
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
        {/* Search */}
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: '8px',
            backgroundColor: '#f8fafc',
            border: '1px solid #e2e8f0',
            borderRadius: '8px',
            padding: '7px 12px',
            width: '280px',
          }}
        >
          <Search size={15} color="#94a3b8" />
          <input
            type="text"
            placeholder="Search booking ID, customer, worker..."
            value={search}
            onChange={(e) => {
              setSearch(e.target.value);
              setCurrentPage(1);
            }}
            style={{ border: 'none', outline: 'none', backgroundColor: 'transparent', width: '100%', fontSize: '13px' }}
          />
        </div>

        {/* Service filter */}
        <select
          value={serviceFilter}
          onChange={(e) => {
            setServiceFilter(e.target.value);
            setCurrentPage(1);
          }}
          style={{
            padding: '7px 12px',
            borderRadius: '8px',
            border: '1px solid #cbd5e1',
            fontSize: '12.5px',
            fontWeight: '600',
            color: '#334155',
            backgroundColor: '#ffffff',
          }}
        >
          <option value="All">All Services</option>
          {serviceOptions.map((srv) => (
            <option key={srv} value={srv}>{srv}</option>
          ))}
        </select>

        {/* Status Pills */}
        <div style={{ display: 'flex', gap: '4px', flexWrap: 'wrap' }}>
          {['All', 'Confirmed', 'Pending', 'In Progress', 'Completed', 'Cancelled', 'Emergency'].map((st) => (
            <button
              key={st}
              onClick={() => {
                setStatusFilter(st);
                setCurrentPage(1);
              }}
              style={{
                padding: '5px 10px',
                borderRadius: '6px',
                fontSize: '12px',
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

      {/* Bookings Table */}
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
        <table style={{ minWidth: '850px', width: '100%', borderCollapse: 'collapse', textAlign: 'left' }}>
          <thead>
            <tr style={{ backgroundColor: '#f8faf9', borderBottom: '1px solid #e6ede8', color: '#55695e', fontSize: '12px', fontWeight: '700', whiteSpace: 'nowrap' }}>
              <th onClick={() => toggleSort('id')} style={{ padding: '14px 18px', cursor: 'pointer', whiteSpace: 'nowrap' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
                  <span>Booking ID</span>
                  <ArrowUpDown size={12} />
                </div>
              </th>
              <th onClick={() => toggleSort('customer')} style={{ padding: '14px 18px', cursor: 'pointer', whiteSpace: 'nowrap' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
                  <span>Customer & Location</span>
                  <ArrowUpDown size={12} />
                </div>
              </th>
              <th style={{ padding: '14px 18px', whiteSpace: 'nowrap' }}>Service Details</th>
              <th style={{ padding: '14px 18px', whiteSpace: 'nowrap' }}>Assigned Worker</th>
              <th onClick={() => toggleSort('amount')} style={{ padding: '14px 18px', cursor: 'pointer', whiteSpace: 'nowrap' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
                  <span>Amount</span>
                  <ArrowUpDown size={12} />
                </div>
              </th>
              <th style={{ padding: '14px 18px', whiteSpace: 'nowrap' }}>Status</th>
              <th style={{ padding: '14px 18px', textAlign: 'right', whiteSpace: 'nowrap' }}>Actions</th>
            </tr>
          </thead>
          <tbody>
            {paginated.map((b) => (
              <tr key={b.id} style={{ borderBottom: '1px solid #f1f5f3', fontSize: '13px' }}>
                <td style={{ padding: '14px 18px' }}>
                  <span
                    onClick={() => setSelectedBookingForView(b)}
                    style={{ color: 'var(--text-link)', fontWeight: '700', cursor: 'pointer' }}
                  >
                    {b.id}
                  </span>
                  <div style={{ fontSize: '11px', color: '#94a3b8' }}>
                    {b.date} • {b.time}
                  </div>
                </td>
                <td style={{ padding: '14px 18px' }}>
                  <div style={{ fontWeight: '700', color: '#1e293b' }}>{b.customer}</div>
                  <div style={{ fontSize: '11.5px', color: '#64748b', maxWidth: '240px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                    {b.customerAddress}
                  </div>
                </td>
                <td style={{ padding: '14px 18px' }}>
                  <div style={{ fontWeight: '600', color: '#1e293b' }}>{b.service}</div>
                  <div style={{ fontSize: '11.5px', color: '#64748b' }}>{b.serviceType}</div>
                </td>
                <td style={{ padding: '14px 18px' }}>
                  {b.worker ? (
                    <div>
                      <div style={{ fontWeight: '600', color: '#1e293b' }}>{b.worker}</div>
                      <div style={{ fontSize: '11.5px', color: '#15803d' }}>⭐ {b.workerRating}</div>
                    </div>
                  ) : (
                    <span style={{ color: '#d97706', fontSize: '12px', fontWeight: '600' }}>Unassigned</span>
                  )}
                </td>
                <td style={{ padding: '14px 18px', fontWeight: '800', color: '#0f172a' }}>
                  {b.amount}
                  {b.couponCode && (
                    <div style={{ fontSize: '11px', fontWeight: '600', color: '#15803d', marginTop: '2px' }}>
                      {b.couponCode} −₹{b.couponDiscount || 0}
                    </div>
                  )}
                </td>
                <td style={{ padding: '14px 18px' }}>
                  <Badge status={b.status} />
                </td>
                <td style={{ padding: '14px 18px', textAlign: 'right' }}>
                  <div style={{ display: 'flex', gap: '6px', justifyContent: 'flex-end' }}>
                    <button
                      onClick={() => setSelectedBookingForView(b)}
                      title="View Details"
                      style={{
                        padding: '6px 8px',
                        backgroundColor: '#f1f8f3',
                        color: '#15803d',
                        borderRadius: '6px',
                        fontSize: '12px',
                        fontWeight: '600',
                      }}
                    >
                      <Eye size={14} />
                    </button>

                    <button
                      onClick={() => setSelectedBookingForAssign(b)}
                      title="Assign Worker"
                      style={{
                        padding: '6px 8px',
                        backgroundColor: '#eff6ff',
                        color: '#2563eb',
                        borderRadius: '6px',
                        fontSize: '12px',
                        fontWeight: '600',
                      }}
                    >
                      <UserCheck size={14} />
                    </button>

                    <button
                      onClick={() => setSelectedBookingForReschedule(b)}
                      title="Reschedule Slot"
                      style={{
                        padding: '6px 8px',
                        backgroundColor: '#f8fafc',
                        color: '#475569',
                        borderRadius: '6px',
                        fontSize: '12px',
                      }}
                    >
                      <CalendarClock size={14} />
                    </button>

                    {b.status !== 'Cancelled' && (
                      <button
                        onClick={() => setSelectedBookingForCancel(b)}
                        title="Cancel Booking"
                        style={{
                          padding: '6px 8px',
                          backgroundColor: '#fef2f2',
                          color: '#dc2626',
                          borderRadius: '6px',
                          fontSize: '12px',
                        }}
                      >
                        <Ban size={14} />
                      </button>
                    )}
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>

        {/* Pagination */}
        <Pagination
          currentPage={currentPage}
          totalItems={bookingsPagination?.total || filtered.length}
          pageSize={pageSize}
          onPageChange={(p) => setCurrentPage(p)}
        />
      </div>

      {/* Booking View Modal */}
      {selectedBookingForView && (
        <Modal
          isOpen={!!selectedBookingForView}
          onClose={() => setSelectedBookingForView(null)}
          title={`Booking Details: ${selectedBookingForView.id}`}
          subtitle={`Status: ${selectedBookingForView.status}`}
          maxWidth="560px"
          footer={
            <button
              onClick={() => setSelectedBookingForView(null)}
              style={{
                padding: '8px 18px',
                backgroundColor: 'var(--primary-brand)',
                color: '#ffffff',
                borderRadius: '8px',
                fontWeight: '600',
                fontSize: '13px',
              }}
            >
              Close
            </button>
          }
        >
          <div style={{ display: 'flex', flexDirection: 'column', gap: '14px', fontSize: '13px' }}>
            <div style={{ backgroundColor: '#f0fdf4', padding: '12px', borderRadius: '10px', border: '1px solid #bbf7d0' }}>
              <div style={{ fontWeight: '700', color: '#15803d', fontSize: '14px' }}>
                {selectedBookingForView.service} — {selectedBookingForView.serviceType}
              </div>
              <div style={{ color: '#166534', marginTop: '2px' }}>
                Amount: <strong>{selectedBookingForView.amount}</strong> ({selectedBookingForView.paymentStatus})
              </div>
              {selectedBookingForView.couponCode && (
                <div style={{ color: '#15803d', marginTop: '6px', fontWeight: '600' }}>
                  Coupon {selectedBookingForView.couponCode}: −₹{selectedBookingForView.couponDiscount || 0}
                </div>
              )}
            </div>

            <div><strong>Customer:</strong> {selectedBookingForView.customer} ({selectedBookingForView.customerPhone})</div>
            <div><strong>Location:</strong> {selectedBookingForView.customerAddress}</div>
            <div><strong>Assigned Worker:</strong> {selectedBookingForView.worker || 'None'} ({selectedBookingForView.workerPhone || 'N/A'})</div>
            <div><strong>Schedule:</strong> {selectedBookingForView.scheduledSlot || selectedBookingForView.date}</div>
            <div><strong>Customer Notes:</strong> {selectedBookingForView.notes || 'None provided'}</div>
          </div>
        </Modal>
      )}

      {/* Assign Worker Modal */}
      <AssignWorkerModal
        booking={selectedBookingForAssign}
        isOpen={!!selectedBookingForAssign}
        onClose={() => setSelectedBookingForAssign(null)}
      />

      {/* Reschedule Modal */}
      <RescheduleBookingModal
        booking={selectedBookingForReschedule}
        isOpen={!!selectedBookingForReschedule}
        onClose={() => setSelectedBookingForReschedule(null)}
      />

      {/* Cancel Confirmation Dialog */}
      <ConfirmDialog
        isOpen={!!selectedBookingForCancel}
        onClose={() => setSelectedBookingForCancel(null)}
        onConfirm={() => cancelBooking(selectedBookingForCancel.id, 'Cancelled by Admin')}
        title="Cancel this Booking?"
        message={`Are you sure you want to cancel booking ${selectedBookingForCancel?.id} for ${selectedBookingForCancel?.customer}? This will issue a full escrow refund and release the assigned worker.`}
        confirmText="Confirm Cancellation"
        isDestructive={true}
      />
    </div>
  );
}
