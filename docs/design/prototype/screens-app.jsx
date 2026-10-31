// screens-app.jsx — main app after onboarding: tab bar, home, library, kids
const { useState: useStateM } = React;

const STORIES = [
  { id: 's1', title: 'Лиса, которая берегла звёзды', world: 'forest', kid: 'k1', min: 8, audio: true, fav: true, progress: 0.62, day: 'Вчера' },
  { id: 's2', title: 'Кит и потерянная песня', world: 'ocean', kid: 'k1', min: 10, audio: true, fav: false, day: '2 дня назад' },
  { id: 's3', title: 'Сонная ракета', world: 'space', kid: 'k2', min: 5, audio: false, fav: true, day: '3 дня назад' },
  { id: 's4', title: 'Рыцарь тёплого пледа', world: 'castle', kid: 'k1', min: 12, audio: true, fav: false, day: 'На неделе' },
  { id: 's5', title: 'Облако, которое не умело плакать', world: 'clouds', kid: 'k2', min: 7, audio: true, fav: false, day: 'На неделе' },
  { id: 's6', title: 'Тихая тропа сквозь джунгли', world: 'jungle', kid: 'k1', min: 9, audio: false, fav: true, day: 'В октябре' },
];
const worldOf = (id) => WORLDS.find((w) => w.id === id) || WORLDS[0];

// ── Icons ──
function Ico({ d, size = 22, color = 'currentColor', sw = 1.8, fill = 'none' }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill={fill} stroke={color} strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round">
      {[].concat(d).map((p, i) => <path key={i} d={p} />)}
    </svg>
  );
}
const IC = {
  home: ['M3.5 10.5 12 4l8.5 6.5', 'M5.5 9v10.5h13V9'],
  book: ['M4 5.5c2.5-1.2 5.5-1.2 8 .5v13c-2.5-1.7-5.5-1.7-8-.5z', 'M20 5.5c-2.5-1.2-5.5-1.2-8 .5v13c2.5-1.7 5.5-1.7 8-.5z'],
  kids: ['M9 11a3.2 3.2 0 1 0 0-6.4A3.2 3.2 0 0 0 9 11z', 'M3.5 19.5c.6-3.3 2.8-5.3 5.5-5.3s4.9 2 5.5 5.3', 'M16 10.5a2.6 2.6 0 1 0 0-5.2', 'M17.5 14.4c1.7.6 2.7 2.4 3 5.1'],
  plus: ['M12 5v14', 'M5 12h14'],
  play: 'M8 5.5v13l10.5-6.5z',
  head: ['M4 15v-3a8 8 0 0 1 16 0v3', 'M4 15.5a2 2 0 0 1 2-2h1v6H6a2 2 0 0 1-2-2z', 'M20 15.5a2 2 0 0 0-2-2h-1v6h1a2 2 0 0 0 2-2z'],
  read: ['M4 6h16', 'M4 11h16', 'M4 16h10'],
  heart: 'M12 19.5s-7.5-4.4-7.5-10A4.2 4.2 0 0 1 12 7a4.2 4.2 0 0 1 7.5 2.5c0 5.6-7.5 10-7.5 10z',
  search: ['M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14z', 'M20 20l-4-4'],
  edit: ['M4 20h4L19 9l-4-4L4 16z'],
  chevD: 'M6 9l6 6 6-6',
  moon: 'M19.5 14.5A8 8 0 0 1 9.5 4.5a8 8 0 1 0 10 10z',
};

// ── Tab bar ──
function TabBar({ tab, onTab }) {
  const items = [
    { id: 'home', label: 'Сегодня', icon: IC.home },
    { id: 'library', label: 'Сказки', icon: IC.book },
    { id: 'create', label: 'Сочинить', icon: IC.plus, center: true },
    { id: 'kids', label: 'Дети', icon: IC.kids },
  ];
  return (
    <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, zIndex: 20, padding: '10px 18px 30px',
      background: 'linear-gradient(180deg, rgba(16,12,31,0) 0%, rgba(16,12,31,0.92) 34%, #100c1f 100%)' }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-around', height: 64, borderRadius: 32,
        background: 'rgba(34,30,58,0.78)', border: '1px solid var(--border)', backdropFilter: 'blur(18px)', WebkitBackdropFilter: 'blur(18px)' }}>
        {items.map((it) => {
          const on = tab === it.id;
          if (it.center) return (
            <div key={it.id} onClick={() => onTab(it.id)} style={{ cursor: 'pointer', width: 50, height: 50, borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center',
              background: 'linear-gradient(135deg,#f7d9a8,var(--gold) 60%,#d2873f)', boxShadow: '0 8px 22px -6px rgba(230,168,92,0.6)' }}>
              <Ico d={it.icon} color="#2b1c0c" sw={2.4} />
            </div>
          );
          return (
            <div key={it.id} onClick={() => onTab(it.id)} style={{ cursor: 'pointer', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3, width: 64,
              color: on ? 'var(--text)' : 'var(--text-3)', transition: 'color .2s' }}>
              <Ico d={it.icon} color={on ? 'var(--accent)' : 'currentColor'} />
              <span style={{ fontSize: 11.5, fontWeight: 500 }}>{it.label}</span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function AppShell({ tab, onTab, seed = 41, children }) {
  return (
    <div className="screen">
      <div className="aurora a1" /><div className="aurora a2" />
      <Stars count={34} seed={seed} />
      <div className="screen-content scroll-y" style={{ paddingTop: 62, paddingBottom: 120 }}>
        <div className="anim-screen">{children}</div>
      </div>
      <TabBar tab={tab} onTab={onTab} />
    </div>
  );
}

// small world-scene thumbnail for a story
function StoryThumb({ story, h = 120, radius = 18, kid }) {
  return (
    <div style={{ position: 'relative', height: h, borderRadius: radius, overflow: 'hidden', boxShadow: 'inset 0 0 0 1px rgba(246,235,221,0.08)' }}>
      <WorldScene g={worldOf(story.world).g} />
      {kid && <div style={{ position: 'absolute', left: '50%', bottom: 4, transform: 'translateX(-50%)' }}>
        <HeroAvatar {...kid} size={h * 0.46} />
      </div>}
    </div>
  );
}

function ModeBadge({ audio }) {
  return (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5, fontSize: 12.5, color: 'var(--text-3)', whiteSpace: 'nowrap' }}>
      <Ico d={audio ? IC.head : IC.read} size={14} sw={2} />{audio ? 'Аудио' : 'Текст'}
    </span>
  );
}

// ── Kid switcher pill ──
function KidSwitch({ kids, activeId, onPick }) {
  const [open, setOpen] = useStateM(false);
  const kid = kids.find((k) => k.id === activeId) || kids[0];
  return (
    <div style={{ position: 'relative' }}>
      <div onClick={() => setOpen(!open)} style={{ cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 8, padding: '4px 12px 4px 4px',
        borderRadius: 999, background: 'var(--card)', border: '1px solid var(--border)' }}>
        <div style={{ width: 34, height: 34, borderRadius: '50%', overflow: 'hidden', background: 'var(--accent-soft)', display: 'flex', alignItems: 'flex-end', justifyContent: 'center' }}>
          <HeroAvatar {...kid} size={34} />
        </div>
        <span style={{ fontSize: 15, fontWeight: 600, color: 'var(--text)' }}>{kid.name}</span>
        <Ico d={IC.chevD} size={16} color="var(--text-3)" sw={2.2} />
      </div>
      {open && (
        <div style={{ position: 'absolute', right: 0, top: 50, zIndex: 30, minWidth: 190, padding: 6, borderRadius: 20,
          background: 'var(--card-solid)', border: '1px solid var(--border-strong)', boxShadow: '0 20px 40px -12px rgba(0,0,0,0.7)' }}>
          {kids.map((k) => (
            <div key={k.id} onClick={() => { onPick(k.id); setOpen(false); }} style={{ cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 10, padding: '8px 10px', borderRadius: 14,
              background: k.id === kid.id ? 'var(--accent-soft)' : 'transparent' }}>
              <div style={{ width: 32, height: 32, borderRadius: '50%', overflow: 'hidden', display: 'flex', alignItems: 'flex-end', justifyContent: 'center', background: 'rgba(255,255,255,0.05)' }}>
                <HeroAvatar {...k} size={32} />
              </div>
              <span style={{ fontSize: 15, color: 'var(--text)', flex: 1 }}>{k.name}</span>
              {k.id === kid.id && <CheckMini size={14} color="var(--accent)" />}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

// ── Home ──
function HomeScreen({ kids, activeId, setActive, onTab, onOpen, onCreate }) {
  const kid = kids.find((k) => k.id === activeId) || kids[0];
  const mine = STORIES.filter((s) => s.kid === kid.id);
  const tonight = mine[0] || STORIES[0];
  const recent = mine.slice(1).concat(STORIES.filter((s) => s.kid !== kid.id)).slice(0, 4);
  return (
    <AppShell tab="home" onTab={onTab} seed={41}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 22 }}>
        <div className="caption" style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <Ico d={IC.moon} size={15} color="var(--gold)" sw={2} />Добрый вечер
        </div>
        <KidSwitch kids={kids} activeId={kid.id} onPick={setActive} />
      </div>
      <h1 className="display" style={{ fontSize: 30, marginBottom: 20 }}>Что почитаем сегодня?</h1>

      {tonight.progress ? (
        <div className="glass-card" style={{ padding: 14, marginBottom: 14, display: 'flex', gap: 14, alignItems: 'center', cursor: 'pointer' }} onClick={() => onOpen(tonight, tonight.audio ? 'listen' : 'read')}>
          <div style={{ width: 64, flexShrink: 0 }}><StoryThumb story={tonight} h={64} radius={14} /></div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div className="kicker" style={{ fontSize: 11, color: 'var(--gold)', marginBottom: 4 }}>Продолжить</div>
            <div style={{ fontFamily: 'var(--serif)', fontSize: 16.5, color: 'var(--text)', lineHeight: 1.25, marginBottom: 8 }}>{tonight.title}</div>
            <div style={{ height: 3, borderRadius: 9, background: 'rgba(246,235,221,0.12)' }}>
              <div style={{ width: tonight.progress * 100 + '%', height: '100%', borderRadius: 9, background: 'linear-gradient(90deg,var(--accent),var(--gold))' }} />
            </div>
          </div>
          <div style={{ width: 44, height: 44, borderRadius: '50%', background: 'var(--accent)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
            <Ico d={IC.play} size={18} fill="#1a1330" color="#1a1330" sw={1.5} />
          </div>
        </div>
      ) : null}

      <div className="glass-card" style={{ padding: 8, marginBottom: 28 }}>
        <div style={{ position: 'relative', height: 210, borderRadius: 20, overflow: 'hidden' }}>
          <BookCover height={210} avatar={<HeroAvatar {...kid} size={86} float />} kicker="На сегодня" />
        </div>
        <div style={{ padding: '16px 10px 6px' }}>
          <div style={{ fontFamily: 'var(--serif)', fontSize: 21, color: 'var(--text)', lineHeight: 1.25, marginBottom: 6, textWrap: 'balance' }}>
            Сочинить новую историю на сегодня
          </div>
          <p className="caption" style={{ marginBottom: 16 }}>Учтём любимые темы и то, что было в прошлых сказках.</p>
          <button className="btn btn-primary" style={{ height: 52 }} onClick={onCreate}>
            <Sparkle size={15} color="#1a1330" />Сочинить сказку
          </button>
        </div>
      </div>

      <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginBottom: 14 }}>
        <h2 className="title" style={{ fontSize: 21 }}>Недавние</h2>
        <span onClick={() => onTab('library')} style={{ cursor: 'pointer', fontSize: 14, color: 'var(--accent)', fontWeight: 500 }}>Все сказки</span>
      </div>
      <div className="scroll-y" style={{ display: 'flex', gap: 12, overflowX: 'auto', overflowY: 'hidden', margin: '0 -26px', padding: '0 26px 4px' }}>
        {recent.map((s) => (
          <div key={s.id} onClick={() => onOpen(s, 'read')} style={{ cursor: 'pointer', width: 150, flexShrink: 0 }}>
            <StoryThumb story={s} h={110} kid={kids.find((k) => k.id === s.kid)} />
            <div style={{ fontFamily: 'var(--serif)', fontSize: 15, color: 'var(--text)', lineHeight: 1.3, margin: '9px 0 4px' }}>{s.title}</div>
            <div className="caption" style={{ fontSize: 12.5 }}>{s.min} мин · {s.day}</div>
          </div>
        ))}
      </div>
    </AppShell>
  );
}

// ── Library ──
function LibraryScreen({ kids, onTab, onOpen }) {
  const [filter, setFilter] = useStateM('all');
  const [kidF, setKidF] = useStateM('any');
  const filters = [['all', 'Все'], ['fav', 'Любимые'], ['audio', 'С озвучкой']];
  const list = STORIES.filter((s) => (filter === 'fav' ? s.fav : filter === 'audio' ? s.audio : true) && (kidF === 'any' || s.kid === kidF));
  return (
    <AppShell tab="library" onTab={onTab} seed={52}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 18 }}>
        <h1 className="display" style={{ fontSize: 30 }}>Сказки</h1>
        <div className="icon-btn"><Ico d={IC.search} size={19} color="var(--text-2)" /></div>
      </div>
      <div style={{ display: 'flex', padding: 4, borderRadius: 999, background: 'var(--card)', border: '1px solid var(--border)', marginBottom: 14 }}>
        {filters.map(([id, l]) => (
          <div key={id} onClick={() => setFilter(id)} style={{ cursor: 'pointer', flex: 1, textAlign: 'center', padding: '9px 0', borderRadius: 999, fontSize: 14.5, fontWeight: 500,
            color: filter === id ? '#1a1330' : 'var(--text-2)', background: filter === id ? 'var(--accent)' : 'transparent', transition: 'all .2s' }}>{l}</div>
        ))}
      </div>
      <div style={{ display: 'flex', gap: 8, marginBottom: 20, flexWrap: 'wrap' }}>
        {[{ id: 'any', name: 'Все дети' }].concat(kids).map((k) => (
          <div key={k.id} className={'chip' + (kidF === k.id ? ' selected' : '')} onClick={() => setKidF(k.id)} style={{ padding: k.skin != null ? '5px 14px 5px 5px' : '9px 14px', fontSize: 14 }}>
            {k.skin != null && <span style={{ width: 26, height: 26, borderRadius: '50%', overflow: 'hidden', display: 'flex', alignItems: 'flex-end', justifyContent: 'center', background: 'rgba(255,255,255,0.06)' }}><HeroAvatar {...k} size={26} /></span>}
            {k.name}
          </div>
        ))}
      </div>
      {list.length === 0 ? (
        <div style={{ textAlign: 'center', padding: '50px 20px' }}>
          <div style={{ display: 'flex', justifyContent: 'center', marginBottom: 12 }}><MoonIcon size={64} /></div>
          <p className="body">Здесь пока пусто.</p>
        </div>
      ) : (
        <div style={{ display: 'grid', gridTemplateColumns: 'minmax(0,1fr) minmax(0,1fr)', gap: '20px 12px' }}>
          {list.map((s) => (
            <div key={s.id} onClick={() => onOpen(s, 'read')} style={{ cursor: 'pointer', position: 'relative' }}>
              <StoryThumb story={s} h={150} kid={kids.find((k) => k.id === s.kid)} />
              {s.fav && <div style={{ position: 'absolute', top: 10, right: 10, color: 'var(--gold)' }}><Ico d={IC.heart} size={18} fill="var(--gold)" color="var(--gold)" /></div>}
              <div style={{ fontFamily: 'var(--serif)', fontSize: 15.5, color: 'var(--text)', lineHeight: 1.3, margin: '10px 0 5px' }}>{s.title}</div>
              <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
                <span className="caption" style={{ fontSize: 12.5, whiteSpace: 'nowrap' }}>{s.min} мин</span><ModeBadge audio={s.audio} />
              </div>
            </div>
          ))}
        </div>
      )}
    </AppShell>
  );
}

// ── Kids profiles ──
function KidsScreen({ kids, activeId, setActive, onTab, onAdd }) {
  return (
    <AppShell tab="kids" onTab={onTab} seed={63}>
      <h1 className="display" style={{ fontSize: 30, marginBottom: 6 }}>Дети</h1>
      <p className="caption" style={{ marginBottom: 22 }}>У каждого — свой герой, темы и полка сказок.</p>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
        {kids.map((k) => {
          const on = k.id === activeId;
          const n = STORIES.filter((s) => s.kid === k.id).length;
          return (
            <div key={k.id} className="glass-card" onClick={() => setActive(k.id)} style={{ cursor: 'pointer', padding: 16,
              borderColor: on ? 'var(--accent)' : 'var(--border)', boxShadow: on ? '0 0 0 1px var(--accent) inset' : 'none' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
                <div style={{ width: 72, height: 72, borderRadius: 22, overflow: 'hidden', flexShrink: 0, background: 'linear-gradient(180deg,#2a1d52,#1c2752)', display: 'flex', alignItems: 'flex-end', justifyContent: 'center' }}>
                  <HeroAvatar {...k} size={64} />
                </div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontFamily: 'var(--serif)', fontSize: 21, color: 'var(--text)' }}>{k.name}</div>
                  <div className="caption">{k.age} {ageWord(k.age)} · {n} {n === 1 ? 'сказка' : n < 5 ? 'сказки' : 'сказок'}</div>
                </div>
                <div className="icon-btn" style={{ width: 38, height: 38 }}><Ico d={IC.edit} size={17} color="var(--text-2)" /></div>
              </div>
              {k.interests && k.interests.length > 0 && (
                <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginTop: 14 }}>
                  {k.interests.slice(0, 4).map((i) => (
                    <span key={i} style={{ fontSize: 12.5, color: 'var(--text-2)', padding: '5px 10px', borderRadius: 999, background: 'rgba(246,235,221,0.06)' }}>{i}</span>
                  ))}
                  <span style={{ fontSize: 12.5, color: 'var(--text-3)', padding: '5px 4px' }}>· {worldOf(k.world).name}</span>
                </div>
              )}
              {on && <div className="kicker" style={{ fontSize: 10.5, marginTop: 14, color: 'var(--accent)' }}>Сейчас выбран</div>}
            </div>
          );
        })}
        <div onClick={onAdd} style={{ cursor: 'pointer', borderRadius: 26, border: '1.5px dashed var(--border-strong)', padding: '22px 16px', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 10, color: 'var(--text-2)' }}>
          <Ico d={IC.plus} size={20} color="var(--accent)" sw={2.2} />
          <span style={{ fontSize: 15.5, fontWeight: 500 }}>Добавить ребёнка</span>
        </div>
      </div>
    </AppShell>
  );
}

Object.assign(window, { STORIES, worldOf, Ico, IC, TabBar, AppShell, StoryThumb, ModeBadge, KidSwitch, HomeScreen, LibraryScreen, KidsScreen });
