import axios from 'axios';

let envBase = import.meta.env.VITE_API_URL;
const isLocal =
  typeof window !== 'undefined' &&
  (window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1');

// When deployed on HTTPS (e.g. Netlify) and backend is HTTP, route through the Netlify reverse proxy
// (/api/admin) so the browser doesn't block it with "Mixed Content" or CORS errors.
if (
  typeof window !== 'undefined' &&
  window.location.protocol === 'https:' &&
  envBase &&
  envBase.startsWith('http://')
) {
  envBase = '/api/admin';
}

const API_BASE_URL = envBase || (isLocal ? 'http://localhost:8000/api/admin' : '/api/admin');

const adminApi = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    'Content-Type': 'application/json'
  }
});

// Request Interceptor: Attach JWT Token & Auto-handle FormData
adminApi.interceptors.request.use(
  (config) => {
    const token = sessionStorage.getItem('adminToken');
    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
    }
    if (config.data instanceof FormData) {
      delete config.headers['Content-Type'];
    }
    return config;
  },
  (error) => Promise.reject(error)
);

// Response Interceptor: Handle 401 Unauthorized
adminApi.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response && error.response.status === 401) {
      // If unauthorized and not on login request, clear token and redirect
      if (!error.config.url.includes('/login')) {
        sessionStorage.removeItem('adminToken');
        sessionStorage.removeItem('adminUser');
        if (window.location.pathname !== '/login') {
          window.location.href = '/login';
        }
      }
    }
    return Promise.reject(error);
  }
);

export const api = {
  // Auth
  login: async (email, password) => {
    const res = await adminApi.post('/login', { email, password });
    return res.data;
  },
  getProfile: async () => {
    const res = await adminApi.get('/me');
    return res.data;
  },
  updateProfile: async (data) => {
    const res = await adminApi.put('/me', data);
    return res.data;
  },

  // Dashboard
  getDashboardStats: async () => {
    const res = await adminApi.get('/dashboard');
    return res.data;
  },

  // Customers
  getCustomers: async (params = {}) => {
    const res = await adminApi.get('/customers', { params });
    return res.data;
  },
  getCustomerById: async (id) => {
    const res = await adminApi.get(`/customers/${id}`);
    return res.data;
  },
  toggleCustomerStatus: async (id, isVerified) => {
    const res = await adminApi.patch(`/customers/${id}/status`, { isVerified });
    return res.data;
  },

  // Workers
  getWorkers: async (params = {}) => {
    const res = await adminApi.get('/workers', { params });
    return res.data;
  },
  getWorkerById: async (id) => {
    const res = await adminApi.get(`/workers/${id}`);
    return res.data;
  },
  updateWorker: async (id, data) => {
    const res = await adminApi.put(`/workers/${id}`, data);
    return res.data;
  },
  updateWorkerStatus: async (id, data) => {
    const res = await adminApi.patch(`/workers/${id}/status`, data);
    return res.data;
  },
  addWorker: async (workerData) => {
    const res = await adminApi.post('/workers', workerData);
    return res.data;
  },

  // Bookings
  getBookings: async (params = {}) => {
    const res = await adminApi.get('/bookings', { params });
    return res.data;
  },
  getBookingById: async (id) => {
    const res = await adminApi.get(`/bookings/${id}`);
    return res.data;
  },
  assignWorkerToBooking: async (bookingId, workerId) => {
    const res = await adminApi.patch(`/bookings/${bookingId}/assign`, { workerId });
    return res.data;
  },
  updateBookingStatus: async (bookingId, data) => {
    const res = await adminApi.patch(`/bookings/${bookingId}/status`, data);
    return res.data;
  },

  // Services
  getServices: async (params = {}) => {
    const res = await adminApi.get('/services', { params });
    return res.data;
  },
  createService: async (serviceData) => {
    const res = await adminApi.post('/services', serviceData);
    return res.data;
  },
  updateService: async (id, serviceData) => {
    const res = await adminApi.put(`/services/${id}`, serviceData);
    return res.data;
  },
  deleteService: async (id) => {
    const res = await adminApi.delete(`/services/${id}`);
    return res.data;
  },
  syncServicesCache: async () => {
    const res = await adminApi.post('/services/sync-cache');
    return res.data;
  },

  // Payments
  getPayments: async (params = {}) => {
    const res = await adminApi.get('/payments', { params });
    return res.data;
  },
  getPaymentStats: async () => {
    const res = await adminApi.get('/payments/stats');
    return res.data;
  },

  // Reviews
  getReviews: async (params = {}) => {
    const res = await adminApi.get('/reviews', { params });
    return res.data;
  },
  deleteReview: async (id) => {
    const res = await adminApi.delete(`/reviews/${id}`);
    return res.data;
  },

  // Notifications & Broadcast
  sendAdminNotification: async (notifData) => {
    const res = await adminApi.post('/notifications/broadcast', notifData);
    return res.data;
  },

  // Notifications
  getNotifications: async () => {
    const res = await adminApi.get('/notifications');
    return res.data;
  },
  sendNotification: async (data) => {
    const res = await adminApi.post('/notifications/broadcast', data);
    return res.data;
  },
  markAllNotificationsRead: async () => {
    const res = await adminApi.put('/notifications/mark-read');
    return res.data;
  },
  deleteNotification: async (id) => {
    const res = await adminApi.delete(`/notifications/${id}`);
    return res.data;
  },

  // Analytics & AI Insights
  getAnalytics: async () => {
    const res = await adminApi.get('/analytics');
    return res.data;
  },
  getAIInsights: async () => {
    const res = await adminApi.get('/ai-insights');
    return res.data;
  },
  getReportsData: async () => {
    const res = await adminApi.get('/reports');
    return res.data;
  },

  // Governance Settings
  getSettings: async () => {
    const res = await adminApi.get('/settings');
    return res.data;
  },
  updateSettings: async (settingsData) => {
    const res = await adminApi.put('/settings', settingsData);
    return res.data;
  },

  // Cooperative Federation Governance
  getCooperative: async () => {
    const res = await adminApi.get('/cooperative');
    return res.data;
  },
  updateCooperative: async (coopData) => {
    const res = await adminApi.put('/cooperative', coopData);
    return res.data;
  },

  // Primary Cooperative Societies
  getSocieties: async (params = {}) => {
    const res = await adminApi.get('/cooperative/societies', { params });
    return res.data;
  },
  createSociety: async (societyData) => {
    const res = await adminApi.post('/cooperative/societies', societyData);
    return res.data;
  },
  getSocietyById: async (id) => {
    const res = await adminApi.get(`/cooperative/societies/${id}`);
    return res.data;
  },
  updateSociety: async (id, societyData) => {
    const res = await adminApi.put(`/cooperative/societies/${id}`, societyData);
    return res.data;
  },
  assignWorkerToSociety: async (data) => {
    const res = await adminApi.post('/cooperative/assign-worker', data);
    return res.data;
  },

  // Promotional Coupon Banners
  getBanners: async () => {
    const res = await adminApi.get('/banners');
    return res.data;
  },
  createBanner: async (bannerData) => {
    const res = await adminApi.post('/banners', bannerData);
    return res.data;
  },
  updateBanner: async (id, bannerData) => {
    const res = await adminApi.put(`/banners/${id}`, bannerData);
    return res.data;
  },
  deleteBanner: async (id) => {
    const res = await adminApi.delete(`/banners/${id}`);
    return res.data;
  },

  // Support Desk & AI Chatbot
  getSupportTickets: async (params) => {
    const res = await adminApi.get('/support/tickets', { params });
    return res.data;
  },
  getSupportTicketById: async (id) => {
    const res = await adminApi.get(`/support/tickets/${id}`);
    return res.data;
  },
  sendSupportMessage: async (id, message) => {
    const res = await adminApi.post(`/support/tickets/${id}/messages`, { body: message });
    return res.data;
  },
  takeoverSupportTicket: async (id) => {
    const res = await adminApi.post(`/support/tickets/${id}/takeover`);
    return res.data;
  },
  updateSupportTicketStatus: async (id, statusData) => {
    const res = await adminApi.patch(`/support/tickets/${id}`, statusData);
    return res.data;
  },

  // Federations
  getAllFederations: async () => {
    const res = await adminApi.get('/federations');
    return res.data;
  },
  createFederation: async (federationData) => {
    const res = await adminApi.post('/federations', federationData);
    return res.data;
  },
  impersonateFederation: async (id) => {
    const res = await adminApi.post(`/federations/${id}/impersonate`);
    return res.data;
  },
  getFederationDetails: async (id) => {
    const res = await adminApi.get(`/federations/${id}`);
    return res.data;
  },
  approveFederation: async (id) => {
    const res = await adminApi.patch(`/federations/${id}/approve`);
    return res.data;
  },
  suspendFederation: async (id) => {
    const res = await adminApi.patch(`/federations/${id}/suspend`);
    return res.data;
  },

  // Languages
  getEnabledLanguages: async () => {
    const res = await adminApi.get('/settings/languages');
    return res.data;
  },
  updateEnabledLanguages: async (languages) => {
    const res = await adminApi.put('/settings/languages', { languages });
    return res.data;
  },

  // Platform Governance Settings
  getSettings: async () => {
    const res = await adminApi.get('/settings');
    return res.data;
  },
  updateSettings: async (settingsData) => {
    const res = await adminApi.put('/settings', settingsData);
    return res.data;
  },

  // Mobile App Version & Force Update Governance
  getAppVersion: async () => {
    const res = await adminApi.get('/settings/app-version');
    return res.data;
  },
  updateAppVersion: async (versionData) => {
    const res = await adminApi.put('/settings/app-version', versionData);
    return res.data;
  },

  // Redis Cache Flush & Memory Management
  clearRedisCache: async (type = 'all') => {
    const res = await adminApi.post(`/redis/clear/${type}`);
    return res.data;
  },

  // Image & File Upload
  uploadImage: async (file) => {
    const formData = new FormData();
    formData.append('file', file);
    const res = await adminApi.post('/upload', formData);
    return res.data;
  },

  // Welfare Resources & e-Shram Guides
  getWelfareResources: async () => {
    const res = await adminApi.get('/welfare/resources');
    return res.data;
  },
  createWelfareResource: async (data) => {
    const res = await adminApi.post('/welfare/resources', data);
    return res.data;
  },
  updateWelfareResource: async (id, data) => {
    const res = await adminApi.put(`/welfare/resources/${id}`, data);
    return res.data;
  },
  deleteWelfareResource: async (id) => {
    const res = await adminApi.delete(`/welfare/resources/${id}`);
    return res.data;
  },
  uploadWelfareResourcePdf: async (file) => {
    const formData = new FormData();
    formData.append('file', file);
    formData.append('folder', 'insurance_welfare');
    formData.append('type', 'welfare');
    const res = await adminApi.post('/welfare/resources/upload', formData);
    return res.data;
  },

  // Emergency Contacts
  getEmergencyContacts: async () => {
    const res = await adminApi.get('/emergency/contacts');
    return res.data;
  },
  createEmergencyContact: async (data) => {
    const res = await adminApi.post('/emergency/contacts', data);
    return res.data;
  },
  updateEmergencyContact: async (id, data) => {
    const res = await adminApi.put(`/emergency/contacts/${id}`, data);
    return res.data;
  },
  deleteEmergencyContact: async (id) => {
    const res = await adminApi.delete(`/emergency/contacts/${id}`);
    return res.data;
  },

  // Demand Forecast
  getDemandForecast: async () => {
    const res = await adminApi.get('/ai/demand-forecast');
    return res.data;
  }
};

export default adminApi;
