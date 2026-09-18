import data from './indiaStatesDistricts.json';

export const INDIA_STATES_DATA = data.states || [];

export const ALL_STATES = INDIA_STATES_DATA.map((s) => s.state).sort();

const districtsMap = new Map();
INDIA_STATES_DATA.forEach((s) => {
  districtsMap.set(s.state.toLowerCase().trim(), s.districts || []);
});

/**
 * Returns the list of districts for a given state (case-insensitive).
 */
export function getDistrictsForState(stateName) {
  if (!stateName) return [];
  const key = String(stateName).toLowerCase().trim();
  if (districtsMap.has(key)) {
    return districtsMap.get(key);
  }
  // Loose match fallback (e.g. if state contains or is contained by)
  for (const [s, dists] of districtsMap.entries()) {
    if (s.includes(key) || key.includes(s)) {
      return dists;
    }
  }
  return [];
}

/**
 * Filter states matching query
 */
export function filterStates(query = '') {
  const q = String(query).toLowerCase().trim();
  if (!q) return ALL_STATES;
  return ALL_STATES.filter((st) => st.toLowerCase().includes(q));
}

/**
 * Filter districts for a state matching query
 */
export function filterDistricts(stateName, query = '') {
  const all = getDistrictsForState(stateName);
  const q = String(query).toLowerCase().trim();
  if (!q) return all;
  return all.filter((d) => d.toLowerCase().includes(q));
}

export default {
  ALL_STATES,
  INDIA_STATES_DATA,
  getDistrictsForState,
  filterStates,
  filterDistricts,
};
