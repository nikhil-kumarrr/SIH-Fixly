import React, { useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { useApp } from '../../context/AppContext';
import {
  Search,
  Plus,
  Star,
  MapPin,
  Ban,
  Eye,
  ArrowUpDown,
  Phone,
  Battery,
  Map as MapIcon,
  CheckCircle,
} from 'lucide-react';
import Badge from '../../components/common/Badge';
import Pagination from '../../components/common/Pagination';
import AddWorkerModal from '../../components/modals/AddWorkerModal';
import LiveMapModal from '../../components/LiveMapModal';
import Avatar from '../../components/common/Avatar';
import { getMergedCategories } from '../../data/services';

export default function WorkersPage() {
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  const { workers, workersPagination, fetchWorkers, suspendWorker, verifyWorker, rejectWorker, services } = useApp();

  const tradeOptions = React.useMemo(() => getMergedCategories(services), [services]);

  // Search & Filter states
  const [search, setSearch] = useState('');
  const [serviceFilter, setServiceFilter] = useState('All');
  const [statusFilter, setStatusFilter] = useState('All');
  const [availabilityFilter, setAvailabilityFilter] = useState('All');
  const [cityFilter, setCityFilter] = useState('All');
  const [sortField, setSortField] = useState('rating');
  const [sortAsc, setSortAsc] = useState(false);
  const [currentPage, setCurrentPage] = useState(1);
  const [isAddWorkerOpen, setIsAddWorkerOpen] = useState(false);
  const [isMapOpen, setIsMapOpen] = useState(() => searchParams.get('map') === '1');
  const pageSize = 10;

  React.useEffect(() => {
    if (searchParams.get('map') === '1') {
      setIsMapOpen(true);
    }
  }, [searchParams]);

  const openMap = () => {
    setIsMapOpen(true);
    setSearchParams((prev) => {
      const next = new URLSearchParams(prev);
      next.set('map', '1');
      return next;
    });
  };

  const closeMap = () => {
    setIsMapOpen(false);
    setSearchParams((prev) => {
      const next = new URLSearchParams(prev);
      next.delete('map');
      return next;
    });
  };

  React.useEffect(() => {
    const params = {
      page: currentPage,
      limit: pageSize,
      search: search || undefined,
      category: serviceFilter !== 'All' ? serviceFilter : '',
    };
    if (statusFilter === 'Verified') params.isVerified = 'true';
    if (statusFilter === 'Pending') params.isVerified = 'false';
    if (statusFilter === 'Rejected') params.kycStatus = 'rejected';
    fetchWorkers(params);
  }, [fetchWorkers, currentPage, search, serviceFilter, statusFilter]);

  let filtered = [...workers];

  // Category / Skill Filter
  if (serviceFilter && serviceFilter !== 'All' && serviceFilter !== 'All Services') {
    const sTerm = serviceFilter.toLowerCase();
    filtered = filtered.filter((w) => {
      const skills = Array.isArray(w.skills) ? w.skills.join(' ').toLowerCase() : '';
      const cat = (w.category || w.primarySkill || '').toLowerCase();
      return skills.includes(sTerm) || cat.includes(sTerm);
    });
  }

  // Search Filter
  if (search && search.trim() !== '') {
    const q = search.toLowerCase().trim();
    filtered = filtered.filter((w) => {
      const name = (w.name || w.fullName || '').toLowerCase();
      const phone = (w.phone || w.phoneNumber || '').toLowerCase();
      const cat = (w.category || w.primarySkill || '').toLowerCase();
      return name.includes(q) || phone.includes(q) || cat.includes(q);
    });
  }

  // City Filter
  if (cityFilter && cityFilter !== 'All' && cityFilter !== 'All Cities') {
    const cTerm = cityFilter.toLowerCase();
    filtered = filtered.filter((w) => {
      const city = (w.city || w.location?.city || w.locationName || w.address?.city || '').toLowerCase();
      const locStr = (typeof w.location === 'string' ? w.location : JSON.stringify(w.location || {})).toLowerCase();
      return city.includes(cTerm) || locStr.includes(cTerm);
    });
  }

  // Availability Filter
  if (availabilityFilter && availabilityFilter !== 'All') {
    filtered = filtered.filter((w) => {
      if (availabilityFilter === 'Active') return w.isAvailable || w.status === 'ACTIVE';
      if (availabilityFilter === 'On Job') return w.status === 'ON_JOB';
      if (availabilityFilter === 'Offline') return !w.isAvailable || w.status === 'OFFLINE';
      return true;
    });
  }

  // Verification / Status Filter
  if (statusFilter && statusFilter !== 'All') {
    filtered = filtered.filter((w) => {
      if (statusFilter === 'Verified') return w.isVerified || w.verification === 'Verified';
      if (statusFilter === 'Pending') return !w.isVerified && w.verification !== 'Rejected';
      if (statusFilter === 'Rejected') return w.kycStatus === 'rejected' || w.verification === 'Rejected';
      return true;
    });
  }

  // Sort logic
  filtered.sort((a, b) => {
    let valA = a[sortField] || '';
    let valB = b[sortField] || '';
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
      setSortAsc(false);
    }
  };

  return (
    <div style={{ padding: '0 32px 32px 32px', animation: 'fadeIn 0.2s ease' }}>
      {/* Page Header */}
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
            Workers Directory ({workersPagination?.total ?? filtered.length})
          </h2>
          <p style={{ fontSize: '13px', color: '#64748b' }}>
            Manage all registered cooperative workers, verify KYC, and track activity.
          </p>
        </div>

        <div style={{ display: 'flex', gap: '10px' }}>
          <button
            type="button"
            onClick={openMap}
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '6px',
              padding: '9px 16px',
              backgroundColor: '#ffffff',
              color: '#15803d',
              borderRadius: '8px',
              fontSize: '13px',
              fontWeight: '600',
              border: '1px solid #bbf7d0',
              cursor: 'pointer',
            }}
          >
            <MapIcon size={16} />
            <span>Map</span>
          </button>
          <button
            onClick={() => setIsAddWorkerOpen(true)}
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '6px',
              padding: '9px 16px',
              backgroundColor: 'var(--primary-brand)',
              color: '#ffffff',
              borderRadius: '8px',
              fontSize: '13px',
              fontWeight: '600',
              boxShadow: 'var(--shadow-pill)',
            }}
          >
            <Plus size={16} />
            <span>Onboard Member</span>
          </button>
        </div>
      </div>

      {/* Filters Bar */}
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
            width: '260px',
          }}
        >
          <Search size={15} color="#94a3b8" />
          <input
            type="text"
            placeholder="Search worker, skill, trade..."
            value={search}
            onChange={(e) => {
              setSearch(e.target.value);
              setCurrentPage(1);
            }}
            style={{ border: 'none', outline: 'none', backgroundColor: 'transparent', width: '100%', fontSize: '13px' }}
          />
        </div>

        {/* Dropdown Filters */}
        <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap' }}>
          {/* Status filter */}
          <select
            value={statusFilter}
            onChange={(e) => {
              setStatusFilter(e.target.value);
              setCurrentPage(1);
            }}
            style={{
              padding: '7px 10px',
              borderRadius: '8px',
              border: '1px solid #cbd5e1',
              fontSize: '12.5px',
              fontWeight: '600',
              backgroundColor: '#ffffff',
            }}
          >
            <option value="All">All Statuses</option>
            <option value="Verified">Verified Only</option>
            <option value="Pending">Pending / In Review</option>
            <option value="Rejected">Rejected</option>
          </select>

          {/* Service filter */}
          <select
            value={serviceFilter}
            onChange={(e) => {
              setServiceFilter(e.target.value);
              setCurrentPage(1);
            }}
            style={{
              padding: '7px 10px',
              borderRadius: '8px',
              border: '1px solid #cbd5e1',
              fontSize: '12.5px',
              fontWeight: '600',
              backgroundColor: '#ffffff',
            }}
          >
            <option value="All">All Trades</option>
            {tradeOptions.map((trade) => (
              <option key={trade} value={trade}>{trade}</option>
            ))}
          </select>

          {/* City filter */}
          <select
            value={cityFilter}
            onChange={(e) => {
              setCityFilter(e.target.value);
              setCurrentPage(1);
            }}
            style={{
              padding: '7px 10px',
              borderRadius: '8px',
              border: '1px solid #cbd5e1',
              fontSize: '12.5px',
              fontWeight: '600',
              backgroundColor: '#ffffff',
            }}
          >
            <option value="All">All Cities</option>
            <option value="Noida">Noida</option>
            <option value="New Delhi">New Delhi</option>
            <option value="Gurgaon">Gurgaon</option>
            <option value="Ghaziabad">Ghaziabad</option>
            <option value="Mumbai">Mumbai</option>
            <option value="Pune">Pune</option>
          </select>
        </div>
      </div>

      {/* Workers Table Card */}
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
              <th style={{ padding: '14px 18px', whiteSpace: 'nowrap' }}>Profile & Name</th>
              <th style={{ padding: '14px 18px', whiteSpace: 'nowrap' }}>Trade & Skills</th>
              <th style={{ padding: '14px 18px', whiteSpace: 'nowrap' }}>Location</th>
              <th onClick={() => toggleSort('rating')} style={{ padding: '14px 18px', cursor: 'pointer', whiteSpace: 'nowrap' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
                  <span>Rating</span>
                  <ArrowUpDown size={12} />
                </div>
              </th>
              <th onClick={() => toggleSort('completedJobs')} style={{ padding: '14px 18px', cursor: 'pointer', whiteSpace: 'nowrap' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
                  <span>Jobs Completed</span>
                  <ArrowUpDown size={12} />
                </div>
              </th>
              <th style={{ padding: '14px 18px', whiteSpace: 'nowrap' }}>Availability</th>
              <th style={{ padding: '14px 18px', whiteSpace: 'nowrap' }}>Verification</th>
              <th style={{ padding: '14px 18px', textAlign: 'right', whiteSpace: 'nowrap' }}>Actions</th>
            </tr>
          </thead>
          <tbody>
            {paginated.map((w) => (
              <tr key={w.id} style={{ borderBottom: '1px solid #f1f5f3', fontSize: '13px' }}>
                {/* Profile & Name */}
                <td style={{ padding: '14px 18px' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                    <Avatar
                      src={w.avatar}
                      name={w.name}
                      size={38}
                    />
                    <div>
                      <div
                        onClick={() => navigate(`/workers/${w.id}`)}
                        style={{ fontWeight: '700', color: 'var(--text-link)', cursor: 'pointer' }}
                      >
                        {w.name}
                      </div>
                      <div style={{ fontSize: '11px', color: '#64748b' }}>{w.id} • {w.phone}</div>
                    </div>
                  </div>
                </td>

                {/* Trade & Skills */}
                <td style={{ padding: '14px 18px' }}>
                  <div style={{ fontWeight: '700', color: '#1e293b' }}>{w.service || w.category}</div>
                  <div style={{ fontSize: '11.5px', color: '#64748b', maxWidth: '180px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                    {Array.isArray(w.skills) ? w.skills.join(', ') : (w.category || 'General')}
                  </div>
                </td>

                {/* Location */}
                <td style={{ padding: '14px 18px', color: '#475569' }}>
                  <div>{w.location || 'Sector 62'}</div>
                  <div style={{ fontSize: '11px', color: '#94a3b8' }}>City: {w.city || 'Noida'}</div>
                </td>

                {/* Rating */}
                <td style={{ padding: '14px 18px', fontWeight: '700', color: '#15803d' }}>
                  ★ {w.rating}
                  <div style={{ fontSize: '11px', color: '#64748b', fontWeight: '400' }}>({w.totalReviews} revs)</div>
                </td>

                {/* Completed Jobs */}
                <td style={{ padding: '14px 18px', fontWeight: '700', color: '#0f172a' }}>
                  {w.completedJobs} tasks
                  <div style={{ fontSize: '11px', color: '#15803d' }}>{w.todayEarnings} today</div>
                </td>

                {/* Availability */}
                <td style={{ padding: '14px 18px' }}>
                  <Badge status={w.availability} />
                </td>

                {/* Verification */}
                <td style={{ padding: '14px 18px' }}>
                  <Badge status={w.verification} />
                </td>

                {/* Actions */}
                <td style={{ padding: '14px 18px', textAlign: 'right' }}>
                  <div style={{ display: 'flex', gap: '6px', justifyContent: 'flex-end' }}>
                    <button
                      onClick={() => navigate(`/workers/${w.rawId || w._id || w.id}`)}
                      title="View & Edit Worker Profile"
                      style={{
                        padding: '6px 8px',
                        backgroundColor: '#f1f8f3',
                        color: '#15803d',
                        borderRadius: '6px',
                        fontSize: '12px',
                      }}
                    >
                      <Eye size={14} />
                    </button>

                    {w.verification !== 'Verified' && (
                      <button
                        onClick={() => verifyWorker(w.id)}
                        title="Approve Worker"
                        style={{
                          padding: '6px 8px',
                          backgroundColor: '#ecfdf5',
                          color: '#059669',
                          borderRadius: '6px',
                          fontSize: '12px',
                        }}
                      >
                        <CheckCircle size={14} />
                      </button>
                    )}

                    <button
                      onClick={() => suspendWorker(w.id)}
                      title="Suspend Account"
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
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>

        {/* Pagination */}
        <Pagination
          currentPage={currentPage}
          totalItems={workersPagination?.total || filtered.length}
          pageSize={pageSize}
          onPageChange={(p) => setCurrentPage(p)}
        />
      </div>

      <AddWorkerModal isOpen={isAddWorkerOpen} onClose={() => setIsAddWorkerOpen(false)} />
      <LiveMapModal isOpen={isMapOpen} onClose={closeMap} />
    </div>
  );
}
