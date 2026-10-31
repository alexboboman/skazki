// screens-intro.jsx — Welcome + value-proposition carousel
const { useState: useStateI } = React;

// ── Welcome / splash ─────────────────────────────────────────────
function WelcomeScreen({ onStart }) {
  return (
    <NightScreen stars={60} seed={3}>
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', textAlign: 'center', paddingBottom: 8 }}>
        <div className="float rise" style={{ marginBottom: 30, position: 'relative' }}>
          <MoonIcon size={118} />
          <Sparkle size={20} style={{ position: 'absolute', top: 6, left: -10 }} />
          <Sparkle size={13} color="#fff" style={{ position: 'absolute', bottom: 14, right: -6 }} />
        </div>
        <div className="kicker rise" style={{ animationDelay: '.08s', marginBottom: 16 }}>Сказки на ночь</div>
        <h1 className="display rise" style={{ animationDelay: '.14s', fontSize: 46, marginBottom: 18 }}>Сказочник</h1>
        <p className="body rise" style={{ animationDelay: '.2s', maxWidth: 290, fontSize: 17.5 }}>
          Каждый вечер — новая добрая история, где главный герой похож на вашего ребёнка.
        </p>
      </div>
      <div className="rise" style={{ animationDelay: '.28s', paddingBottom: 46, display: 'flex', flexDirection: 'column', gap: 6 }}>
        <button className="btn btn-primary" onClick={onStart}>Начать</button>
        <button className="btn btn-ghost" onClick={onStart}>
          <AppleLogo size={17} color="var(--text-2)" />
          Уже есть аккаунт? Войти с Apple
        </button>
      </div>
    </NightScreen>
  );
}

// ── Value slides ─────────────────────────────────────────────────
const VALUE_SLIDES = [
  {
    kicker: 'Персонализация',
    title: 'Герой сказки — ваш ребёнок',
    body: 'Имя, внешность и любимые увлечения малыша оживают в каждой истории.',
    scene: 'hero',
  },
  {
    kicker: 'Спокойствие',
    title: 'Мягко и безопасно',
    body: 'Только добрые сюжеты — без страшного и тревожного. Тёплый ритуал перед сном.',
    scene: 'safe',
  },
  {
    kicker: 'Ваша библиотека',
    title: 'Истории остаются с вами',
    body: 'Сказки с иллюстрациями сохраняются и доступны для чтения даже без интернета.',
    scene: 'library',
  },
];

function ValueScene({ kind }) {
  if (kind === 'hero') {
    return (
      <div style={{ position: 'relative', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <div style={{ position: 'absolute', width: 210, height: 210, borderRadius: '50%',
          border: '1px dashed rgba(184,167,255,0.35)', animation: 'spinSlow 28s linear infinite' }} />
        <div style={{ position: 'absolute', width: 250, height: 250, borderRadius: '50%',
          background: 'radial-gradient(circle, rgba(184,167,255,0.16), transparent 65%)' }} />
        <Sparkle size={20} style={{ position: 'absolute', top: 8, right: 40 }} />
        <Sparkle size={14} color="#fff" style={{ position: 'absolute', bottom: 24, left: 36 }} />
        <Sparkle size={16} style={{ position: 'absolute', top: 60, left: 18 }} />
        <HeroAvatar size={150} skin={1} hair={2} hairStyle="short" outfit={0} float />
      </div>
    );
  }
  if (kind === 'safe') {
    return (
      <div style={{ position: 'relative', width: 200, height: 200, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <div className="float" style={{
          width: 150, height: 168,
          background: 'linear-gradient(180deg, rgba(184,167,255,0.18), rgba(139,110,219,0.06))',
          border: '1px solid var(--border-strong)',
          borderRadius: '50% 50% 46% 46% / 42% 42% 60% 60%',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          boxShadow: 'inset 0 2px 0 rgba(255,255,255,0.14)',
        }}>
          <MoonIcon size={74} />
        </div>
        <Sparkle size={16} style={{ position: 'absolute', top: 18, left: 26 }} />
        <Sparkle size={13} color="#fff" style={{ position: 'absolute', bottom: 30, right: 28 }} />
      </div>
    );
  }
  // library — fanned story cards
  return (
    <div style={{ position: 'relative', width: 220, height: 200 }}>
      {[
        { rot: -13, x: -54, c: 'linear-gradient(160deg,#2a1d52,#14315c)', z: 1, d: '.05s' },
        { rot: 9, x: 50, c: 'linear-gradient(160deg,#3a2150,#5c2f4a)', z: 2, d: '.12s' },
        { rot: -1, x: 0, c: 'linear-gradient(160deg,#1c2752,#14315c)', z: 3, d: '0s' },
      ].map((card, i) => (
        <div key={i} className="rise" style={{
          position: 'absolute', left: '50%', top: '50%',
          transform: `translate(-50%,-50%) translateX(${card.x}px) rotate(${card.rot}deg)`,
          width: 110, height: 150, borderRadius: 16, background: card.c, zIndex: card.z,
          animationDelay: card.d,
          boxShadow: '0 16px 30px -14px rgba(0,0,0,0.7), inset 0 0 0 1px rgba(246,235,221,0.1)',
          overflow: 'hidden',
        }}>
          <Stars count={10} seed={i + 2} />
          <div style={{ position: 'absolute', bottom: 12, left: 12, right: 12, height: 5, borderRadius: 3, background: 'rgba(246,235,221,0.4)' }} />
          <div style={{ position: 'absolute', bottom: 22, left: 12, width: '60%', height: 5, borderRadius: 3, background: 'rgba(246,235,221,0.22)' }} />
          {card.z === 3 && <div style={{ position: 'absolute', top: 14, right: 12 }}><MoonIcon size={26} /></div>}
        </div>
      ))}
    </div>
  );
}

function ValueScreen({ onDone, onBack }) {
  const [i, setI] = useStateI(0);
  const slide = VALUE_SLIDES[i];
  const last = i === VALUE_SLIDES.length - 1;
  const back = () => { i === 0 ? onBack() : setI(i - 1); };
  const next = () => { last ? onDone() : setI(i + 1); };
  return (
    <NightScreen stars={42} seed={i + 11}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 14, paddingTop: 66, paddingBottom: 0 }}>
        <div className="icon-btn" onClick={back}><Chevron dir="left" /></div>
        <button className="btn btn-ghost" onClick={onDone} style={{ marginLeft: 'auto', width: 'auto', height: 42, padding: '0 6px', fontSize: 15 }}>Пропустить</button>
      </div>

      <div key={i} className="anim-screen" style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', textAlign: 'center' }}>
        <div style={{ height: 240, display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: 24 }}>
          <ValueScene kind={slide.scene} />
        </div>
        <div className="kicker" style={{ marginBottom: 14 }}>{slide.kicker}</div>
        <h2 className="display" style={{ marginBottom: 16, maxWidth: 300 }}>{slide.title}</h2>
        <p className="body" style={{ maxWidth: 296 }}>{slide.body}</p>
      </div>

      <div style={{ paddingBottom: 46 }}>
        <div className="dots" style={{ marginBottom: 24 }}>
          {VALUE_SLIDES.map((_, k) => <span key={k} className={"dot" + (k === i ? " active" : "")} />)}
        </div>
        <button className="btn btn-primary" onClick={next}>{last ? 'Создать профиль' : 'Далее'}</button>
      </div>
    </NightScreen>
  );
}

Object.assign(window, { WelcomeScreen, ValueScreen, VALUE_SLIDES });
