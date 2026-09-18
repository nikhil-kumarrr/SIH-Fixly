import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useApp } from '../../context/AppContext';
import {
  UserCheck,
  Search,
  Eye,
  Ban,
  CheckCircle,
  ArrowUpDown,
  Phone,
  Mail,
  MapPin
} from 'lucide-react';
import Badge from '../../components/common/Badge';
import Pagination from '../../components/common/Pagination';
import Avatar from '../../components/common/Avatar';

export default function CustomersPage() {
  const navigate = useNavigate();
  const { customers, customersPagination, fetchCustomers, toggleCustomerBlock } = useApp();

  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('All');
  const [sortField, setSortField] = useState('rawSpent');
  const [sortAsc, setSortAsc] = useState(false);
  const [currentPage, setCurrentPage] = useState(1);
  const pageSize = 10;

  React.useEffect(() => {
    fetchCustomers({
      page: currentPage,
      limit: pageSize,
      search,
      isVerified: statusFilter === 'Active' ? 'true' : (statusFilter === 'Blocked' ? 'false' : '')
    });
  }, [fetchCustomers, currentPage, search, statusFilter]);

  let filtered = [...customers];

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
            Customer Directory & Patrons ({customers.length})
          </h2>
          <p style={{ fontSize: '13px', color: '#64748b' }}>
            Customer profiles, lifetime booking values, ratings, and account status
          </p>
        </div>
      </div>

      {/* Filter Bar */}
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
            placeholder="Search customer name, phone, email..."
            value={search}
            onChange={(e) => {
              setSearch(e.target.value);
              setCurrentPage(1);
            }}
            style={{ border: 'none', outline: 'none', backgroundColor: 'transparent', width: '100%', fontSize: '13px' }}
          />
        </div>

        <div style={{ display: 'flex', gap: '6px' }}>
          {['All', 'Active', 'VIP', 'Blocked'].map((st) => (
            <button
              key={st}
              onClick={() => {
                setStatusFilter(st);
                setCurrentPage(1);
              }}
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

      {/* Customers Table */}
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
        <table style={{ minWidth: '750px', width: '100%', borderCollapse: 'collapse', textAlign: 'left' }}>
          <thead>
            <tr style={{ backgroundColor: '#f8faf9', borderBottom: '1px solid #e6ede8', color: '#55695e', fontSize: '12px', fontWeight: '700', whiteSpace: 'nowrap' }}>
              <th onClick={() => toggleSort('name')} style={{ padding: '14px 18px', cursor: 'pointer', whiteSpace: 'nowrap' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
                  <span>Customer</span>
                  <ArrowUpDown size={12} />
                </div>
              </th>
              <th style={{ padding: '14px 18px', whiteSpace: 'nowrap' }}>Contact & Location</th>
              <th onClick={() => toggleSort('totalBookings')} style={{ padding: '14px 18px', cursor: 'pointer', whiteSpace: 'nowrap' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
                  <span>Total Bookings</span>
                  <ArrowUpDown size={12} />
                </div>
              </th>
              <th onClick={() => toggleSort('rawSpent')} style={{ padding: '14px 18px', cursor: 'pointer', whiteSpace: 'nowrap' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
                  <span>Lifetime Spending</span>
                  <ArrowUpDown size={12} />
                </div>
              </th>
              <th style={{ padding: '14px 18px', whiteSpace: 'nowrap' }}>Rating</th>
              <th style={{ padding: '14px 18px', whiteSpace: 'nowrap' }}>Status</th>
              <th style={{ padding: '14px 18px', textAlign: 'right', whiteSpace: 'nowrap' }}>Actions</th>
            </tr>
          </thead>
          <tbody>
            {paginated.map((c) => (
              <tr key={c.id} style={{ borderBottom: '1px solid #f1f5f3', fontSize: '13px' }}>
                <td style={{ padding: '14px 18px' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                    <Avatar src={c.avatar} name={c.name} size={34} />
                    <div>
                      <div
                        onClick={() => navigate(`/customers/${c.id}`)}
                        style={{ fontWeight: '700', color: 'var(--text-link)', cursor: 'pointer' }}
                      >
                        {c.name}
                      </div>
                      <div style={{ fontSize: '11px', color: '#64748b' }}>{c.id} • Since {c.memberSince}</div>
                    </div>
                  </div>
                </td>

                <td style={{ padding: '14px 18px' }}>
                  <div style={{ color: '#1e293b' }}>{c.phone}</div>
                  <div style={{ fontSize: '11.5px', color: '#64748b', maxWidth: '240px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                    {c.address}
                  </div>
                </td>

                <td style={{ padding: '14px 18px', fontWeight: '700', color: '#1e293b' }}>
                  {c.totalBookings} tasks
                </td>

                <td style={{ padding: '14px 18px', fontWeight: '800', color: '#15803d' }}>
                  {c.totalSpent}
                </td>

                <td style={{ padding: '14px 18px', fontWeight: '700', color: '#ca8a04' }}>
                  ★ {c.rating}
                </td>

                <td style={{ padding: '14px 18px' }}>
                  <Badge status={c.status} />
                </td>

                <td style={{ padding: '14px 18px', textAlign: 'right' }}>
                  <div style={{ display: 'flex', gap: '6px', justifyContent: 'flex-end' }}>
                    <button
                      onClick={() => navigate(`/customers/${c.id}`)}
                      title="View Customer Profile"
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

                    <button
                      onClick={() => toggleCustomerBlock(c.id, c.isVerified)}
                      title={c.status === 'Blocked' ? 'Unblock Customer' : 'Block Customer'}
                      style={{
                        padding: '6px 8px',
                        backgroundColor: c.status === 'Blocked' ? '#eaf8ef' : '#fef2f2',
                        color: c.status === 'Blocked' ? '#15803d' : '#dc2626',
                        borderRadius: '6px',
                        fontSize: '12px',
                      }}
                    >
                      {c.status === 'Blocked' ? <CheckCircle size={14} /> : <Ban size={14} />}
                    </button>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>

        <Pagination
          currentPage={currentPage}
          totalItems={customersPagination?.total || filtered.length}
          pageSize={pageSize}
          onPageChange={(p) => setCurrentPage(p)}
        />
      </div>
    </div>
  );
}
