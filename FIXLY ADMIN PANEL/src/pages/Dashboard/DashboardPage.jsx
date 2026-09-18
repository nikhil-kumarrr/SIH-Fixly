import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useApp } from '../../context/AppContext';
import { useLanguage } from '../../context/LanguageContext';
import {
  User,
  IndianRupee,
  IdCard,
  Users,
  Star,
  ArrowUpRight,
  Navigation,
  Sparkles,
  Zap,
  Plus,
  Bell,
  ArrowRight,
  ExternalLink,
  ShieldCheck,
  CalendarCheck,
  Radio,
  Clock
} from 'lucide-react';

import WorkersLeafletMap from '../../components/map/WorkersLeafletMap';
import BookingsOverviewChart from '../../components/charts/BookingsOverviewChart';
import TopServicesCard from '../../components/TopServicesCard';
import Badge from '../../components/common/Badge';
import AddWorkerModal from '../../components/modals/AddWorkerModal';
import AddServiceModal from '../../components/modals/AddServiceModal';
import SendNotificationModal from '../../components/modals/SendNotificationModal';
import EmergencyDispatchModal from '../../components/modals/EmergencyDispatchModal';

export default function DashboardPage() {
  const navigate = useNavigate();
  const { t } = useLanguage();
  const {
    dashboardStats,
    recentBookings,
    workers,
    customers,
    bookings,
    services,
    notifications,
  } = useApp();

  // Modal controls
  const [isAddWorkerOpen, setIsAddWorkerOpen] = useState(false);
  const [isAddServiceOpen, setIsAddServiceOpen] = useState(false);
  const [isSendNotifOpen, setIsSendNotifOpen] = useState(false);
  const [emergencyBooking, setEmergencyBooking] = useState(null);
  const [isMobile, setIsMobile] = useState(() => typeof window !== 'undefined' && window.innerWidth <= 900);

  useEffect(() => {
    const handleResize = () => setIsMobile(window.innerWidth <= 900);
    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, []);

  const totalBookingsVal = dashboardStats?.totalBookings !== undefined ? dashboardStats.totalBookings.toLocaleString() : (bookings?.length || 0).toLocaleString();
  const totalRevenueVal = dashboardStats?.totalRevenue !== undefined ? `₹${dashboardStats.totalRevenue.toLocaleString('en-IN')}` : '₹0';
  const totalWorkersVal = dashboardStats?.totalWorkers !== undefined ? dashboardStats.totalWorkers.toLocaleString() : (workers?.length || 0).toLocaleString();
  const totalCustomersVal = dashboardStats?.totalCustomers !== undefined ? dashboardStats.totalCustomers.toLocaleString() : (customers?.length || 0).toLocaleString();

  // Top stats matching backend API
  const statCards = [
    {
      id: 'bookings',
      title: 'Total Bookings',
      value: totalBookingsVal,
      trend: 'Real-time',
      icon: User,
    },
    {
      id: 'revenue',
      title: 'Total Revenue',
      value: totalRevenueVal,
      trend: 'Gross Value',
      icon: IndianRupee,
    },
    {
      id: 'workers',
      title: 'Active Workers',
      value: totalWorkersVal,
      trend: 'Onboarded',
      icon: IdCard,
    },
    {
      id: 'customers',
      title: 'Total Customers',
      value: totalCustomersVal,
      trend: 'Registered',
      icon: Users,
    },
  ];

  const displayRecentBookings = (recentBookings || []).slice(0, 5).map((b) => ({
    id: b.bookingId || b._id,
    customer: b.customer?.name || 'Customer',
    service: b.service?.title || 'Gig Service',
    worker: b.worker?.name || 'Unassigned',
    status: b.status || 'SEARCHING',
  }));


  const [sosAlerts, setSosAlerts] = useState([]);

  useEffect(() => {
    if (typeof window !== 'undefined' && window.socket) {
      const handleSos = (data) => {
        setSosAlerts((prev) => [...prev, data]);
      };
      window.socket.on('sos:alert', handleSos);
      return () => {
        window.socket.off('sos:alert', handleSos);
      };
    }
  }, []);

  const activeEmergency = bookings.find((b) => b.status === 'Emergency');

  return (
    <div
      style={{
        display: 'flex',
        flexDirection: 'column',
        gap: '24px',
        padding: '0 32px 32px 32px',
        animation: 'fadeIn 0.25s ease',
      }}
    >
      {/* Emergency Flash Banner if any emergency booking exists */}
      {activeEmergency && (
        <div
          style={{
            backgroundColor: '#fef2f2',
            border: '1.5px solid #f87171',
            borderRadius: '14px',
            padding: '12px 18px',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            gap: '12px',
            animation: 'fadeIn 0.2s ease',
          }}
        >
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            <span style={{ fontSize: '20px' }}>🚨</span>
            <div>
              <span style={{ fontWeight: '800', color: '#991b1b', fontSize: '13.5px' }}>
                CRITICAL SOS TICKET: {activeEmergency.service} — {activeEmergency.serviceType}
              </span>
              <span style={{ fontSize: '12px', color: '#7f1d1d', marginLeft: '8px' }}>
                ({activeEmergency.customerAddress} • {activeEmergency.customerPhone})
              </span>
            </div>
          </div>

          <button
            onClick={() => setEmergencyBooking(activeEmergency)}
            style={{
              padding: '6px 14px',
              backgroundColor: '#dc2626',
              color: '#ffffff',
              borderRadius: '8px',
              fontSize: '12px',
              fontWeight: '700',
              boxShadow: '0 2px 8px rgba(220, 38, 38, 0.3)',
            }}
          >
            Dispatch Nearest Worker Now →
          </button>
        </div>
      )}

      {/* 1. Top KPI Stat Cards (4 Cards matching Screenshot + 1 Rating pill) */}
      <div
        className="stats-grid"
        style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(4, minmax(0, 1fr))',
          gap: '18px',
        }}
      >
        {statCards.map((stat) => {
          const Icon = stat.icon;
          return (
            <div
              key={stat.id}
              style={{
                backgroundColor: 'var(--bg-card)',
                borderRadius: 'var(--radius-lg)',
                border: '1px solid var(--border-light)',
                padding: '20px 22px',
                boxShadow: 'var(--shadow-card)',
                display: 'flex',
                flexDirection: 'column',
                justifyContent: 'space-between',
                minHeight: '120px',
                transition: 'transform 0.2s ease, box-shadow 0.2s ease',
              }}
              onMouseEnter={(e) => {
                e.currentTarget.style.transform = 'translateY(-3px)';
                e.currentTarget.style.boxShadow = 'var(--shadow-hover)';
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.transform = 'translateY(0)';
                e.currentTarget.style.boxShadow = 'var(--shadow-card)';
              }}
            >
              <div style={{ display: 'flex', alignItems: 'center', gap: '14px' }}>
                <div
                  style={{
                    width: '46px',
                    height: '46px',
                    borderRadius: '12px',
                    backgroundColor: '#eaf7ee',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    flexShrink: 0,
                  }}
                >
                  <Icon size={22} color="#1e7e45" strokeWidth={2.2} />
                </div>

                <div>
                  <div
                    style={{
                      fontSize: '22px',
                      fontWeight: '800',
                      color: '#111827',
                      lineHeight: '1.15',
                      letterSpacing: '-0.4px',
                    }}
                  >
                    {stat.value}
                  </div>
                  <div
                    style={{
                      fontSize: '12.5px',
                      color: 'var(--text-secondary)',
                      fontWeight: '500',
                      marginTop: '3px',
                    }}
                  >
                    {stat.title}
                  </div>
                </div>
              </div>

              <div
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: '4px',
                  marginTop: '14px',
                  paddingLeft: '60px',
                }}
              >
                <span
                  style={{
                    display: 'inline-flex',
                    alignItems: 'center',
                    gap: '2px',
                    fontSize: '12px',
                    fontWeight: '700',
                    color: '#15803d',
                  }}
                >
                  <ArrowUpRight size={14} strokeWidth={2.8} />
                  {stat.trend}
                </span>
              </div>
            </div>
          );
        })}
      </div>

      {/* 2. Middle Row: Bookings Overview (62%) + Top Services (38%) */}
      <div
        className="middle-grid"
        style={{
          display: 'grid',
          gridTemplateColumns: '1.65fr 1fr',
          gap: '20px',
          alignItems: 'stretch',
        }}
      >
        <div style={{ minHeight: '310px' }}>
          <BookingsOverviewChart />
        </div>
        <div style={{ minHeight: '310px' }}>
          <TopServicesCard onSelectService={() => navigate('/services')} />
        </div>
      </div>

      {/* 3. Bottom Row: Recent Bookings (62%) + Workers on Duty Live on Map (38%) */}
      <div
        className="bottom-grid"
        style={{
          display: 'grid',
          gridTemplateColumns: '1.65fr 1fr',
          gap: '20px',
          alignItems: 'stretch',
        }}
      >
        {/* Recent Bookings Card */}
        <div
          style={{
            backgroundColor: 'var(--bg-card)',
            borderRadius: 'var(--radius-lg)',
            border: '1px solid var(--border-light)',
            padding: isMobile ? '16px 14px' : '22px 24px',
            boxShadow: 'var(--shadow-card)',
            display: 'flex',
            flexDirection: 'column',
            justifyContent: 'space-between',
            minHeight: '230px',
            minWidth: 0,
            maxWidth: '100%',
            overflow: 'hidden',
          }}
        >
          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              marginBottom: '14px',
            }}
          >
            <h2 style={{ fontSize: '16px', fontWeight: '700', color: '#12251a' }}>
              Recent Bookings
            </h2>
            <button
              onClick={() => navigate('/bookings')}
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

          <div
            className="table-responsive"
            style={{
              overflowX: 'auto',
              WebkitOverflowScrolling: 'touch',
              width: '100%',
              maxWidth: '100%',
              display: 'block',
            }}
          >
            <table style={{ minWidth: '580px', width: '100%', borderCollapse: 'collapse', textAlign: 'left' }}>
              <thead>
                <tr style={{ borderBottom: '1px solid #f0f4f1', color: '#718278', fontSize: '12px', fontWeight: '600', whiteSpace: 'nowrap' }}>
                  <th style={{ padding: '8px 12px 10px 4px', whiteSpace: 'nowrap' }}>Booking ID</th>
                  <th style={{ padding: '8px 12px 10px 12px', whiteSpace: 'nowrap' }}>Customer</th>
                  <th style={{ padding: '8px 12px 10px 12px', whiteSpace: 'nowrap' }}>Service</th>
                  <th style={{ padding: '8px 12px 10px 12px', whiteSpace: 'nowrap' }}>Worker</th>
                  <th style={{ padding: '8px 4px 10px 12px', textAlign: 'right', whiteSpace: 'nowrap' }}>Status</th>
                </tr>
              </thead>
              <tbody>
                {displayRecentBookings.length === 0 ? (
                  <tr>
                    <td colSpan="5" style={{ padding: '24px', textAlign: 'center', color: '#64748b', fontSize: '13px' }}>
                      No recent bookings found in database.
                    </td>
                  </tr>
                ) : (
                  displayRecentBookings.map((b) => (
                    <tr
                      key={b.id}
                      onClick={() => navigate(`/bookings`)}
                      style={{ borderBottom: '1px solid #f5f8f6', fontSize: '13px', cursor: 'pointer', whiteSpace: 'nowrap' }}
                      onMouseEnter={(e) => (e.currentTarget.style.backgroundColor = '#f9fbf9')}
                      onMouseLeave={(e) => (e.currentTarget.style.backgroundColor = 'transparent')}
                    >
                      <td style={{ padding: '12px 12px 12px 4px', whiteSpace: 'nowrap' }}>
                        <span style={{ color: 'var(--text-link)', fontWeight: '600' }}>
                          {b.id}
                        </span>
                      </td>
                      <td style={{ padding: '12px', fontWeight: '500', color: '#203227', whiteSpace: 'nowrap' }}>
                        {b.customer}
                      </td>
                      <td style={{ padding: '12px', color: '#556b5e', fontWeight: '500', whiteSpace: 'nowrap' }}>
                        {b.service}
                      </td>
                      <td style={{ padding: '12px', color: '#203227', fontWeight: '500', whiteSpace: 'nowrap' }}>
                        {b.worker}
                      </td>
                      <td style={{ padding: '12px 4px 12px 12px', textAlign: 'right', whiteSpace: 'nowrap' }}>
                        <Badge status={b.status} />
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>

        {/* Workers on Duty Live on Map Banner */}
        <div
          style={{
            backgroundColor: 'var(--bg-card)',
            borderRadius: 'var(--radius-lg)',
            border: '1px solid var(--border-light)',
            padding: isMobile ? '16px' : '20px 24px',
            boxShadow: 'var(--shadow-card)',
            position: 'relative',
            overflow: 'hidden',
            display: 'flex',
            flexDirection: 'column',
            justifyContent: 'space-between',
            minHeight: isMobile ? 'auto' : '230px',
            gap: isMobile ? '14px' : '0',
            minWidth: 0,
            maxWidth: '100%',
          }}
        >
          {isMobile ? (
            /* Mobile Stacked Map Layout */
            <>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap', gap: '8px' }}>
                <div>
                  <h2 style={{ fontSize: '15px', fontWeight: '700', color: '#12251a', lineHeight: '1.2' }}>
                    Workers on Duty Live on Map
                  </h2>
                  <div
                    style={{
                      display: 'inline-flex',
                      alignItems: 'center',
                      gap: '6px',
                      marginTop: '4px',
                      fontSize: '11px',
                      color: '#15803d',
                      fontWeight: '600',
                      backgroundColor: '#eaf8ef',
                      padding: '2px 8px',
                      borderRadius: '999px',
                    }}
                  >
                    <span
                      style={{
                        width: '6px',
                        height: '6px',
                        borderRadius: '50%',
                        backgroundColor: '#15803d',
                      }}
                    />
                    <span>
                      {workers.filter((w) => Array.isArray(w.coordinates) && w.coordinates.length === 2).length}{' '}
                      with live GPS
                    </span>
                  </div>
                </div>

                <button
                  onClick={() => navigate('/workers?map=1')}
                  style={{
                    display: 'inline-flex',
                    alignItems: 'center',
                    gap: '6px',
                    backgroundColor: 'var(--primary-brand)',
                    color: '#ffffff',
                    padding: '6px 14px',
                    borderRadius: 'var(--radius-pill)',
                    fontSize: '12px',
                    fontWeight: '600',
                    boxShadow: 'var(--shadow-pill)',
                  }}
                >
                  <span>View Map</span>
                  <Navigation size={12} strokeWidth={2.4} />
                </button>
              </div>

              {/* Full Width Map Preview on Mobile */}
              <div
                style={{
                  width: '100%',
                  height: '180px',
                  borderRadius: '12px',
                  overflow: 'hidden',
                  position: 'relative',
                  border: '1px solid var(--border-light)',
                }}
              >
                <WorkersLeafletMap workers={workers} sosAlerts={sosAlerts} height="100%" />
              </div>
            </>
          ) : (
            /* Desktop Side-by-Side Map Layout */
            <>
              <div style={{ position: 'relative', zIndex: 2, maxWidth: '200px' }}>
                <h2 style={{ fontSize: '16px', fontWeight: '700', color: '#12251a', lineHeight: '1.3' }}>
                  Workers on Duty Live on Map
                </h2>
                <div
                  style={{
                    display: 'inline-flex',
                    alignItems: 'center',
                    gap: '6px',
                    marginTop: '6px',
                    fontSize: '11px',
                    color: '#15803d',
                    fontWeight: '600',
                    backgroundColor: '#eaf8ef',
                    padding: '2px 8px',
                    borderRadius: '999px',
                  }}
                >
                  <span
                    style={{
                      width: '6px',
                      height: '6px',
                      borderRadius: '50%',
                      backgroundColor: '#15803d',
                    }}
                  />
                  <span>
                    {workers.filter((w) => Array.isArray(w.coordinates) && w.coordinates.length === 2).length}{' '}
                    with live GPS
                  </span>
                </div>
              </div>

              <div
                style={{
                  position: 'absolute',
                  right: '0',
                  bottom: '0',
                  top: '0',
                  width: '60%',
                  zIndex: 1,
                }}
              >
                <WorkersLeafletMap workers={workers} sosAlerts={sosAlerts} height="100%" />
              </div>

              <div style={{ position: 'relative', zIndex: 2, marginTop: '20px' }}>
                <button
                  onClick={() => navigate('/workers?map=1')}
                  style={{
                    display: 'inline-flex',
                    alignItems: 'center',
                    gap: '8px',
                    backgroundColor: 'var(--primary-brand)',
                    color: '#ffffff',
                    padding: '9px 18px',
                    borderRadius: 'var(--radius-pill)',
                    fontSize: '13px',
                    fontWeight: '600',
                    boxShadow: 'var(--shadow-pill)',
                  }}
                >
                  <span>View Map</span>
                  <Navigation size={13} strokeWidth={2.4} />
                </button>
              </div>
            </>
          )}
        </div>
      </div>

      {/* 4. Quick Actions */}
      <div
        style={{
          backgroundColor: '#ffffff',
          borderRadius: '16px',
          border: '1px solid var(--border-light)',
          padding: '20px 24px',
          boxShadow: 'var(--shadow-card)',
        }}
      >
        <h3 style={{ fontSize: '15px', fontWeight: '700', color: '#111827', marginBottom: '14px' }}>
          ⚡ Fast Platform Operations
        </h3>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '10px' }}>
          <button
            onClick={() => setIsAddWorkerOpen(true)}
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '8px',
              padding: '10px 12px',
              borderRadius: '10px',
              backgroundColor: '#f8fafc',
              border: '1px solid #e2e8f0',
              fontSize: '12.5px',
              fontWeight: '600',
              color: '#334155',
              textAlign: 'left',
            }}
          >
            <Plus size={15} color="#1e7e45" />
            <span>Add New Worker</span>
          </button>

          <button
            onClick={() => setIsAddServiceOpen(true)}
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '8px',
              padding: '10px 12px',
              borderRadius: '10px',
              backgroundColor: '#f8fafc',
              border: '1px solid #e2e8f0',
              fontSize: '12.5px',
              fontWeight: '600',
              color: '#334155',
              textAlign: 'left',
            }}
          >
            <Zap size={15} color="#1e7e45" />
            <span>Add Service</span>
          </button>

          <button
            onClick={() => setIsSendNotifOpen(true)}
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '8px',
              padding: '10px 12px',
              borderRadius: '10px',
              backgroundColor: '#f8fafc',
              border: '1px solid #e2e8f0',
              fontSize: '12.5px',
              fontWeight: '600',
              color: '#334155',
              textAlign: 'left',
            }}
          >
            <Bell size={15} color="#1e7e45" />
            <span>Broadcast Alert</span>
          </button>
        </div>
      </div>

      {/* Modals */}
      <AddWorkerModal isOpen={isAddWorkerOpen} onClose={() => setIsAddWorkerOpen(false)} />
      <AddServiceModal isOpen={isAddServiceOpen} onClose={() => setIsAddServiceOpen(false)} />
      <SendNotificationModal isOpen={isSendNotifOpen} onClose={() => setIsSendNotifOpen(false)} />
      <EmergencyDispatchModal emergencyBooking={emergencyBooking} isOpen={!!emergencyBooking} onClose={() => setEmergencyBooking(null)} />
    </div>
  );
}
