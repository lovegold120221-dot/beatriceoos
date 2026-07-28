/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
*/
import { createContext, useContext, ReactNode, useEffect } from 'react';
import { auth } from '@/lib/firebase';
import { onAuthStateChanged } from 'firebase/auth';
import { useAuthStore, UserProfile } from '@/lib/auth-store';

interface AuthContextType {
  currentUser: UserProfile | null;
  logout: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export const useAuth = (): AuthContextType => {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
};

interface AuthProviderProps {
  children: ReactNode;
}

export default function AuthProvider({ children }: AuthProviderProps) {
  const setUser = useAuthStore(s => s.setUser);

  useEffect(() => {
    const unsubscribe = onAuthStateChanged(auth, (firebaseUser) => {
      if (firebaseUser) {
        const existingProfile = useAuthStore.getState().user;
        const profile: UserProfile = {
          uid: firebaseUser.uid,
          email: firebaseUser.email,
          displayName: firebaseUser.displayName || firebaseUser.email?.split('@')[0] || null,
          provider: firebaseUser.providerData[0]?.providerId ?? null,
          photoURL: existingProfile?.photoURL || firebaseUser.photoURL || null,
        };
        setUser(profile);
      } else {
        setUser(null);
      }
    });
    return () => unsubscribe();
  }, [setUser]);

  const logout = async () => {
    try {
      await auth.signOut();
    } catch (_err) {
      // Ignore sign-out errors
    }
  };

  return (
    <AuthContext.Provider value={{ currentUser: useAuthStore.getState().user, logout }}>
      {children}
    </AuthContext.Provider>
  );
}
