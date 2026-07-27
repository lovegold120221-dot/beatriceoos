/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
*/
import { useEffect, useState } from 'react';
import './SplashScreen.css';

interface SplashScreenProps {
  onReady: () => void;
}

const LOGO_URL = '/logo.png';

export default function SplashScreen({ onReady }: SplashScreenProps) {
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    // Stagger entrance animation
    const timer = setTimeout(() => {
      setVisible(true);
      onReady();
     }, 100);
    return () => clearTimeout(timer);
   }, [onReady]);

  const handleSkip = () => {
    onReady();
   };

  return (
       <div className={`splash-screen ${visible ? 'visible' : ''}`}>
         <div className="splash-content">
           <img
            src={LOGO_URL}
            alt="Beatrice AI Logo"
            className="splash-logo"
             />
           <h1 className="splash-title">Beatrice</h1>
           <p className="splash-subtitle">Powered by Eburon AI</p>
         </div>
         <button
          className="splash-skip-btn"
          onClick={handleSkip}
           >
            Continue
           </button>
         </div>
       );
     }
