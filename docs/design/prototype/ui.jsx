// ui.jsx — shared atoms for the Сказочник onboarding prototype
const { useState, useEffect, useMemo, useRef } = React;

// ── Starfield ────────────────────────────────────────────────────
function Stars({ count = 46, seed = 1 }) {
  const stars = useMemo(() => {
    let s = seed * 9301 + 49297;
    const rnd = () => { s = (s * 9301 + 49297) % 233280; return s / 233280; };
    return Array.from({ length: count }, () => {
      const big = rnd() > 0.84;
      return {
        top: rnd() * 100,
        left: rnd() * 100,
        size: big ? 2.4 + rnd() * 1.4 : 1 + rnd() * 1.3,
        dur: 3 + rnd() * 4,
        delay: rnd() * 5,
        min: 0.12 + rnd() * 0.2,
        max: big ? 0.95 : 0.5 + rnd() * 0.4,
        gold: rnd() > 0.8,
      };
    });
  }, [count, seed]);
  return (
    <div className="stars">
      {stars.map((st, i) => (
        <span key={i} className="star" style={{
          top: st.top + '%', left: st.left + '%',
          width: st.size, height: st.size,
          background: st.gold ? '#f6d9a8' : '#fff',
          boxShadow: st.size > 2.4 ? `0 0 ${st.size * 2}px rgba(255,255,255,0.7)` : 'none',
          '--dur': st.dur + 's', '--delay': st.delay + 's',
          '--min': st.min, '--max': st.max,
        }} />
      ))}
    </div>
  );
}

// ── Night screen wrapper (bg + aurora + stars + content) ─────────
function NightScreen({ children, stars = 46, seed = 1, contentStyle = {}, scroll = false }) {
  return (
    <div className="screen">
      <div className="aurora a1" />
      <div className="aurora a2" />
      <div className="aurora a3" />
      <Stars count={stars} seed={seed} />
      <div className={"screen-content" + (scroll ? " scroll-y" : "")} style={contentStyle}>
        {children}
      </div>
    </div>
  );
}

// ── Icons ────────────────────────────────────────────────────────
function MoonIcon({ size = 96 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 100 100" fill="none">
      <defs>
        <radialGradient id="moonG" cx="38%" cy="34%" r="72%">
          <stop offset="0%" stopColor="#fff7e6" />
          <stop offset="55%" stopColor="#f6d9a8" />
          <stop offset="100%" stopColor="#e6a85c" />
        </radialGradient>
        <filter id="moonGlow" x="-60%" y="-60%" width="220%" height="220%">
          <feGaussianBlur stdDeviation="6" result="b" />
          <feMerge><feMergeNode in="b" /><feMergeNode in="SourceGraphic" /></feMerge>
        </filter>
      </defs>
      <circle cx="50" cy="50" r="34" fill="url(#moonG)" filter="url(#moonGlow)" />
      <circle cx="40" cy="40" r="5.5" fill="#e6a85c" opacity="0.35" />
      <circle cx="58" cy="56" r="7.5" fill="#d2873f" opacity="0.28" />
      <circle cx="52" cy="34" r="3.5" fill="#d2873f" opacity="0.25" />
    </svg>
  );
}

function Sparkle({ size = 16, color = 'var(--gold)', style = {} }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" style={style}>
      <path d="M12 0c.6 6.2 5.2 10.8 11.4 11.4l.6.6-.6.6C17.2 13.2 12.6 17.8 12 24c-.6-6.2-5.2-10.8-11.4-11.4L0 12l.6-.6C6.8 10.8 11.4 6.2 12 0z" fill={color} />
    </svg>
  );
}

function CheckMini({ size = 16, color = '#1a1330' }) {
  return (
    <svg width={size} height={size} viewBox="0 0 16 16" fill="none">
      <path d="M3 8.5l3 3 7-7.5" stroke={color} strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function Chevron({ dir = 'left', color = 'var(--text)', size = 16 }) {
  const d = dir === 'left' ? 'M11 2L4 9l7 7' : 'M5 2l7 7-7 7';
  return (
    <svg width={size} height={size * 1.1} viewBox="0 0 16 18" fill="none">
      <path d={d} stroke={color} strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function AppleLogo({ size = 18, color = 'var(--text)' }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill={color}>
      <path d="M17.05 12.5c-.03-2.5 2.04-3.7 2.13-3.76-1.16-1.7-2.97-1.93-3.62-1.96-1.54-.16-3 .9-3.78.9-.78 0-1.98-.88-3.25-.86-1.67.03-3.21.97-4.07 2.46-1.73 3-.44 7.45 1.25 9.88.83 1.19 1.81 2.53 3.1 2.48 1.24-.05 1.71-.8 3.21-.8 1.49 0 1.92.8 3.23.78 1.33-.03 2.18-1.21 3-2.41.94-1.38 1.33-2.72 1.35-2.79-.03-.01-2.6-1-2.63-3.95zM14.6 4.92c.69-.83 1.15-1.99 1.02-3.14-.99.04-2.19.66-2.9 1.49-.64.73-1.2 1.91-1.05 3.03 1.1.09 2.24-.56 2.93-1.38z" />
    </svg>
  );
}

// ── Progress header (back chevron + segmented progress) ──────────
function ProgressHeader({ step, total, onBack, showBack = true }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 14, paddingTop: 66, paddingBottom: 22 }}>
      <div className="icon-btn" onClick={showBack ? onBack : undefined}
        style={{ opacity: showBack ? 1 : 0, pointerEvents: showBack ? 'auto' : 'none' }}>
        <Chevron dir="left" />
      </div>
      <div className="prog-track">
        {Array.from({ length: total }, (_, i) => (
          <div key={i} className={"prog-seg" + (i < step ? " done" : i === step ? " active" : "")}>
            <span className="fill" />
          </div>
        ))}
      </div>
    </div>
  );
}

// ── Hero avatar — friendly child, built from simple shapes ───────
const SKIN_TONES = ['#f3d3b8', '#e7b894', '#cf9a6e', '#a87148', '#7a5333'];
const HAIR_COLORS = ['#3a2a1c', '#6b4423', '#a8743c', '#d9a441', '#e8e0d4', '#2a2730'];
const OUTFITS = ['#8B6EDB', '#4f9d8a', '#d98a6b', '#5c7bd9', '#c76aa8'];

function HeroAvatar({ skin = 0, hair = 0, hairStyle = 'short', outfit = 0, size = 132, float = false }) {
  const skinC = SKIN_TONES[skin] || SKIN_TONES[0];
  const hairC = HAIR_COLORS[hair] || HAIR_COLORS[0];
  const outfitC = OUTFITS[outfit] || OUTFITS[0];
  const u = size / 132; // unit scale
  const long = hairStyle === 'long';
  return (
    <div className={float ? "float" : ""} style={{ width: size, height: size, position: 'relative' }}>
      {/* soft glow */}
      <div style={{
        position: 'absolute', inset: -size * 0.18, borderRadius: '50%',
        background: 'radial-gradient(circle, rgba(184,167,255,0.32), transparent 68%)',
      }} />
      {/* body */}
      <div style={{
        position: 'absolute', left: '50%', bottom: 0, transform: 'translateX(-50%)',
        width: 86 * u, height: 56 * u,
        background: `linear-gradient(180deg, ${outfitC}, ${shade(outfitC, -18)})`,
        borderRadius: `${44 * u}px ${44 * u}px ${20 * u}px ${20 * u}px`,
        boxShadow: `inset 0 ${2 * u}px 0 rgba(255,255,255,0.18)`,
      }} />
      {/* long hair behind */}
      {long && (
        <div style={{
          position: 'absolute', left: '50%', top: 16 * u, transform: 'translateX(-50%)',
          width: 92 * u, height: 96 * u, background: hairC,
          borderRadius: `${46 * u}px ${46 * u}px ${36 * u}px ${36 * u}px`,
        }} />
      )}
      {/* head */}
      <div style={{
        position: 'absolute', left: '50%', top: 18 * u, transform: 'translateX(-50%)',
        width: 76 * u, height: 76 * u, borderRadius: '50%',
        background: `radial-gradient(circle at 38% 34%, ${shade(skinC, 12)}, ${skinC})`,
      }}>
        {/* eyes */}
        <span style={dot(11 * u, 26 * u, 30 * u)} />
        <span style={dot(11 * u, 26 * u, 46 * u)} />
        {/* cheeks */}
        <span style={{ ...cheek(u), left: 13 * u }} />
        <span style={{ ...cheek(u), right: 13 * u }} />
        {/* smile */}
        <span style={{
          position: 'absolute', top: 44 * u, left: '50%', transform: 'translateX(-50%)',
          width: 22 * u, height: 11 * u, borderRadius: `0 0 ${22 * u}px ${22 * u}px`,
          borderBottom: `${2.6 * u}px solid ${shade(skinC, -42)}`,
          borderLeft: `${2.6 * u}px solid transparent`, borderRight: `${2.6 * u}px solid transparent`,
        }} />
      </div>
      {/* hair cap (front) */}
      <div style={{
        position: 'absolute', left: '50%', top: 14 * u, transform: 'translateX(-50%)',
        width: 82 * u, height: long ? 40 * u : 46 * u,
        background: hairC,
        borderRadius: long
          ? `${42 * u}px ${42 * u}px ${10 * u}px ${10 * u}px`
          : `${42 * u}px ${42 * u}px ${30 * u}px ${30 * u}px`,
        clipPath: long ? 'none' : 'inset(0 0 42% 0)',
      }} />
    </div>
  );

  function dot(s, top, left) {
    return {
      position: 'absolute', width: s, height: s, borderRadius: '50%',
      background: '#3a2e28', top, left,
    };
  }
  function cheek(uu) {
    return {
      position: 'absolute', top: 40 * uu, width: 12 * uu, height: 8 * uu,
      borderRadius: '50%', background: 'rgba(214,110,120,0.32)',
    };
  }
}

// lighten/darken hex
function shade(hex, amt) {
  const n = parseInt(hex.slice(1), 16);
  let r = (n >> 16) + amt, g = ((n >> 8) & 255) + amt, b = (n & 255) + amt;
  r = Math.max(0, Math.min(255, r)); g = Math.max(0, Math.min(255, g)); b = Math.max(0, Math.min(255, b));
  return '#' + ((1 << 24) + (r << 16) + (g << 8) + b).toString(16).slice(1);
}

// ── Story book cover — composed night scene ──────────────────────
function BookCover({ avatar, title, kicker, height = 320 }) {
  return (
    <div style={{
      position: 'relative', width: '100%', height, borderRadius: 26, overflow: 'hidden',
      background: 'linear-gradient(180deg, #2a1d52 0%, #1c2752 52%, #14315c 100%)',
      boxShadow: '0 26px 60px -22px rgba(0,0,0,0.7), inset 0 0 0 1px rgba(246,235,221,0.1)',
    }}>
      <Stars count={28} seed={7} />
      {/* moon */}
      <div style={{ position: 'absolute', top: 26, right: 30 }}>
        <div className="float"><MoonIcon size={56} /></div>
      </div>
      {/* hills */}
      <div style={{ position: 'absolute', left: '-12%', bottom: -34, width: '70%', height: 120,
        background: 'linear-gradient(180deg,#243a6e,#1a2c54)', borderRadius: '50% 50% 0 0' }} />
      <div style={{ position: 'absolute', right: '-16%', bottom: -50, width: '80%', height: 140,
        background: 'linear-gradient(180deg,#1c2c5a,#16234a)', borderRadius: '50% 50% 0 0' }} />
      <div style={{ position: 'absolute', left: '50%', bottom: -20, transform: 'translateX(-50%)', width: '74%', height: 90,
        background: 'linear-gradient(180deg,#16213f,#10182f)', borderRadius: '50% 50% 0 0' }} />
      {/* hero standing on the front hill */}
      <div style={{ position: 'absolute', left: '50%', bottom: 30, transform: 'translateX(-50%)' }}>
        {avatar}
      </div>
      {/* text */}
      <div style={{ position: 'absolute', left: 22, right: 22, top: 22 }}>
        {kicker && <div className="kicker" style={{ color: 'var(--gold)', marginBottom: 8 }}>{kicker}</div>}
      </div>
    </div>
  );
}

Object.assign(window, {
  Stars, NightScreen, MoonIcon, Sparkle, CheckMini, Chevron, AppleLogo,
  ProgressHeader, HeroAvatar, BookCover,
  SKIN_TONES, HAIR_COLORS, OUTFITS, shade,
});
