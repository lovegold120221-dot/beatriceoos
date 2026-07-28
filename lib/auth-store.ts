/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
*/
import { create } from 'zustand';

export interface UserProfile {
  uid: string;
  email: string | null;
  displayName: string | null;
  provider: string | null;
  photoURL: string | null;
}

type AuthState = {
  user: UserProfile | null;
  isAuthenticated: boolean;
  isLoading: boolean;
  _authFlowPhase: 'splash' | 'auth' | 'app';
  setUser: (user: UserProfile | null) => void;
  setIsLoading: (loading: boolean) => void;
  resetAuthFlow: () => void;
};

export const useAuthStore = create<AuthState>((set) => ({
  user: (() => {
    try {
      const stored = localStorage.getItem('beatrice_auth');
      return stored ? JSON.parse(stored) : null;
    } catch {
      return null;
    }
   })(),
  isAuthenticated: false,
  isLoading: false,
  _authFlowPhase: 'app',
  setUser: (user) => {
    set({ user, isAuthenticated: !!user });
    if (user) {
      localStorage.setItem('beatrice_auth', JSON.stringify(user));
      } else {
      localStorage.removeItem('beatrice_auth');
     }
   },
  setIsLoading: (isLoading) => set({ isLoading }),
  resetAuthFlow: () => {
    set({ _authFlowPhase: 'splash' });
  },
}));
