import React from 'react';
import { recentBookingsData } from '../data/mockData';
import { ExternalLink, Eye, MoreHorizontal } from 'lucide-react';

export default function RecentBookingsTable({ onSelectBooking }) {
  const getStatusBadge = (status) => {
    switch (status) {
      case 'Confirmed':
        return (
          <span
            style={{
              padding: '4px 10px',
              borderRadius: '999px',
              fontSize: '11.5px',
              fontWeight: '600',
              backgroundColor: '#eaf8ef',
              color: '#15803d',
              display: 'inline-block',
            }}
          >
            Confirmed
          </span>
        );
      case 'Pending':
        return (
          <span
            style={{
              padding: '4px 10px',
              borderRadius: '999px',
              fontSize: '11.5px',
              fontWeight: '600',
              backgroundColor: '#fef8e7',
              color: '#d97706',
              display: 'inline-block',
            }}
          >
            Pending
          </span>
        );
      case 'Completed':
        return (
          <span
            style={{
              padding: '4px 10px',
              borderRadius: '999px',
              fontSize: '11.5px',
              fontWeight: '600',
              backgroundColor: '#eff6ff',
              color: '#2563eb',
              display: 'inline-block',
            }}
          >
            Completed
          </span>
        );
      default:
        return (
          <span
            style={{
              padding: '4px 10px',
              borderRadius: '999px',
              fontSize: '11.5px',
              fontWeight: '600',
              backgroundColor: '#f1f5f9',
              color: '#64748b',
              display: 'inline-block',
            }}
          >
            {status}
          </span>
        );
    }
  };

  // Showing the 3 main rows as in the screenshot + expand option
  const displayBookings = recentBookingsData.slice(0, 3);

  return (
    <div
      style={{
        backgroundColor: 'var(--bg-card)',
        borderRadius: 'var(--radius-lg)',
        border: '1px solid var(--border-light)',
        padding: '22px 24px',
        boxShadow: 'var(--shadow-card)',
        display: 'flex',
        flexDirection: 'column',
        height: '100%',
      }}
    >
      {/* Header */}
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          marginBottom: '16px',
        }}
      >
        <h2
          style={{
            fontSize: '16px',
            fontWeight: '700',
            color: '#12251a',
          }}
        >
          Recent Bookings
        </h2>
        <button
          onClick={() => onSelectBooking && onSelectBooking(recentBookingsData[0])}
          style={{
            fontSize: '12px',
            fontWeight: '600',
            color: 'var(--primary-brand)',
            display: 'flex',
            alignItems: 'center',
            gap: '4px',
          }}
        >
          <span>View All</span>
          <ExternalLink size={13} />
        </button>
      </div>

      {/* Table Container */}
      <div className="table-responsive" style={{ overflowX: 'auto', WebkitOverflowScrolling: 'touch', flex: 1, width: '100%' }}>
        <table
          style={{
            minWidth: '600px',
            width: '100%',
            borderCollapse: 'collapse',
            textAlign: 'left',
          }}
        >
          <thead>
            <tr
              style={{
                borderBottom: '1px solid #f0f4f1',
                color: '#718278',
                fontSize: '12px',
                fontWeight: '600',
                whiteSpace: 'nowrap',
              }}
            >
              <th style={{ padding: '8px 12px 10px 4px', whiteSpace: 'nowrap' }}>Booking ID</th>
              <th style={{ padding: '8px 12px 10px 12px', whiteSpace: 'nowrap' }}>Customer</th>
              <th style={{ padding: '8px 12px 10px 12px', whiteSpace: 'nowrap' }}>Service</th>
              <th style={{ padding: '8px 12px 10px 12px', whiteSpace: 'nowrap' }}>Worker</th>
              <th style={{ padding: '8px 4px 10px 12px', textAlign: 'right', whiteSpace: 'nowrap' }}>Status</th>
            </tr>
          </thead>
          <tbody>
            {displayBookings.map((b) => (
              <tr
                key={b.id}
                onClick={() => onSelectBooking && onSelectBooking(b)}
                style={{
                  borderBottom: '1px solid #f5f8f6',
                  fontSize: '13px',
                  cursor: 'pointer',
                  transition: 'background-color 0.15s ease',
                  whiteSpace: 'nowrap',
                }}
                onMouseEnter={(e) => (e.currentTarget.style.backgroundColor = '#f9fbf9')}
                onMouseLeave={(e) => (e.currentTarget.style.backgroundColor = 'transparent')}
              >
                {/* Booking ID */}
                <td style={{ padding: '12px 12px 12px 4px', whiteSpace: 'nowrap' }}>
                  <span
                    style={{
                      color: 'var(--text-link)',
                      fontWeight: '600',
                      letterSpacing: '-0.2px',
                    }}
                  >
                    {b.id}
                  </span>
                </td>

                {/* Customer */}
                <td
                  style={{
                    padding: '12px',
                    fontWeight: '500',
                    color: '#203227',
                  }}
                >
                  {b.customer}
                </td>

                {/* Service */}
                <td
                  style={{
                    padding: '12px',
                    color: '#556b5e',
                    fontWeight: '500',
                  }}
                >
                  {b.service}
                </td>

                {/* Worker */}
                <td
                  style={{
                    padding: '12px',
                    color: '#203227',
                    fontWeight: '500',
                  }}
                >
                  {b.worker}
                </td>

                {/* Status Badge */}
                <td style={{ padding: '12px 4px 12px 12px', textAlign: 'right' }}>
                  {getStatusBadge(b.status)}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
