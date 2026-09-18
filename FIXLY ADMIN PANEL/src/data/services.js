export const OFFICIAL_CATEGORIES = [
  'Electrician',
  'Plumber',
  'Carpenter',
  'Painter',
  'Gardener',
  'Domestic Helper',
  'Caregiving',
  'Driver',
  'Technician',
  'Cleaning',
];

/**
 * Converts any string to Title Case (Each word's first character uppercase, rest lowercase)
 * Handles snake_case, kebab-case, extra whitespace cleanly.
 * e.g., 'plumber' -> 'Plumber'
 * e.g., 'domestic_helper' -> 'Domestic Helper'
 * e.g., 'ac repair' -> 'Ac Repair'
 */
export const toTitleCase = (str = '') => {
  if (!str || typeof str !== 'string') return '';
  return str
    .replace(/[_-]+/g, ' ')
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
    .join(' ');
};

/**
 * Normalizes any category string into Title Case for UI display.
 * Dynamic: does not hardcode words with else-if chains!
 */
export const normalizeCategory = (category = '') => {
  if (!category) return '';
  return toTitleCase(category.trim());
};

export const getMergedCategories = (dynamicList = []) => {
  const custom = (dynamicList || [])
    .map(s => s.category || s.service || s.trade)
    .filter(Boolean)
    .map(c => normalizeCategory(c));
  return Array.from(new Set([...OFFICIAL_CATEGORIES, ...custom]));
};

export const initialServices = [
  {
    id: 'SRV-01',
    name: 'Plumbing Services',
    category: 'Plumber',
    description: 'Expert pipe repairs, leakage fixes, bathroom fittings, motor installation, and sanitary maintenance.',
    basePrice: '₹350',
    rawPrice: 350,
    requiredSkills: 'Hydro-Tech Certification, Leakage Detection, Soldering',
    availability: '24/7 Available',
    emergencyAvailable: true,
    status: 'Active',
    activeWorkers: 2197,
    completedTasks: '18,420',
    avgRating: 4.9,
    percentage: 25,
    icon: 'Wrench',
    iconColor: '#1e40af',
    bg: '#eff6ff',
    coopWelfarePercent: 5,
  },
  {
    id: 'SRV-02',
    name: 'Electrical Repairs & Wiring',
    category: 'Electrical',
    description: 'Circuit troubleshooting, MCB replacement, appliance wiring, switchboard fix, and inverter installation.',
    basePrice: '₹400',
    rawPrice: 400,
    requiredSkills: 'Safety License, Wire Gauging, Voltage Testing',
    availability: '24/7 Available',
    emergencyAvailable: true,
    status: 'Active',
    activeWorkers: 1757,
    completedTasks: '14,890',
    avgRating: 4.8,
    percentage: 20,
    icon: 'Zap',
    iconColor: '#ca8a04',
    bg: '#fefce8',
    coopWelfarePercent: 5,
  },
  {
    id: 'SRV-03',
    name: 'Deep Home & Office Cleaning',
    category: 'Cleaning',
    description: 'Full house sanitization, kitchen & bathroom deep scrubbing, sofa & carpet shampooing.',
    basePrice: '₹799',
    rawPrice: 799,
    requiredSkills: 'Sanitization Protocols, Chemical Safety, Machine Handling',
    availability: '07:00 AM - 09:00 PM',
    emergencyAvailable: false,
    status: 'Active',
    activeWorkers: 1318,
    completedTasks: '11,200',
    avgRating: 4.7,
    percentage: 15,
    icon: 'Sparkles',
    iconColor: '#16a34a',
    bg: '#f0fdf4',
    coopWelfarePercent: 5,
  },
  {
    id: 'SRV-04',
    name: 'Carpentry & Woodwork',
    category: 'Carpentry',
    description: 'Custom furniture repairs, door lock installation, hinge adjustments, and modular wood fittings.',
    basePrice: '₹380',
    rawPrice: 380,
    requiredSkills: 'Wood Joinery, Power Tool Mastery, Precision Cutting',
    availability: '08:00 AM - 08:00 PM',
    emergencyAvailable: true,
    status: 'Active',
    activeWorkers: 1318,
    completedTasks: '9,840',
    avgRating: 4.8,
    percentage: 15,
    icon: 'Hammer',
    iconColor: '#ea580c',
    bg: '#fff7ed',
    coopWelfarePercent: 5,
  },
  {
    id: 'SRV-05',
    name: 'AC Repair & HVAC Servicing',
    category: 'AC Repair',
    description: 'Jet pump servicing, gas charging, compressor diagnosis, PCB repair, and new split AC installation.',
    basePrice: '₹499',
    rawPrice: 499,
    requiredSkills: 'Refrigerant Handling, Electrical PCB, Pressure Check',
    availability: '08:00 AM - 10:00 PM',
    emergencyAvailable: true,
    status: 'Active',
    activeWorkers: 980,
    completedTasks: '7,400',
    avgRating: 4.85,
    percentage: 8,
    icon: 'Wind',
    iconColor: '#0284c7',
    bg: '#f0f9ff',
    coopWelfarePercent: 5,
  },
  {
    id: 'SRV-06',
    name: 'Elderly & Patient Caregiving',
    category: 'Caregiving',
    description: 'Compassionate assistance for senior citizens, post-operative nursing, mobility aid, and medication timing.',
    basePrice: '₹600',
    rawPrice: 600,
    requiredSkills: 'GDA Nursing Certification, CPR, Patient Empathy',
    availability: '24/7 Shifts',
    emergencyAvailable: true,
    status: 'Active',
    activeWorkers: 640,
    completedTasks: '4,650',
    avgRating: 4.95,
    percentage: 6,
    icon: 'HeartHandshake',
    iconColor: '#db2777',
    bg: '#fdf2f8',
    coopWelfarePercent: 5,
  },
  {
    id: 'SRV-07',
    name: 'Professional House Painting',
    category: 'Painting',
    description: 'Interior & exterior emulsion, texture walls, waterproof coatings, and wood polishing.',
    basePrice: '₹1,200',
    rawPrice: 1200,
    requiredSkills: 'Surface Prep, Roller Technique, Color Matching',
    availability: '08:00 AM - 07:00 PM',
    emergencyAvailable: false,
    status: 'Active',
    activeWorkers: 850,
    completedTasks: '5,900',
    avgRating: 4.75,
    percentage: 5,
    icon: 'Paintbrush',
    iconColor: '#9333ea',
    bg: '#faf5ff',
    coopWelfarePercent: 5,
  },
  {
    id: 'SRV-08',
    name: 'On-Demand Verified Drivers',
    category: 'Driving',
    description: 'City rides, outstation trips, night drivers, and emergency car chauffeurs.',
    basePrice: '₹350',
    rawPrice: 350,
    requiredSkills: 'Commercial Transport License, GPS Route Mastery',
    availability: '24/7 Available',
    emergencyAvailable: true,
    status: 'Active',
    activeWorkers: 720,
    completedTasks: '6,100',
    avgRating: 4.8,
    percentage: 4,
    icon: 'Car',
    iconColor: '#0d9488',
    bg: '#f0fdfa',
    coopWelfarePercent: 5,
  },
  {
    id: 'SRV-09',
    name: 'Gardening & Landscaping',
    category: 'Gardening',
    description: 'Lawn mowing, plant pruning, organic fertilization, terrace garden setup, and soil conditioning.',
    basePrice: '₹300',
    rawPrice: 300,
    requiredSkills: 'Horticulture Basics, Pest Treatment, Lawn Mowing',
    availability: '07:00 AM - 06:00 PM',
    emergencyAvailable: false,
    status: 'Active',
    activeWorkers: 450,
    completedTasks: '3,200',
    avgRating: 4.85,
    percentage: 2,
    icon: 'Trees',
    iconColor: '#65a30d',
    bg: '#f7fee7',
    coopWelfarePercent: 5,
  }
];
