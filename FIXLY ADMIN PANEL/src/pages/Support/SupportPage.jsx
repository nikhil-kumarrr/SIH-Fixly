import React, { useState, useEffect, useRef } from 'react';
import {
  MessageSquare,
  Bot,
  User,
  Headphones,
  Search,
  Send,
  CheckCircle2,
  AlertCircle,
  Clock,
  ArrowRight,
  RefreshCw,
  Phone,
  Mail,
  Shield,
  Briefcase,
  Sparkles,
  Zap,
  ChevronRight,
  ArrowLeft
} from 'lucide-react';
import { api } from '../../services/api';
import { useToast } from '../../context/ToastContext';
import Badge from '../../components/common/Badge';

const CANNED_RESPONSES = [
  "Hello! I am taking over this chat to assist you directly.",
  "We are checking your booking details right now.",
  "We have contacted your service technician for immediate update.",
  "Your refund for extra parts has been initiated and will credit in 24 hrs.",
  "Could you please share more details or a photo if applicable?",
  "Your ticket has been marked resolved. Feel free to reach out anytime!"
];

export default function SupportPage() {
  const { showToast } = useToast();

  const [tickets, setTickets] = useState([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [selectedTicketId, setSelectedTicketId] = useState(null);
  const [selectedTicket, setSelectedTicket] = useState(null);
  const [ticketDetailLoading, setTicketDetailLoading] = useState(false);
  const [isMobile, setIsMobile] = useState(() => typeof window !== 'undefined' && window.innerWidth <= 900);

  useEffect(() => {
    const handleResize = () => setIsMobile(window.innerWidth <= 900);
    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, []);

  // Filters & Search
  const [statusTab, setStatusTab] = useState('ALL'); // ALL, ESCALATED, AGENT_ACTIVE, BOT_ACTIVE, RESOLVED
  const [roleFilter, setRoleFilter] = useState('ALL'); // ALL, customer, worker
  const [searchQuery, setSearchQuery] = useState('');

  // Chat message input
  const [messageText, setMessageText] = useState('');
  const [sending, setSending] = useState(false);

  const messagesEndRef = useRef(null);

  // Fetch Tickets List
  const fetchTickets = async (silent = false) => {
    if (!silent) setLoading(true);
    try {
      const res = await api.getSupportTickets({
        status: statusTab !== 'ALL' ? statusTab : undefined,
        userRole: roleFilter !== 'ALL' ? roleFilter : undefined,
        search: searchQuery || undefined
      });
      if (res?.success && Array.isArray(res?.data)) {
        setTickets(res.data);
        // If nothing selected and tickets available, select first
        if (!selectedTicketId && res.data.length > 0) {
          setSelectedTicketId(res.data[0]._id);
        }
      }
    } catch (err) {
      if (!silent) {
        showToast(err.response?.data?.message || 'Failed to load support tickets', 'error');
      }
    } finally {
      if (!silent) setLoading(false);
      setRefreshing(false);
    }
  };

  // Fetch Selected Ticket Details
  const fetchTicketDetails = async (ticketId, silent = false) => {
    if (!ticketId) return;
    if (!silent) setTicketDetailLoading(true);
    try {
      const res = await api.getSupportTicketById(ticketId);
      if (res?.success && res?.data) {
        setSelectedTicket(res.data);
      }
    } catch (err) {
      if (!silent) {
        showToast('Failed to load conversation details', 'error');
      }
    } finally {
      if (!silent) setTicketDetailLoading(false);
    }
  };

  // Initial load and filter effect
  useEffect(() => {
    fetchTickets();
  }, [statusTab, roleFilter]);

  // Load ticket details on selection
  useEffect(() => {
    if (selectedTicketId) {
      fetchTicketDetails(selectedTicketId);
    }
  }, [selectedTicketId]);

  // Live polling for real-time updates every 4 seconds
  useEffect(() => {
    const interval = setInterval(() => {
      fetchTickets(true);
      if (selectedTicketId) {
        fetchTicketDetails(selectedTicketId, true);
      }
    }, 4000);
    return () => clearInterval(interval);
  }, [selectedTicketId, statusTab, roleFilter]);

  // Auto scroll to latest message
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [selectedTicket?.messages]);

  // Handle Send Message
  const handleSendMessage = async (customText = null) => {
    const textToSend = (customText || messageText).trim();
    if (!textToSend || !selectedTicketId || sending) return;

    setSending(true);
    try {
      const res = await api.sendSupportMessage(selectedTicketId, textToSend);
      if (res?.success) {
        setMessageText('');
        fetchTicketDetails(selectedTicketId, true);
        fetchTickets(true);
        showToast('Reply sent successfully', 'success');
      }
    } catch (err) {
      showToast(err.response?.data?.message || 'Failed to send message', 'error');
    } finally {
      setSending(false);
    }
  };

  // Handle Take Over Chat
  const handleTakeover = async () => {
    if (!selectedTicketId) return;
    try {
      const res = await api.takeoverSupportTicket(selectedTicketId);
      if (res?.success) {
        showToast('You have taken over this support chat from AI!', 'success');
        fetchTicketDetails(selectedTicketId, true);
        fetchTickets(true);
      }
    } catch (err) {
      showToast(err.response?.data?.message || 'Failed to take over chat', 'error');
    }
  };

  // Handle Status Change
  const handleStatusChange = async (newStatus) => {
    if (!selectedTicketId) return;
    try {
      const res = await api.updateSupportTicketStatus(selectedTicketId, { status: newStatus });
      if (res?.success) {
        showToast(`Ticket status updated to ${newStatus}`, 'success');
        fetchTicketDetails(selectedTicketId, true);
        fetchTickets(true);
      }
    } catch (err) {
      showToast(err.response?.data?.message || 'Failed to update status', 'error');
    }
  };

  // Counts for tabs
  const escalatedCount = tickets.filter(t => t.status === 'ESCALATED').length;
  const agentActiveCount = tickets.filter(t => t.status === 'AGENT_ACTIVE').length;
  const botCount = tickets.filter(t => t.status === 'BOT_ACTIVE').length;

  const resolvedCount = tickets.filter(t => t.status === 'RESOLVED' || t.status === 'CLOSED').length;

  return (
    <div style={{ padding: '0 32px 32px 32px', height: 'calc(100vh - 105px)', display: 'flex', flexDirection: 'column', boxSizing: 'border-box', animation: 'fadeIn 0.2s ease' }}>
      {/* Top Header */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '16px', flexWrap: 'wrap', gap: '12px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '14px' }}>
          <div
            style={{
              width: '44px',
              height: '44px',
              borderRadius: '12px',
              backgroundColor: '#eaf7ee',
              color: '#15803d',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              boxShadow: '0 2px 6px rgba(21,128,61,0.12)',
            }}
          >
            <Headphones size={22} />
          </div>
          <div>
            <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
              <h2 style={{ fontSize: '20px', fontWeight: '700', color: '#111827', margin: 0 }}>
                Support Desk & AI Chatbot
              </h2>
              {escalatedCount > 0 && (
                <span
                  style={{
                    display: 'inline-flex',
                    alignItems: 'center',
                    gap: '4px',
                    padding: '2px 9px',
                    fontSize: '11px',
                    fontWeight: '700',
                    backgroundColor: '#fef3c7',
                    color: '#b45309',
                    border: '1px solid #fde68a',
                    borderRadius: '20px',
                  }}
                >
                  <AlertCircle size={12} /> {escalatedCount} Escalated
                </span>
              )}
            </div>
            <p style={{ fontSize: '13px', color: '#64748b', margin: '2px 0 0 0' }}>
              Real-time customer & worker support queries handled by AI with seamless human takeover
            </p>
          </div>
        </div>

        {/* Live Counters & Refresh */}
        <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '12px', color: '#64748b' }}>
            <span style={{ padding: '4px 10px', borderRadius: '8px', backgroundColor: '#f1f5f9', fontWeight: '600', color: '#334155' }}>
              Total: {tickets.length}
            </span>
            <span style={{ padding: '4px 10px', borderRadius: '8px', backgroundColor: '#ecfdf5', fontWeight: '600', color: '#047857' }}>
              💬 Live Chat: {agentActiveCount}
            </span>
            <span style={{ padding: '4px 10px', borderRadius: '8px', backgroundColor: '#f5f3ff', fontWeight: '600', color: '#6b21a8' }}>
              🤖 AI Bot: {botCount}
            </span>
          </div>

          <button
            onClick={() => { setRefreshing(true); fetchTickets(); }}
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              gap: '6px',
              padding: '8px 14px',
              backgroundColor: '#ffffff',
              color: '#334155',
              borderRadius: '8px',
              border: '1px solid #cbd5e1',
              fontSize: '13px',
              fontWeight: '600',
              cursor: 'pointer',
              boxShadow: '0 1px 2px rgba(0,0,0,0.04)',
            }}
          >
            <RefreshCw size={14} style={{ animation: refreshing ? 'spin 1s linear infinite' : 'none' }} />
            <span>Refresh</span>
          </button>
        </div>
      </div>

      {/* Main Workspace (Two-Pane Layout) */}
      <div style={{ display: 'flex', gap: '18px', flex: 1, minHeight: 0, width: '100%' }}>
        {/* LEFT COLUMN: Ticket Queue Sidebar */}
        {(!isMobile || !selectedTicketId) && (
          <div
            style={{
              width: isMobile ? '100%' : '380px',
              minWidth: isMobile ? '0' : '340px',
              maxWidth: isMobile ? '100%' : '400px',
              flexShrink: 0,
              backgroundColor: '#ffffff',
              borderRadius: '14px',
              border: '1px solid var(--border-light)',
              boxShadow: 'var(--shadow-card)',
              display: 'flex',
              flexDirection: 'column',
              overflow: 'hidden',
            }}
          >
          {/* Search & Filters */}
          <div style={{ padding: '14px', borderBottom: '1px solid #f1f5f9', display: 'flex', flexDirection: 'column', gap: '10px' }}>
            {/* Search Input */}
            <div style={{ position: 'relative', width: '100%' }}>
              <Search size={14} style={{ position: 'absolute', left: '12px', top: '50%', transform: 'translateY(-50%)', color: '#94a3b8' }} />
              <input
                type="text"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                onKeyDown={(e) => e.key === 'Enter' && fetchTickets()}
                placeholder="Search ticket #, name, query..."
                style={{
                  width: '100%',
                  boxSizing: 'border-box',
                  paddingLeft: '34px',
                  paddingRight: '12px',
                  paddingTop: '8px',
                  paddingBottom: '8px',
                  fontSize: '12.5px',
                  backgroundColor: '#f8fafc',
                  border: '1px solid #e2e8f0',
                  borderRadius: '8px',
                  outline: 'none',
                  color: '#1e293b',
                }}
              />
              {searchQuery && (
                <button
                  onClick={() => { setSearchQuery(''); fetchTickets(); }}
                  style={{ position: 'absolute', right: '10px', top: '50%', transform: 'translateY(-50%)', color: '#94a3b8', cursor: 'pointer' }}
                >
                  <X size={13} />
                </button>
              )}
            </div>

            {/* Status Filter Chips */}
            <div style={{ display: 'flex', gap: '5px', overflowX: 'auto', paddingBottom: '2px' }}>
              {[
                { key: 'ALL', label: 'All', count: tickets.length },
                { key: 'ESCALATED', label: '⚠️ Escalated', count: escalatedCount },
                { key: 'AGENT_ACTIVE', label: '💬 In Chat', count: agentActiveCount },
                { key: 'BOT_ACTIVE', label: '🤖 AI Bot', count: botCount },
                { key: 'RESOLVED', label: '✅ Resolved', count: resolvedCount },
              ].map((tab) => {
                const isActive = statusTab === tab.key;
                return (
                  <button
                    key={tab.key}
                    onClick={() => setStatusTab(tab.key)}
                    style={{
                      padding: '5px 9px',
                      borderRadius: '8px',
                      fontSize: '11px',
                      fontWeight: '600',
                      whiteSpace: 'nowrap',
                      border: 'none',
                      cursor: 'pointer',
                      display: 'flex',
                      alignItems: 'center',
                      gap: '5px',
                      backgroundColor: isActive ? 'var(--primary-brand)' : '#f1f5f9',
                      color: isActive ? '#ffffff' : '#475569',
                      boxShadow: isActive ? '0 1px 3px rgba(21,128,61,0.2)' : 'none',
                      transition: 'all 0.15s ease',
                    }}
                  >
                    <span>{tab.label}</span>
                    {tab.count !== undefined && tab.count > 0 && (
                      <span
                        style={{
                          fontSize: '10px',
                          padding: '1px 5px',
                          borderRadius: '10px',
                          fontWeight: '700',
                          backgroundColor: isActive ? 'rgba(255,255,255,0.25)' : '#e2e8f0',
                          color: isActive ? '#ffffff' : '#334155',
                        }}
                      >
                        {tab.count}
                      </span>
                    )}
                  </button>
                );
              })}
            </div>

            {/* Role Filter Chips */}
            <div style={{ display: 'flex', alignItems: 'center', gap: '6px', paddingTop: '4px', borderTop: '1px solid #f8fafc', fontSize: '11px' }}>
              <span style={{ color: '#94a3b8', fontWeight: '600' }}>Role:</span>
              {[
                { key: 'ALL', label: 'All Roles' },
                { key: 'customer', label: 'Customers' },
                { key: 'worker', label: 'Workers' },
              ].map((role) => {
                const isActive = roleFilter === role.key;
                return (
                  <button
                    key={role.key}
                    onClick={() => setRoleFilter(role.key)}
                    style={{
                      padding: '3px 8px',
                      borderRadius: '6px',
                      fontSize: '11px',
                      fontWeight: '600',
                      cursor: 'pointer',
                      border: 'none',
                      backgroundColor: isActive ? '#1e293b' : 'transparent',
                      color: isActive ? '#ffffff' : '#64748b',
                      transition: 'all 0.15s ease',
                    }}
                  >
                    {role.label}
                  </button>
                );
              })}
            </div>
          </div>

          {/* Ticket Queue List */}
          <div style={{ flex: 1, overflowY: 'auto', display: 'flex', flexDirection: 'column' }}>
            {loading ? (
              <div style={{ padding: '40px', textAlign: 'center', color: '#94a3b8', fontSize: '12.5px', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '8px' }}>
                <RefreshCw size={20} style={{ animation: 'spin 1s linear infinite', color: 'var(--primary-brand)' }} />
                <span>Loading tickets queue...</span>
              </div>
            ) : tickets.length === 0 ? (
              <div style={{ padding: '40px 20px', textAlign: 'center', color: '#94a3b8', fontSize: '12.5px', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '10px' }}>
                <MessageSquare size={28} style={{ color: '#cbd5e1' }} />
                <span style={{ fontWeight: '600', color: '#64748b' }}>No tickets found</span>
                <span style={{ fontSize: '11.5px', color: '#94a3b8' }}>No conversations match the selected filters.</span>
              </div>
            ) : (
              tickets.map((t) => {
                const isSelected = t._id === selectedTicketId;
                const lastMsg = t.messages?.[t.messages.length - 1];
                const senderRole = t.createdBy?.role || t.userRole || 'customer';
                const isWorker = senderRole === 'worker';

                return (
                  <div
                    key={t._id}
                    onClick={() => setSelectedTicketId(t._id)}
                    style={{
                      padding: '12px 14px',
                      cursor: 'pointer',
                      borderBottom: '1px solid #f1f5f9',
                      borderLeft: isSelected ? '4px solid var(--primary-brand)' : '4px solid transparent',
                      backgroundColor: isSelected ? '#f0fdf4' : '#ffffff',
                      display: 'flex',
                      flexDirection: 'column',
                      gap: '6px',
                      transition: 'all 0.12s ease',
                    }}
                  >
                    {/* Top row: Avatar + Name + Status */}
                    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '8px' }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '8px', minWidth: 0 }}>
                        <div
                          style={{
                            width: '28px',
                            height: '28px',
                            borderRadius: '50%',
                            backgroundColor: isWorker ? '#fef3c7' : '#dbeafe',
                            color: isWorker ? '#b45309' : '#1e40af',
                            display: 'flex',
                            alignItems: 'center',
                            justifyContent: 'center',
                            fontWeight: '700',
                            fontSize: '11px',
                            flexShrink: 0,
                          }}
                        >
                          {isWorker ? 'W' : 'C'}
                        </div>
                        <span style={{ fontWeight: '700', fontSize: '12.5px', color: '#0f172a', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                          {t.createdBy?.name || 'User'}
                        </span>
                        <span
                          style={{
                            fontSize: '10px',
                            padding: '1px 6px',
                            borderRadius: '4px',
                            fontWeight: '600',
                            textTransform: 'uppercase',
                            backgroundColor: isWorker ? '#fffbeb' : '#eff6ff',
                            color: isWorker ? '#92400e' : '#1e40af',
                          }}
                        >
                          {senderRole}
                        </span>
                      </div>

                      <Badge status={t.status} />
                    </div>

                    {/* Preview of last message */}
                    <p
                      style={{
                        margin: 0,
                        fontSize: '11.5px',
                        color: '#475569',
                        display: '-webkit-box',
                        WebkitLineClamp: 2,
                        WebkitBoxOrient: 'vertical',
                        overflow: 'hidden',
                        lineHeight: '1.4',
                      }}
                    >
                      {lastMsg?.body || t.description || 'No messages yet'}
                    </p>

                    {/* Bottom row: Ticket # + Handler + Time */}
                    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', fontSize: '10.5px', color: '#94a3b8', paddingTop: '2px' }}>
                      <span style={{ fontFamily: 'monospace', color: '#64748b' }}>{t.ticketNumber}</span>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                        {t.handledBy === 'BOT' ? (
                          <span style={{ display: 'inline-flex', alignItems: 'center', gap: '3px', color: '#7c3aed', fontWeight: '600' }}>
                            <Bot size={11} /> AI Bot
                          </span>
                        ) : (
                          <span style={{ display: 'inline-flex', alignItems: 'center', gap: '3px', color: '#15803d', fontWeight: '600' }}>
                            <Headphones size={11} /> Agent
                          </span>
                        )}
                        <span>•</span>
                        <span>
                          {new Date(t.lastMessageAt || t.updatedAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                        </span>
                      </div>
                    </div>
                  </div>
                );
              })
            )}
          </div>
        </div>
        )}

        {/* RIGHT COLUMN: Interactive Live Chat & Takeover Console */}
        {(!isMobile || selectedTicketId) && (
          <div
            style={{
              flex: 1,
              minWidth: 0,
              backgroundColor: '#ffffff',
              borderRadius: '14px',
              border: '1px solid var(--border-light)',
              boxShadow: 'var(--shadow-card)',
              display: 'flex',
              flexDirection: 'column',
              overflow: 'hidden',
              width: isMobile ? '100%' : 'auto',
            }}
          >
            {!selectedTicket ? (
              <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: '40px', textAlign: 'center', color: '#94a3b8' }}>
                <div
                  style={{
                    width: '64px',
                    height: '64px',
                    borderRadius: '16px',
                    backgroundColor: '#f1f5f9',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    color: '#94a3b8',
                    marginBottom: '16px',
                  }}
                >
                  <MessageSquare size={32} />
                </div>
                <h3 style={{ fontSize: '16px', fontWeight: '700', color: '#334155', margin: '0 0 6px 0' }}>
                  Select a Support Conversation
                </h3>
                <p style={{ fontSize: '13px', color: '#64748b', maxWidth: '380px', margin: 0, lineHeight: '1.5' }}>
                  Pick any ticket from the left queue to view live AI interactions, take over the conversation, or send direct resolution messages.
                </p>
              </div>
            ) : (
              <>
                {/* Console Header Bar */}
                <div
                  style={{
                    padding: isMobile ? '10px 14px' : '14px 20px',
                    borderBottom: '1px solid #e2e8f0',
                    backgroundColor: '#f8fafc',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'space-between',
                    flexWrap: 'wrap',
                    gap: '10px',
                  }}
                >
                  {/* Mobile Back button */}
                  {isMobile && (
                    <button
                      onClick={() => { setSelectedTicketId(null); setSelectedTicket(null); }}
                      style={{
                        display: 'inline-flex',
                        alignItems: 'center',
                        gap: 6,
                        padding: '6px 10px',
                        borderRadius: 8,
                        backgroundColor: '#e2e8f0',
                        border: 'none',
                        fontSize: 12,
                        fontWeight: 700,
                        color: '#334155',
                        cursor: 'pointer'
                      }}
                    >
                      <ArrowLeft size={14} /> Back to Queue
                    </button>
                  )}

                  {/* User Information */}
                  <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                    <div
                      style={{
                        width: '40px',
                        height: '40px',
                        borderRadius: '50%',
                        backgroundColor: selectedTicket.userRole === 'worker' ? '#fef3c7' : '#dbeafe',
                        color: selectedTicket.userRole === 'worker' ? '#b45309' : '#1e40af',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        fontSize: '15px',
                        fontWeight: '700',
                        flexShrink: 0,
                      }}
                    >
                      {selectedTicket.createdBy?.name?.[0] || 'U'}
                    </div>
                  <div>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '8px', flexWrap: 'wrap' }}>
                      <h3 style={{ fontSize: '15px', fontWeight: '700', color: '#0f172a', margin: 0 }}>
                        {selectedTicket.createdBy?.name || 'User'}
                      </h3>
                      <span
                        style={{
                          fontSize: '11px',
                          padding: '1px 6px',
                          borderRadius: '4px',
                          fontWeight: '600',
                          textTransform: 'uppercase',
                          backgroundColor: selectedTicket.userRole === 'worker' ? '#fffbeb' : '#eff6ff',
                          color: selectedTicket.userRole === 'worker' ? '#92400e' : '#1e40af',
                        }}
                      >
                        {selectedTicket.userRole || selectedTicket.createdBy?.role || 'user'}
                      </span>
                      <span style={{ fontFamily: 'monospace', fontSize: '12px', color: '#64748b' }}>
                        {selectedTicket.ticketNumber}
                      </span>
                      <Badge status={selectedTicket.status} />
                    </div>

                    <div style={{ display: 'flex', alignItems: 'center', gap: '14px', fontSize: '12px', color: '#64748b', marginTop: '3px' }}>
                      {selectedTicket.createdBy?.phone && (
                        <span style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
                          <Phone size={12} style={{ color: '#94a3b8' }} />
                          {selectedTicket.createdBy.phone}
                        </span>
                      )}
                      {selectedTicket.createdBy?.email && (
                        <span style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
                          <Mail size={12} style={{ color: '#94a3b8' }} />
                          {selectedTicket.createdBy.email}
                        </span>
                      )}
                    </div>
                  </div>
                </div>

                {/* Status & Takeover Actions */}
                <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                  {/* Take Over Button */}
                  {(selectedTicket.handledBy === 'BOT' || selectedTicket.status === 'ESCALATED') && (
                    <button
                      onClick={handleTakeover}
                      style={{
                        display: 'inline-flex',
                        alignItems: 'center',
                        gap: '6px',
                        padding: '8px 14px',
                        backgroundColor: '#15803d',
                        color: '#ffffff',
                        borderRadius: '8px',
                        fontSize: '12.5px',
                        fontWeight: '600',
                        border: 'none',
                        cursor: 'pointer',
                        boxShadow: '0 2px 4px rgba(21,128,61,0.2)',
                        transition: 'all 0.15s ease',
                      }}
                    >
                      <Headphones size={14} />
                      <span>Take Over Chat</span>
                    </button>
                  )}

                  {/* Status Dropdown */}
                  <select
                    value={selectedTicket.status}
                    onChange={(e) => handleStatusChange(e.target.value)}
                    style={{
                      fontSize: '12.5px',
                      fontWeight: '600',
                      padding: '8px 12px',
                      borderRadius: '8px',
                      border: '1px solid #cbd5e1',
                      backgroundColor: '#ffffff',
                      color: '#334155',
                      outline: 'none',
                      cursor: 'pointer',
                    }}
                  >
                    <option value="BOT_ACTIVE">🤖 AI Bot Active</option>
                    <option value="ESCALATED">⚠️ Escalated</option>
                    <option value="AGENT_ACTIVE">💬 Agent Active</option>
                    <option value="WAITING_FOR_USER">⏳ Waiting for User</option>
                    <option value="RESOLVED">✅ Resolved</option>
                    <option value="CLOSED">🔒 Closed</option>
                  </select>
                </div>
              </div>

              {/* Escalation Alert Banner */}
              {selectedTicket.status === 'ESCALATED' && (
                <div
                  style={{
                    padding: '10px 18px',
                    backgroundColor: '#fffbeb',
                    borderBottom: '1px solid #fde68a',
                    color: '#92400e',
                    fontSize: '12.5px',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'space-between',
                  }}
                >
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px', fontWeight: '500' }}>
                    <AlertCircle size={16} style={{ color: '#d97706', flexShrink: 0 }} />
                    <span>User requested human support or AI could not resolve this query. Click &quot;Take Over Chat&quot; to assist directly.</span>
                  </div>
                  <button
                    onClick={handleTakeover}
                    style={{
                      padding: '4px 10px',
                      backgroundColor: '#d97706',
                      color: '#ffffff',
                      borderRadius: '6px',
                      fontSize: '11px',
                      fontWeight: '700',
                      border: 'none',
                      cursor: 'pointer',
                    }}
                  >
                    Take Over
                  </button>
                </div>
              )}

              {/* Live Chat Message Stream */}
              <div
                style={{
                  flex: 1,
                  overflowY: 'auto',
                  padding: '20px',
                  backgroundColor: '#f8fafc',
                  display: 'flex',
                  flexDirection: 'column',
                  gap: '14px',
                }}
              >
                {ticketDetailLoading ? (
                  <div style={{ padding: '40px', textAlign: 'center', color: '#94a3b8', fontSize: '13px', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '8px' }}>
                    <RefreshCw size={20} style={{ animation: 'spin 1s linear infinite', color: 'var(--primary-brand)' }} />
                    <span>Loading conversation history...</span>
                  </div>
                ) : (
                  selectedTicket.messages?.map((msg, index) => {
                    const isUser = msg.role === 'customer' || msg.role === 'worker';
                    const isAi = msg.role === 'ai';
                    const isAdmin = msg.role === 'admin';
                    const isSystem = msg.role === 'system';

                    if (isSystem) {
                      return (
                        <div key={index} style={{ display: 'flex', justifyContent: 'center', margin: '6px 0' }}>
                          <span
                            style={{
                              fontSize: '11px',
                              padding: '4px 14px',
                              borderRadius: '20px',
                              backgroundColor: '#e2e8f0',
                              color: '#475569',
                              fontWeight: '600',
                            }}
                          >
                            {msg.body}
                          </span>
                        </div>
                      );
                    }

                    return (
                      <div
                        key={index}
                        style={{
                          display: 'flex',
                          flexDirection: 'column',
                          alignItems: isAdmin ? 'flex-end' : 'flex-start',
                          maxWidth: '100%',
                        }}
                      >
                        {/* Sender Label & Timestamp */}
                        <div style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '11px', color: '#94a3b8', marginBottom: '4px', paddingLeft: '4px', paddingRight: '4px' }}>
                          {isAi && (
                            <span style={{ display: 'inline-flex', alignItems: 'center', gap: '4px', color: '#7c3aed', fontWeight: '700' }}>
                              <Sparkles size={12} /> Fixly AI
                            </span>
                          )}
                          {isAdmin && (
                            <span style={{ display: 'inline-flex', alignItems: 'center', gap: '4px', color: '#15803d', fontWeight: '700' }}>
                              <Headphones size={12} /> Support Admin (You)
                            </span>
                          )}
                          {isUser && (
                            <span style={{ fontWeight: '600', color: '#475569' }}>
                              {msg.senderName || selectedTicket.createdBy?.name || 'User'} ({msg.role})
                            </span>
                          )}
                          <span>•</span>
                          <span>
                            {new Date(msg.createdAt || Date.now()).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                          </span>
                        </div>

                        {/* Message Bubble */}
                        <div
                          style={{
                            maxWidth: isAdmin ? '70%' : '76%',
                            padding: '12px 16px',
                            borderRadius: isAdmin ? '14px 14px 2px 14px' : '14px 14px 14px 2px',
                            fontSize: '13px',
                            lineHeight: '1.5',
                            backgroundColor: isAdmin ? '#15803d' : isAi ? '#f5f3ff' : '#ffffff',
                            color: isAdmin ? '#ffffff' : isAi ? '#2e1065' : '#1e293b',
                            border: isAdmin ? 'none' : isAi ? '1px solid #ddd6fe' : '1px solid #e2e8f0',
                            boxShadow: isAdmin ? '0 2px 6px rgba(21,128,61,0.2)' : '0 1px 3px rgba(0,0,0,0.04)',
                          }}
                        >
                          <p style={{ margin: 0, whiteSpace: 'pre-wrap' }}>{msg.body}</p>

                          {/* Quick replies preview if AI provided them */}
                          {msg.quickReplies && msg.quickReplies.length > 0 && (
                            <div style={{ marginTop: '10px', paddingTop: '8px', borderTop: '1px solid #ede9fe', display: 'flex', flexDirection: 'column', gap: '4px' }}>
                              <span style={{ fontSize: '10.5px', color: '#6b21a8', fontWeight: '600' }}>
                                AI Suggested options given to user:
                              </span>
                              <div style={{ display: 'flex', flexWrap: 'wrap', gap: '4px' }}>
                                {msg.quickReplies.map((qr, i) => (
                                  <span
                                    key={i}
                                    style={{
                                      fontSize: '10.5px',
                                      padding: '2px 8px',
                                      borderRadius: '12px',
                                      backgroundColor: '#ffffff',
                                      color: '#6b21a8',
                                      border: '1px solid #ddd6fe',
                                      fontWeight: '500',
                                    }}
                                  >
                                    {qr}
                                  </span>
                                ))}
                              </div>
                            </div>
                          )}
                        </div>
                      </div>
                    );
                  })
                )}
                <div ref={messagesEndRef} />
              </div>

              {/* Admin Canned Quick Response Chips */}
              <div style={{ padding: '8px 16px', borderTop: '1px solid #f1f5f9', backgroundColor: '#ffffff', display: 'flex', alignItems: 'center', gap: '8px', overflowX: 'auto' }}>
                <span style={{ fontSize: '11px', color: '#94a3b8', fontWeight: '600', whiteSpace: 'nowrap' }}>
                  Quick Replies:
                </span>
                {CANNED_RESPONSES.map((snip, idx) => (
                  <button
                    key={idx}
                    onClick={() => handleSendMessage(snip)}
                    style={{
                      padding: '4px 10px',
                      borderRadius: '16px',
                      backgroundColor: '#f8fafc',
                      color: '#475569',
                      fontSize: '11px',
                      fontWeight: '500',
                      border: '1px solid #e2e8f0',
                      whiteSpace: 'nowrap',
                      cursor: 'pointer',
                      display: 'inline-flex',
                      alignItems: 'center',
                      gap: '4px',
                      transition: 'all 0.15s ease',
                    }}
                  >
                    <Zap size={11} style={{ color: '#d97706' }} />
                    <span>{snip.length > 34 ? snip.slice(0, 34) + '...' : snip}</span>
                  </button>
                ))}
              </div>

              {/* Chat Input Bar */}
              <div style={{ padding: '12px 16px', borderTop: '1px solid #e2e8f0', backgroundColor: '#ffffff' }}>
                {selectedTicket.handledBy === 'BOT' && selectedTicket.status !== 'ESCALATED' && (
                  <div
                    style={{
                      fontSize: '11.5px',
                      color: '#6b21a8',
                      backgroundColor: '#f5f3ff',
                      padding: '6px 12px',
                      borderRadius: '8px',
                      marginBottom: '10px',
                      display: 'flex',
                      alignItems: 'center',
                      gap: '6px',
                      border: '1px solid #ede9fe',
                    }}
                  >
                    <Bot size={14} />
                    <span>Fixly AI Assistant is currently active. Sending a reply will automatically switch this chat to Human Support.</span>
                  </div>
                )}

                <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                  <input
                    type="text"
                    value={messageText}
                    onChange={(e) => setMessageText(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter' && !e.shiftKey) {
                        e.preventDefault();
                        handleSendMessage();
                      }
                    }}
                    placeholder="Type your response to user... (Press Enter to send)"
                    disabled={sending || selectedTicket.status === 'CLOSED'}
                    style={{
                      flex: 1,
                      padding: '10px 14px',
                      fontSize: '13px',
                      backgroundColor: '#f8fafc',
                      border: '1px solid #cbd5e1',
                      borderRadius: '10px',
                      outline: 'none',
                      color: '#1e293b',
                    }}
                  />

                  {/* Mark as Resolved Quick Action */}
                  {selectedTicket.status !== 'RESOLVED' && selectedTicket.status !== 'CLOSED' && (
                    <button
                      onClick={() => handleStatusChange('RESOLVED')}
                      style={{
                        padding: '10px 14px',
                        backgroundColor: '#f0fdf4',
                        color: '#15803d',
                        borderRadius: '10px',
                        border: '1px solid #bbf7d0',
                        fontSize: '12.5px',
                        fontWeight: '600',
                        cursor: 'pointer',
                        whiteSpace: 'nowrap',
                      }}
                    >
                      Resolve Ticket
                    </button>
                  )}

                  {/* Send Button */}
                  <button
                    onClick={() => handleSendMessage()}
                    disabled={sending || !messageText.trim() || selectedTicket.status === 'CLOSED'}
                    style={{
                      padding: '10px 18px',
                      backgroundColor: sending || !messageText.trim() ? '#94a3b8' : 'var(--primary-brand)',
                      color: '#ffffff',
                      borderRadius: '10px',
                      fontSize: '13px',
                      fontWeight: '600',
                      border: 'none',
                      cursor: sending || !messageText.trim() ? 'not-allowed' : 'pointer',
                      display: 'inline-flex',
                      alignItems: 'center',
                      gap: '6px',
                      boxShadow: '0 2px 4px rgba(21,128,61,0.2)',
                    }}
                  >
                    <Send size={14} />
                    <span>Send</span>
                  </button>
                </div>
              </div>
            </>
          )}
        </div>
        )}
      </div>
    </div>
  );
}
