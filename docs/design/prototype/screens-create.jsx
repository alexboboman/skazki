// screens-create.jsx — repeat story creation (single compact screen)
const { useState: useStateC } = React;

const TOPICS = ['Просто волшебная', 'Не страшно в темноте', 'Первый день в саду', 'Поход к врачу', 'Новый братик', 'Как помириться с другом'];
const VOICES = [
  { id: 'warm', name: 'Тёплый', sub: 'женский, мягкий' },
  { id: 'calm', name: 'Спокойный', sub: 'мужской, низкий' },
  { id: 'granny', name: 'Бабушка', sub: 'неторопливый' },
];

function Seg({ value, options, onChange }) {
  return (
    <div style={{ display: 'flex', padding: 4, borderRadius: 999, background: 'var(--card)', border: '1px solid var(--border)' }}>
      {options.map(([id, l]) => (
        <div key={id} onClick={() => onChange(id)} style={{ cursor: 'pointer', flex: 1, textAlign: 'center', padding: '10px 0', borderRadius: 999, fontSize: 14.5, fontWeight: 500,
          color: value === id ? '#1a1330' : 'var(--text-2)', background: value === id ? 'var(--accent)' : 'transparent', transition: 'all .2s' }}>{l}</div>
      ))}
    </div>
  );
}

function Label({ children }) {
  return <div className="kicker" style={{ fontSize: 11.5, color: 'var(--text-3)', margin: '26px 0 12px' }}>{children}</div>;
}

function CreateScreen({ kids, activeId, onClose, onGenerate }) {
  const [kidIds, setKidIds] = useStateC([activeId]);
  const kid = kids.find((k) => k.id === kidIds[0]) || kids[0];
  const [topic, setTopic] = useStateC(TOPICS[0]);
  const [note, setNote] = useStateC('');
  const [world, setWorld] = useStateC(kid.world || 'forest');
  const [len, setLen] = useStateC('7');
  const [mode, setMode] = useStateC('both');
  const [voice, setVoice] = useStateC('warm');
  const toggleKid = (id) => setKidIds((a) => a.includes(id) ? (a.length > 1 ? a.filter((x) => x !== id) : a) : a.concat(id));
  const names = kids.filter((k) => kidIds.includes(k.id)).map((k) => k.name).join(' и ');

  return (
    <div className="screen">
      <div className="aurora a1" /><div className="aurora a3" />
      <Stars count={30} seed={74} />
      <div className="screen-content scroll-y" style={{ paddingTop: 62, paddingBottom: 130 }}>
        <div className="anim-screen">
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 18 }}>
            <div className="icon-btn" onClick={onClose}><Ico d={['M6 6l12 12', 'M18 6L6 18']} size={18} color="var(--text)" sw={2.2} /></div>
            <span className="caption">Новая сказка</span>
            <div style={{ width: 42 }} />
          </div>
          <h1 className="display" style={{ fontSize: 29 }}>О чём будет сказка сегодня?</h1>

          <Label>Для кого</Label>
          <div style={{ display: 'flex', gap: 10 }}>
            {kids.map((k) => {
              const on = kidIds.includes(k.id);
              return (
                <div key={k.id} onClick={() => toggleKid(k.id)} style={{ cursor: 'pointer', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 7, width: 72 }}>
                  <div style={{ position: 'relative', width: 64, height: 64, borderRadius: '50%', overflow: 'hidden', display: 'flex', alignItems: 'flex-end', justifyContent: 'center',
                    background: on ? 'var(--accent-soft)' : 'var(--card)', boxShadow: on ? '0 0 0 2px var(--accent)' : '0 0 0 1px var(--border)', transition: 'all .2s' }}>
                    <HeroAvatar {...k} size={58} />
                  </div>
                  <span style={{ fontSize: 13.5, color: on ? 'var(--text)' : 'var(--text-3)', fontWeight: 500 }}>{k.name}</span>
                </div>
              );
            })}
          </div>
          {kidIds.length > 1 && <p className="caption" style={{ marginTop: 10 }}>{names} будут героями вместе.</p>}

          <Label>Тема</Label>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
            {TOPICS.map((t) => (
              <div key={t} className={'chip' + (topic === t ? ' selected' : '')} onClick={() => setTopic(t)} style={{ padding: '10px 15px', fontSize: 14.5 }}>{t}</div>
            ))}
          </div>
          <textarea value={note} onChange={(e) => setNote(e.target.value)} rows={2} placeholder="Или своими словами: что случилось за день…"
            style={{ marginTop: 12, width: '100%', resize: 'none', fontFamily: 'var(--sans)', fontSize: 15, lineHeight: 1.45, color: 'var(--text)', background: 'var(--card)',
              border: '1px solid var(--border)', borderRadius: 18, padding: '13px 15px', outline: 'none', caretColor: 'var(--accent)' }} />

          <Label>Мир</Label>
          <div className="scroll-y" style={{ display: 'flex', gap: 10, overflowX: 'auto', overflowY: 'hidden', margin: '0 -26px', padding: '0 26px 4px' }}>
            {WORLDS.map((w) => {
              const sel = world === w.id;
              return (
                <div key={w.id} className={'tile' + (sel ? ' selected' : '')} onClick={() => setWorld(w.id)} style={{ width: 118, height: 84, flexShrink: 0, display: 'flex', alignItems: 'flex-end' }}>
                  <WorldScene g={w.g} />
                  <span style={{ position: 'relative', zIndex: 2, padding: '0 11px 10px', fontFamily: 'var(--serif)', fontSize: 14, color: '#fff', lineHeight: 1.2, textShadow: '0 1px 6px rgba(0,0,0,0.6)' }}>{w.name}</span>
                </div>
              );
            })}
          </div>

          <Label>Длина</Label>
          <Seg value={len} onChange={setLen} options={[['4', '~4 мин'], ['7', '~7 мин'], ['12', '~12 мин']]} />

          <Label>Как слушаем</Label>
          <Seg value={mode} onChange={setMode} options={[['read', 'Читаю сам'], ['listen', 'Слушаем'], ['both', 'Оба']]} />
          <p className="caption" style={{ marginTop: 10 }}>
            {mode === 'read' ? 'Только текст — читаете вслух сами.' : mode === 'listen' ? 'Рассказчик читает, экран гаснет.' : 'Текст с подсветкой и озвучкой — можно переключаться.'}
          </p>

          {mode !== 'read' && (
            <React.Fragment>
              <Label>Голос рассказчика</Label>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                {VOICES.map((v) => {
                  const sel = voice === v.id;
                  return (
                    <div key={v.id} className={'tile' + (sel ? ' selected' : '')} onClick={() => setVoice(v.id)} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 14px' }}>
                      <div style={{ width: 36, height: 36, borderRadius: '50%', background: sel ? 'var(--accent)' : 'rgba(246,235,221,0.08)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                        <Ico d={IC.play} size={14} fill={sel ? '#1a1330' : 'var(--text-2)'} color={sel ? '#1a1330' : 'var(--text-2)'} sw={1.4} />
                      </div>
                      <div style={{ flex: 1 }}>
                        <div style={{ fontSize: 15.5, color: 'var(--text)', fontWeight: 500 }}>{v.name}</div>
                        <div className="caption" style={{ fontSize: 12.5 }}>{v.sub}</div>
                      </div>
                      {sel && <CheckMini size={16} color="var(--accent)" />}
                    </div>
                  );
                })}
              </div>
            </React.Fragment>
          )}
        </div>
      </div>
      <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, zIndex: 20, padding: '24px 26px 40px',
        background: 'linear-gradient(180deg, rgba(16,12,31,0), #100c1f 40%)' }}>
        <button className="btn btn-gold" onClick={() => onGenerate({ kid, world, topic: note.trim() || topic, len, mode, voice })}>
          <Sparkle size={15} color="#2b1c0c" />Сочинить сказку
        </button>
      </div>
    </div>
  );
}

Object.assign(window, { CreateScreen, TOPICS, VOICES, Seg });
