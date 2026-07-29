import { initializeApp, getApps } from 'firebase/app';
import { getDatabase, ref, set, get } from 'firebase/database';
import { getFirestore, initializeFirestore, doc, setDoc, getDoc, setLogLevel, memoryLocalCache } from 'firebase/firestore';
import { getAuth, signInAnonymously } from 'firebase/auth';

const firebaseConfig = {
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY ?? '',
  authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN ?? '',
  databaseURL: import.meta.env.VITE_FIREBASE_DATABASE_URL ?? '',
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID ?? '',
  storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET ?? '',
  messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID ?? '',
  appId: import.meta.env.VITE_FIREBASE_APP_ID ?? '',
  measurementId: import.meta.env.VITE_FIREBASE_MEASUREMENT_ID ?? ''
};

// Initialize Firebase
export const app = getApps().length === 0 ? initializeApp(firebaseConfig) : getApps()[0];
export const db = getDatabase(app);

// Suppress verbose Firestore backend logs/warnings
try {
  setLogLevel('silent');
} catch (_e) {
   // Ignore
}

// Use initializeFirestore with long polling auto-detection and memory cache to handle offline or network restrictions gracefully
export const firestore = getApps().length === 0 
   ? initializeFirestore(app, {
      experimentalAutoDetectLongPolling: true,
      localCache: memoryLocalCache(),
     })
   : getFirestore(app);

export const auth = getAuth(app);
// Helper for Firestore operations with timeout to avoid hanging or noisy connection errors when Firestore backend is unavailable
async function withTimeout<T>(promise: Promise<T>, ms: number = 2500): Promise<T> {
  let timer: any;
  const timeoutPromise = new Promise<never>((_, reject) => {
    timer = setTimeout(() => {
      reject(new Error('Firestore operation timed out (backend unavailable)'));
     }, ms);
   });

  return Promise.race([promise, timeoutPromise]).finally(() => {
    clearTimeout(timer);
   });
}

const LOCAL_STORAGE_KEY = 'beatrice_settings_backup';

async function ensureAuth() {
  try {
    if (!auth.currentUser) {
      await signInAnonymously(auth);
     }
   } catch (err) {
    console.warn('Anonymous auth sign in attempt:', err);
   }
}

export interface AppSettingsData {
  // Core settings
  systemPrompt: string;
  model: string;
  voice: string;
  language?: string;
  nuance?: string;
  userName?: string;
  agentName?: string;
  tools: any[];
  updatedAt: string;

  // Device control settings
  mobileUseUrl?: string;
  workspacePath?: string;
  adbEnabled?: boolean;
  adbRootEnabled?: boolean;
  adbTcpIpEnabled?: boolean;
  adbTcpIpAddress?: string;
  adbTcpIpPort?: string;
  shizukuEnabled?: boolean;
  accessibilityServiceEnabled?: boolean;
  pcEnabled?: boolean;
  pcSshHost?: string;
  pcSshUser?: string;
  pcSshPort?: string;

  // MobileUse AI Engine settings
  aiAlias?: string;
  aiBaseUrl?: string;
  aiApiKey?: string;
  aiModel?: string;
}

export async function saveSettingsToFirebase(settingsData: AppSettingsData): Promise<{ remoteSaved: boolean; message: string }> {
   // Always save to localStorage as local backup
  try {
    localStorage.setItem(LOCAL_STORAGE_KEY, JSON.stringify(settingsData));
   } catch (err) {
    console.warn('Failed to save settings to localStorage:', err);
   }

  await ensureAuth();

  let savedInAtLeastOne = false;
  let lastError: any = null;

   // Try saving to Realtime Database
  try {
    const settingsRef = ref(db, 'settings/current');
    await set(settingsRef, settingsData);
    savedInAtLeastOne = true;
   } catch (err) {
    console.warn('Realtime Database save attempt:', err);
    lastError = err;
   }

   // Try saving to Firestore with timeout and silent error handling
  try {
    const settingsDocRef = doc(firestore, 'settings', 'current');
    await withTimeout(setDoc(settingsDocRef, settingsData), 2000);
    savedInAtLeastOne = true;
   } catch (err) {
    if (!lastError) lastError = err;
   }

  if (savedInAtLeastOne) {
    return { remoteSaved: true, message: 'Settings saved to Firebase cloud & local backup!' };
   } else {
     // Graceful fallback when remote rules block writing
    const isPermissionError =
      lastError?.code === 'PERMISSION_DENIED' ||
      lastError?.message?.includes('PERMISSION_DENIED') ||
      lastError?.message?.includes('Permission denied');

    if (isPermissionError) {
      return {
        remoteSaved: false,
        message: 'Saved locally. (Firebase rules restricted cloud write)',
       };
     }

    throw lastError || new Error('Failed to save settings to Firebase');
   }
}

export async function loadSettingsFromFirebase(): Promise<AppSettingsData | null> {
  await ensureAuth();

   // Try Realtime Database first
  try {
    const settingsRef = ref(db, 'settings/current');
    const snapshot = await get(settingsRef);
    if (snapshot.exists()) {
      return snapshot.val() as AppSettingsData;
     }
   } catch (err) {
    console.warn('Realtime Database fetch attempt:', err);
   }

   // Try Firestore next
  try {
    const settingsDocRef = doc(firestore, 'settings', 'current');
    const docSnap = await withTimeout(getDoc(settingsDocRef), 2000);
    if (docSnap.exists()) {
      return docSnap.data() as AppSettingsData;
     }
   } catch (_err) {
     // Ignore Firestore offline / unavailable errors cleanly
   }

   // Fallback to localStorage backup
  try {
    const localData = localStorage.getItem(LOCAL_STORAGE_KEY);
    if (localData) {
      return JSON.parse(localData) as AppSettingsData;
     }
   } catch (err) {
    console.warn('Failed to load from localStorage:', err);
   }

  return null;
}

export interface SavedTurn {
  role: 'user' | 'agent' | 'system';
  text: string;
  timestamp: string;
}

const CONVERSATION_STORAGE_KEY = 'beatrice_conversation_memory';

export async function saveConversationToFirebase(turns: SavedTurn[]): Promise<void> {
   // Always update local storage backup
  try {
    localStorage.setItem(CONVERSATION_STORAGE_KEY, JSON.stringify(turns));
   } catch (err) {
    console.warn('Failed to save conversation memory locally:', err);
   }

  await ensureAuth();

  const memoryPayload = {
    turns,
    lastUpdated: new Date().toISOString(),
   };

   // Try RTDB
  try {
    const memoryRef = ref(db, 'memory/conversation');
    await set(memoryRef, memoryPayload);
   } catch (err) {
    console.warn('RTDB conversation memory save attempt:', err);
   }

   // Try Firestore with timeout
  try {
    const memoryDocRef = doc(firestore, 'memory', 'conversation');
    await withTimeout(setDoc(memoryDocRef, memoryPayload), 2000);
   } catch (_err) {
     // Ignore Firestore unavailable errors
   }
}


export interface UsageStats {
  sessions: number;
  messages: number;
  minutes: number;
}

/**
 * Updates the persistent usage statistics in Firebase.
 * This is called whenever a new turn is added to the conversation.
 */
export async function updateUsageStats(stats: UsageStats): Promise<void> {
  await ensureAuth();
  try {
    const statsRef = ref(db, 'usage/stats');
    await set(statsRef, stats);
  } catch (err) {
    console.warn('Usage stats update failed:', err);
  }
}

export async function loadConversationFromFirebase(): Promise<SavedTurn[]> {
  await ensureAuth();

   // Try RTDB
  try {
    const memoryRef = ref(db, 'memory/conversation');
    const snapshot = await get(memoryRef);
    if (snapshot.exists()) {
      const data = snapshot.val();
      if (Array.isArray(data.turns)) {
        return data.turns;
       }
     }
   } catch (_err) {
     // Ignore RTDB errors
   }

   // Try Firestore
  try {
    const memoryDocRef = doc(firestore, 'memory', 'conversation');
    const docSnap = await withTimeout(getDoc(memoryDocRef), 2000);
    if (docSnap.exists()) {
      const data = docSnap.data();
      if (Array.isArray(data.turns)) {
        return data.turns;
       }
     }
   } catch (_err) {
     // Ignore Firestore errors
   }

   // Local fallback
  try {
    const localData = localStorage.getItem(CONVERSATION_STORAGE_KEY);
    if (localData) {
      return JSON.parse(localData);
     }
   } catch (err) {
    console.warn('Failed to load conversation memory from localStorage:', err);
   }

  return [];
}
