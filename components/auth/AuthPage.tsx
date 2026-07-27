/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
*/
import { useState } from 'react';
import { signInWithEmailAndPassword, createUserWithEmailAndPassword } from 'firebase/auth';
import { GoogleAuthProvider, signInWithPopup } from 'firebase/auth';
import { auth } from '@/lib/firebase';
import './AuthPage.css';

type Mode = 'login' | 'signup';

interface AuthPageProps {
  onAuthenticated: () => void;
}

const googleProvider = new GoogleAuthProvider();
googleProvider.addScope('profile');
googleProvider.addScope('email');

export default function AuthPage({ onAuthenticated }: AuthPageProps) {
  const [mode, setMode] = useState<Mode>('login');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [googleLoading, setGoogleLoading] = useState(false);

  const handleEmailAuth = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setLoading(true);
    try {
      if (mode === 'login') {
        await signInWithEmailAndPassword(auth, email, password);
      } else {
        await createUserWithEmailAndPassword(auth, email, password);
      }
      onAuthenticated();
    } catch (err: any) {
      let message = 'Authentication failed.';
      switch (err.code) {
        case 'auth/invalid-email':
          message = 'Invalid email address.';
          break;
        case 'auth/user-not-found':
          message = 'No account found. Please sign up first.';
          break;
        case 'auth/wrong-password':
          message = 'Incorrect password.';
          break;
        case 'auth/email-already-in-use':
          message = 'An account with this email already exists.';
          break;
        case 'auth/weak-password':
          message = 'Password must be at least 6 characters.';
          break;
        default:
          message = err.message || message;
      }
      setError(message);
    } finally {
      setLoading(false);
    }
  };

  const handleGoogleSignIn = async () => {
    setError(null);
    setGoogleLoading(true);
    try {
      await signInWithPopup(auth, googleProvider);
      onAuthenticated();
    } catch (err: any) {
      if (err.code !== 'auth/popup-closed-by-user') {
        setError(err.message || 'Google sign-in failed.');
      }
    } finally {
      setGoogleLoading(false);
    }
  };

  return (
    <div className="mobile-app auth-container">
      <div className="auth-header">
        <h1 className="auth-title">Beatrice</h1>
        <p className="auth-subtitle">Sign in to continue</p>
      </div>

      <form onSubmit={handleEmailAuth} className="auth-form">
        {error && <div className="auth-error">{error}</div>}

        <div className="auth-field">
          <label htmlFor="email">Email</label>
          <input
            id="email"
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="you@example.com"
            autoComplete="email"
            required
          />
        </div>

        <div className="auth-field">
          <label htmlFor="password">Password</label>
          <input
            id="password"
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="••••••••"
            autoComplete={mode === 'login' ? 'current-password' : 'new-password'}
            required
          />
        </div>

        <button
          type="submit"
          className="auth-btn auth-btn-primary"
          disabled={loading}
        >
          {loading
            ? mode === 'login'
              ? 'Signing in…'
              : 'Creating account…'
            : mode === 'login'
            ? 'Sign In'
            : 'Create Account'}
        </button>
      </form>

      <div className="auth-divider">
        <span>or</span>
      </div>

      <button
        className="auth-btn auth-btn-google"
        onClick={handleGoogleSignIn}
        disabled={googleLoading}
      >
        <svg viewBox="0 0 24 24" width="20" height="20">
          <path fill="#FFC107" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 0 1-2.2 3.32v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.1z"/>
          <path fill="#FF3D00" d="M6.306 14.6915c-.37.95-.96 1.79-1.72 2.44l2.63 2.04c1.59-1.47 2.78-3.68 2.78-6.48v-1.5H12.6v3h7.96z"/>
          <path fill="#4CAF50" d="M12.6 23c2.77 0 5.12-.93 6.93-2.53l-2.63-2.04c-.91.62-2.07 1-3.3 1-2.47 0-4.56-1.67-5.31-3.92H2.18v2.07C3.99 20.53 7.7 23 12.6 23z"/>
          <path fill="#1976D2" d="M12.6 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12.6 1 7.7 1 3.99 3.47 2.18 7.07l2.85 2.22c.87-2.6 3.3-4.53 6.16-4.53z"/>
        </svg>
        <span>{googleLoading ? 'Connecting…' : 'Continue with Google'}</span>
      </button>

      <p className="auth-toggle">
        {mode === 'login'
          ? "Don't have an account? "
          : 'Already have an account? '}
        <button
          type="button"
          className="auth-link"
          onClick={() => setMode(mode === 'login' ? 'signup' : 'login')}
        >
          {mode === 'login' ? 'Sign Up' : 'Sign In'}
        </button>
      </p>
    </div>
  );
}
