// screens-profile.jsx — profile creation steps
const { useState: useStateP, useEffect: useEffectP, useRef: useRefP } = React;

const PROFILE_TOTAL = 5;

function ageWord(n) {
  const m10 = n % 10, m100 = n % 100;
  if (m10 === 1 && m100 !== 11) return 'год';
  if ([2, 3, 4].includes(m10) && !(m100 >= 12 && m100 <= 14)) return 'года';
  return 'лет';
}

// ── Reusable shell: header + scroll body + pinned footer ─────────
function ProfileShell({ step, onBack, children, footer, seed = 1 }) {
  return (
    <NightScreen stars={36} seed={seed}>
      <ProgressHeader step={step} total={PROFILE_TOTAL} onBack={onBack} />
      <div className="scroll-y" style={{ flex: 1, display: 'flex', flexDirection: 'column', minHeight: 0, margin: '0 -26px', padding: '0 26px' }}>
        {children}
      </div>
      <div style={{ paddingTop: 14, paddingBottom: 42 }}>{footer}</div>
    </NightScreen>
  );
}

function StepHead({ kicker, title, sub }) {
  return (
    <div className="anim-screen" style={{ marginBottom: 26 }}>
      {kicker && <div className="kicker" style={{ marginBottom: 12 }}>{kicker}</div>}
      <h2 className="title" style={{ fontSize: 28 }}>{title}</h2>
      {sub && <p className="body" style={{ marginTop: 10 }}>{sub}</p>}
    </div>
  );
}

// ── 1. Name ──────────────────────────────────────────────────────
function NameScreen({ data, setData, onNext, onBack, step }) {
  const ref = useRefP(null);
  useEffectP(() => { const t = setTimeout(() => ref.current && ref.current.focus(), 360); return () => clearTimeout(t); }, []);
  const valid = data.name.trim().length > 0;
  return (
    <ProfileShell step={step} onBack={onBack} seed={21}
      footer={<button className="btn btn-primary" disabled={!valid} onClick={onNext}>Продолжить</button>}>
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', justifyContent: 'center' }}>
        <div className="anim-screen" style={{ textAlign: 'center', marginBottom: 40 }}>
          <div className="kicker" style={{ marginBottom: 14 }}>Профиль ребёнка</div>
          <h2 className="display" style={{ fontSize: 32 }}>Как зовут<br />вашего малыша?</h2>
        </div>
        <input
          ref={ref}
          className="text-input anim-screen"
          style={{ animationDelay: '.1s' }}
          placeholder="Имя"
          value={data.name}
          maxLength={18}
          onChange={(e) => setData({ name: e.target.value })}
          onKeyDown={(e) => { if (e.key === 'Enter' && valid) onNext(); }}
        />
        <p className="caption anim-screen" style={{ animationDelay: '.18s', textAlign: 'center', marginTop: 18 }}>
          Имя будет звучать в каждой сказке
        </p>
      </div>
    </ProfileShell>
  );
}

// ── 2. Age ───────────────────────────────────────────────────────
function AgeScreen({ data, setData, onNext, onBack, step }) {
  const ages = Array.from({ length: 11 }, (_, i) => i + 2); // 2..12
  const name = data.name.trim() || 'малыш';
  return (
    <ProfileShell step={step} onBack={onBack} seed={22}
      footer={<button className="btn btn-primary" onClick={onNext}>Продолжить</button>}>
      <StepHead kicker="Профиль ребёнка" title={`Сколько лет — ${name}?`} sub="Подберём длину и сложность сказки под возраст." />
      <div className="anim-screen" style={{ animationDelay: '.06s', textAlign: 'center', marginTop: 6, marginBottom: 30 }}>
        <span style={{ fontFamily: 'var(--serif)', fontSize: 78, fontWeight: 500, color: 'var(--text)', lineHeight: 1 }}>{data.age}</span>
        <span style={{ fontFamily: 'var(--serif)', fontSize: 24, color: 'var(--gold)', marginLeft: 10 }}>{ageWord(data.age)}</span>
      </div>
      <div className="scroll-y" style={{ display: 'flex', gap: 12, padding: '6px 4px 10px', overflowX: 'auto' }}>
        {ages.map((a) => {
          const sel = data.age === a;
          return (
            <div key={a} onClick={() => setData({ age: a })} style={{
              flex: '0 0 auto', width: sel ? 72 : 58, height: sel ? 72 : 58,
              borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center',
              fontFamily: 'var(--serif)', fontSize: sel ? 30 : 23, fontWeight: 500,
              color: sel ? '#1a1330' : 'var(--text-2)',
              background: sel ? 'linear-gradient(135deg,#d9ccff,var(--accent))' : 'var(--card)',
              border: '1px solid ' + (sel ? 'transparent' : 'var(--border)'),
              boxShadow: sel ? '0 10px 26px -8px rgba(184,167,255,0.6)' : 'none',
              cursor: 'pointer', transition: 'all .22s ease', alignSelf: 'center',
            }}>{a}</div>
          );
        })}
      </div>
    </ProfileShell>
  );
}

// ── 3. Appearance — the "hero looks like your child" feature ─────
function SwatchRow({ label, colors, value, onPick, ring }) {
  return (
    <div style={{ marginBottom: 24 }}>
      <div className="caption" style={{ marginBottom: 12, color: 'var(--text-2)', fontWeight: 500, letterSpacing: '0.02em' }}>{label}</div>
      <div style={{ display: 'flex', gap: 14, flexWrap: 'wrap' }}>
        {colors.map((c, i) => (
          <div key={i} className={"swatch" + (value === i ? " selected" : "")} onClick={() => onPick(i)}
            style={{ width: 38, height: 38, background: c, border: ring ? '1px solid rgba(246,235,221,0.25)' : 'none' }} />
        ))}
      </div>
    </div>
  );
}

function AppearanceScreen({ data, setData, onNext, onBack, step }) {
  const name = data.name.trim() || 'герой';
  const genders = [['boy', 'Мальчик'], ['girl', 'Девочка'], ['none', 'Не указывать']];
  return (
    <ProfileShell step={step} onBack={onBack} seed={23}
      footer={<button className="btn btn-primary" onClick={onNext}>Продолжить</button>}>
      <StepHead kicker="Внешность героя" title="Сделаем героя похожим" sub={`Соберём портрет — и ${name} станет звездой собственных сказок.`} />

      {/* live preview */}
      <div className="anim-screen glass-card" style={{ animationDelay: '.05s', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '22px 0', marginBottom: 26 }}>
        <HeroAvatar size={150} skin={data.skin} hair={data.hair} hairStyle={data.hairStyle} outfit={data.outfit} float />
      </div>

      {/* gender */}
      <div style={{ marginBottom: 24 }}>
        <div className="caption" style={{ marginBottom: 12, fontWeight: 500 }}>Кто наш герой?</div>
        <div style={{ display: 'flex', gap: 9 }}>
          {genders.map(([v, l]) => {
            const sel = data.gender === v;
            return (
              <div key={v} onClick={() => setData({ gender: v })} style={{
                flex: 1, textAlign: 'center', padding: '12px 4px', borderRadius: 14, cursor: 'pointer',
                fontSize: 14.5, fontWeight: 500, transition: 'all .2s ease',
                color: sel ? 'var(--text)' : 'var(--text-2)',
                background: sel ? 'var(--accent-soft)' : 'var(--card)',
                border: '1px solid ' + (sel ? 'var(--accent)' : 'var(--border)'),
              }}>{l}</div>
            );
          })}
        </div>
      </div>

      <SwatchRow label="Оттенок кожи" colors={SKIN_TONES} value={data.skin} onPick={(i) => setData({ skin: i })} ring />
      <SwatchRow label="Цвет волос" colors={HAIR_COLORS} value={data.hair} onPick={(i) => setData({ hair: i })} ring />

      {/* hair length */}
      <div style={{ marginBottom: 24 }}>
        <div className="caption" style={{ marginBottom: 12, fontWeight: 500 }}>Длина волос</div>
        <div style={{ display: 'flex', gap: 9 }}>
          {[['short', 'Короткие'], ['long', 'Длинные']].map(([v, l]) => {
            const sel = data.hairStyle === v;
            return (
              <div key={v} onClick={() => setData({ hairStyle: v })} style={{
                flex: 1, textAlign: 'center', padding: '12px 4px', borderRadius: 14, cursor: 'pointer',
                fontSize: 14.5, fontWeight: 500, transition: 'all .2s ease',
                color: sel ? 'var(--text)' : 'var(--text-2)',
                background: sel ? 'var(--accent-soft)' : 'var(--card)',
                border: '1px solid ' + (sel ? 'var(--accent)' : 'var(--border)'),
              }}>{l}</div>
            );
          })}
        </div>
      </div>

      <SwatchRow label="Цвет одежды" colors={OUTFITS} value={data.outfit} onPick={(i) => setData({ outfit: i })} />

      {/* photo alternative */}
      <div className="glass-card" style={{ display: 'flex', alignItems: 'center', gap: 14, padding: 14, marginBottom: 6 }}>
        <image-slot id="child-photo" shape="circle" style={{ width: 56, height: 56, flexShrink: 0 }} placeholder="Фото"></image-slot>
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 15, fontWeight: 600, color: 'var(--text)', marginBottom: 3 }}>Или загрузите фото</div>
          <div className="caption">Нарисуем героя похожим на вашего ребёнка</div>
        </div>
      </div>
    </ProfileShell>
  );
}

// ── 4. Interests ─────────────────────────────────────────────────
const INTERESTS = [
  'Динозавры', 'Космос', 'Животные', 'Лошади', 'Машинки', 'Море',
  'Принцессы', 'Роботы', 'Волшебство', 'Пираты', 'Феи', 'Рыцари',
  'Природа', 'Музыка', 'Спорт', 'Драконы',
];

function InterestsScreen({ data, setData, onNext, onBack, step }) {
  const name = data.name.trim() || 'малыш';
  const toggle = (it) => {
    const has = data.interests.includes(it);
    setData({ interests: has ? data.interests.filter((x) => x !== it) : [...data.interests, it] });
  };
  const count = data.interests.length;
  return (
    <ProfileShell step={step} onBack={onBack} seed={24}
      footer={
        <button className="btn btn-primary" disabled={count === 0} onClick={onNext}>
          {count === 0 ? 'Выберите хотя бы одно' : 'Продолжить'}
        </button>
      }>
      <StepHead kicker="Увлечения" title={`Что любит ${name}?`} sub="Эти темы будут вплетаться в сюжеты сказок." />
      <div className="anim-screen" style={{ display: 'flex', flexWrap: 'wrap', gap: 11, paddingBottom: 8, animationDelay: '.05s' }}>
        {INTERESTS.map((it) => {
          const sel = data.interests.includes(it);
          return (
            <div key={it} className={"chip" + (sel ? " selected" : "")} onClick={() => toggle(it)}>
              {sel && <Sparkle size={13} color="var(--accent)" />}
              {it}
            </div>
          );
        })}
      </div>
    </ProfileShell>
  );
}

// ── 5. World / genre ─────────────────────────────────────────────
const WORLDS = [
  { id: 'forest', name: 'Волшебный лес', g: 'linear-gradient(160deg,#1d3a2e,#16433a)' },
  { id: 'ocean', name: 'Подводный мир', g: 'linear-gradient(160deg,#163a5c,#1a5a6e)' },
  { id: 'space', name: 'Далёкий космос', g: 'linear-gradient(160deg,#241b52,#3a2150)' },
  { id: 'castle', name: 'Замки и рыцари', g: 'linear-gradient(160deg,#3a2d22,#5c3f2f)' },
  { id: 'clouds', name: 'Облачное королевство', g: 'linear-gradient(160deg,#2a3560,#46538c)' },
  { id: 'jungle', name: 'Джунгли', g: 'linear-gradient(160deg,#274a22,#3f5c2f)' },
];

function WorldScene({ g }) {
  return (
    <div style={{ position: 'absolute', inset: 0, background: g, overflow: 'hidden' }}>
      <Stars count={10} seed={3} />
      <div style={{ position: 'absolute', right: 12, top: 12 }}><MoonIcon size={24} /></div>
      <div style={{ position: 'absolute', left: '-14%', bottom: -22, width: '70%', height: 50, background: 'rgba(0,0,0,0.28)', borderRadius: '50% 50% 0 0' }} />
      <div style={{ position: 'absolute', right: '-12%', bottom: -28, width: '70%', height: 56, background: 'rgba(0,0,0,0.2)', borderRadius: '50% 50% 0 0' }} />
    </div>
  );
}

function WorldScreen({ data, setData, onNext, onBack, step }) {
  return (
    <ProfileShell step={step} onBack={onBack} seed={25}
      footer={<button className="btn btn-primary" disabled={!data.world} onClick={onNext}>Создать первую сказку</button>}>
      <StepHead kicker="Любимый мир" title="Где начнётся история?" sub="Выберите мир — в нём будут происходить приключения." />
      <div className="anim-screen" style={{ animationDelay: '.05s', display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 13, paddingBottom: 8 }}>
        {WORLDS.map((w) => {
          const sel = data.world === w.id;
          return (
            <div key={w.id} className={"tile" + (sel ? " selected" : "")} onClick={() => setData({ world: w.id })}
              style={{ height: 116, display: 'flex', flexDirection: 'column', justifyContent: 'flex-end' }}>
              <WorldScene g={w.g} />
              <div style={{ position: 'relative', padding: '0 14px 13px', zIndex: 2 }}>
                <span style={{ fontFamily: 'var(--serif)', fontSize: 16.5, fontWeight: 500, color: '#fff', textShadow: '0 1px 6px rgba(0,0,0,0.6)' }}>{w.name}</span>
              </div>
              {sel && (
                <div style={{ position: 'absolute', top: 10, left: 10, zIndex: 3, width: 24, height: 24, borderRadius: '50%', background: 'var(--accent)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                  <CheckMini size={14} />
                </div>
              )}
            </div>
          );
        })}
      </div>
    </ProfileShell>
  );
}

Object.assign(window, {
  PROFILE_TOTAL, ageWord, ProfileShell, StepHead,
  NameScreen, AgeScreen, AppearanceScreen, InterestsScreen, WorldScreen,
  INTERESTS, WORLDS, WorldScene,
});
