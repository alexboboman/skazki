// screens-generate.jsx — generation, story reveal, reading, paywall, done
const { useState: useStateG, useEffect: useEffectG } = React;

const GEN_STEPS = [
  'Готовим идею сказки…',
  'Пишем добрую историю…',
  'Проверяем, что всё подходит ребёнку…',
  'Рисуем иллюстрации…',
  'Сохраняем в библиотеку…',
];

const WORLD_TITLE = {
  forest: 'и звёздная пещера',
  ocean: 'и жемчужина морского царя',
  space: 'и сонные звёзды',
  castle: 'и серебряный рыцарь',
  clouds: 'и облачный замок снов',
  jungle: 'и шёпот тёплых джунглей',
};

function storyFor(data) {
  const name = data.name.trim() || 'малыш';
  const interest = (data.interests[0] || 'звёзды').toLowerCase();
  const title = `${name} ${WORLD_TITLE[data.world] || 'и звёздная пещера'}`;
  const paragraphs = [
    `Когда над миром зажглись первые звёзды, ${name} услышал тихий шёпот ветра. «Идём, — позвал он, — я покажу тебе самое волшебное место на свете».`,
    `Рядом семенил маленький друг — дракончик Рекс, чешуя которого блестела, словно изумруды. Вместе они прошли мимо спящих деревьев и оказались у входа в светящуюся пещеру.`,
    `Внутри потолок мерцал тысячами огоньков. «Это светлячки, — прошептал Рекс. — А ещё я часто думаю про ${interest}. Как думаешь, ${name}, они тоже видят сны?»`,
    `Из-за камней выглянула мудрая сова Ночка. «Когда все отдыхают, — мягко сказала она, — магия становится сильнее, а звёзды светят ярче. Лучший сон — это сон рядом с верным другом».`,
    `${name} нежно погладил дракончика по голове и почувствовал, как тёплая сонливость укрывает его, словно мягкое одеяло. Светлячки засияли нежнее, охраняя добрые сны.`,
  ];
  return {
    title,
    paragraphs,
    moral: 'Даже когда мы отдыхаем, жизнь остаётся волшебной. Настоящая магия дремлет в нас, когда мы хорошо выспались.',
    closing: 'Спи сладко. Пусть тебе приснятся звёзды и добрые драконы…',
  };
}

// ── Generation loading ───────────────────────────────────────────
function GenerateScreen({ data, onDone }) {
  const [s, setS] = useStateG(0);
  const name = data.name.trim() || 'малыш';
  useEffectG(() => {
    if (s >= GEN_STEPS.length) { const t = setTimeout(onDone, 850); return () => clearTimeout(t); }
    const t = setTimeout(() => setS(s + 1), s === 0 ? 1100 : 1350);
    return () => clearTimeout(t);
  }, [s]);
  const current = Math.min(s, GEN_STEPS.length - 1);
  return (
    <NightScreen stars={70} seed={31}>
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', textAlign: 'center' }}>
        {/* orbiting emblem */}
        <div style={{ position: 'relative', width: 200, height: 200, display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: 44 }}>
          <div style={{ position: 'absolute', inset: 0, animation: 'spinSlow 9s linear infinite' }}>
            <Sparkle size={20} style={{ position: 'absolute', top: 0, left: '50%', marginLeft: -10 }} />
            <Sparkle size={14} color="#fff" style={{ position: 'absolute', bottom: 8, left: 24 }} />
            <Sparkle size={16} style={{ position: 'absolute', bottom: 20, right: 16 }} />
          </div>
          <div style={{ position: 'absolute', width: 150, height: 150, borderRadius: '50%', border: '1px dashed rgba(184,167,255,0.3)', animation: 'spinSlow 16s linear infinite reverse' }} />
          <div className="float"><div style={{ animation: 'pulseGlow 2.6s ease-in-out infinite' }}><MoonIcon size={96} /></div></div>
        </div>

        <div className="kicker" style={{ marginBottom: 14 }}>Создаём сказку</div>
        <h2 className="display" style={{ fontSize: 28, marginBottom: 30, maxWidth: 300 }}>{name},<br />твоя сказка рождается</h2>

        <div key={current} className="shimmer-text anim-screen" style={{ fontFamily: 'var(--sans)', fontSize: 17, fontWeight: 500, minHeight: 24 }}>
          {GEN_STEPS[current]}
        </div>
      </div>

      <div style={{ paddingBottom: 50 }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {GEN_STEPS.map((label, i) => {
            const done = i < s, active = i === s;
            return (
              <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 12, opacity: done || active ? 1 : 0.4, transition: 'opacity .4s ease' }}>
                <div style={{ width: 22, height: 22, borderRadius: '50%', flexShrink: 0,
                  background: done ? 'linear-gradient(135deg,#d9ccff,var(--accent))' : 'transparent',
                  border: done ? 'none' : '1.5px solid var(--border-strong)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                  {done && <CheckMini size={13} />}
                  {active && <div style={{ width: 7, height: 7, borderRadius: '50%', background: 'var(--gold)', animation: 'pulseGlow 1s ease-in-out infinite' }} />}
                </div>
                <span className="caption" style={{ fontSize: 13.5, color: done || active ? 'var(--text-2)' : 'var(--text-3)' }}>{label}</span>
              </div>
            );
          })}
        </div>
      </div>
    </NightScreen>
  );
}

// ── Story reveal ─────────────────────────────────────────────────
function RevealScreen({ data, onRead }) {
  const story = storyFor(data);
  return (
    <NightScreen stars={40} seed={32} scroll contentStyle={{ paddingTop: 64, paddingBottom: 44 }}>
      <div className="anim-screen" style={{ textAlign: 'center', marginBottom: 22 }}>
        <div className="kicker" style={{ color: 'var(--gold)', marginBottom: 10 }}>Готово · ваша первая сказка</div>
      </div>
      <div className="rise">
        <BookCover
          height={330}
          kicker="Сказка на ночь"
          avatar={<HeroAvatar size={132} skin={data.skin} hair={data.hair} hairStyle={data.hairStyle} outfit={data.outfit} float />}
        />
      </div>
      <h2 className="title rise" style={{ animationDelay: '.08s', textAlign: 'center', fontSize: 27, marginTop: 22, marginBottom: 14 }}>{story.title}</h2>

      <div className="rise" style={{ animationDelay: '.14s', display: 'flex', gap: 8, justifyContent: 'center', marginBottom: 18, flexWrap: 'wrap' }}>
        {['≈ 5 мин чтения', `${data.age} ${ageWord(data.age)}`, '3 иллюстрации'].map((m, i) => (
          <span key={i} style={{ fontSize: 12.5, color: 'var(--text-2)', background: 'var(--card)', border: '1px solid var(--border)', borderRadius: 999, padding: '7px 13px' }}>{m}</span>
        ))}
      </div>
      <p className="body rise" style={{ animationDelay: '.2s', textAlign: 'center', maxWidth: 320, margin: '0 auto 6px', fontFamily: 'var(--serif)', fontStyle: 'italic', fontSize: 17 }}>
        «{story.paragraphs[0]}»
      </p>

      <div style={{ flex: 1 }} />
      <button className="btn btn-primary rise" style={{ animationDelay: '.26s', marginTop: 26 }} onClick={onRead}>
        <Sparkle size={16} color="#1a1330" /> Читать сказку
      </button>
    </NightScreen>
  );
}

// ── Reading mode ─────────────────────────────────────────────────
function InlineScene({ data }) {
  return (
    <div style={{ position: 'relative', width: '100%', height: 170, borderRadius: 20, overflow: 'hidden', margin: '6px 0 4px',
      background: 'linear-gradient(180deg,#241b52,#16314f)', boxShadow: 'inset 0 0 0 1px var(--border)' }}>
      <Stars count={18} seed={9} />
      <div style={{ position: 'absolute', top: 16, right: 22 }}><MoonIcon size={40} /></div>
      <div style={{ position: 'absolute', left: '-14%', bottom: -18, width: '70%', height: 64, background: '#162a4a', borderRadius: '50% 50% 0 0' }} />
      <div style={{ position: 'absolute', right: '-12%', bottom: -24, width: '74%', height: 70, background: '#11203c', borderRadius: '50% 50% 0 0' }} />
      <div style={{ position: 'absolute', left: '50%', bottom: 8, transform: 'translateX(-50%)' }}>
        <HeroAvatar size={92} skin={data.skin} hair={data.hair} hairStyle={data.hairStyle} outfit={data.outfit} />
      </div>
    </div>
  );
}

function ReadingScreen({ data, onBack, onContinue }) {
  const story = storyFor(data);
  return (
    <div className="screen">
      <div className="aurora a1" /><div className="aurora a2" />
      <div className="screen-content scroll-y" style={{ paddingTop: 0, paddingBottom: 40 }}>
        {/* minimal top bar */}
        <div style={{ position: 'sticky', top: 0, zIndex: 5, display: 'flex', alignItems: 'center', gap: 12, paddingTop: 60, paddingBottom: 14,
          background: 'linear-gradient(180deg, var(--bg-1) 60%, transparent)' }}>
          <div className="icon-btn" onClick={onBack}><Chevron dir="left" /></div>
          <div style={{ flex: 1, textAlign: 'center', fontSize: 13.5, color: 'var(--text-2)' }}>Режим чтения · ночник</div>
          <div className="icon-btn"><span style={{ fontFamily: 'var(--serif)', fontWeight: 600, color: 'var(--text-2)', fontSize: 16 }}>Аа</span></div>
        </div>

        <h1 className="title anim-screen" style={{ fontSize: 30, textAlign: 'center', margin: '8px 0 6px' }}>{story.title}</h1>
        <p className="caption" style={{ textAlign: 'center', marginBottom: 22 }}>{data.name.trim() || 'Малыш'} · сказка на ночь</p>

        <p style={readP}>{story.paragraphs[0]}</p>
        <p style={readP}>{story.paragraphs[1]}</p>
        <InlineScene data={data} />
        <p style={readP}>{story.paragraphs[2]}</p>
        <p style={readP}>{story.paragraphs[3]}</p>
        <p style={readP}>{story.paragraphs[4]}</p>

        <div style={{ borderTop: '1px solid var(--border)', margin: '22px 0', paddingTop: 20 }}>
          <div className="kicker" style={{ color: 'var(--gold)', marginBottom: 10 }}>Мораль сказки</div>
          <p style={{ ...readP, fontStyle: 'italic', color: 'var(--text)' }}>{story.moral}</p>
        </div>
        <p style={{ fontFamily: 'var(--serif)', fontStyle: 'italic', fontSize: 17, color: 'var(--accent)', textAlign: 'center', marginBottom: 28 }}>{story.closing}</p>

        {/* gentle upsell */}
        <div className="glass-card" style={{ padding: 22, textAlign: 'center' }}>
          <div className="float" style={{ display: 'inline-block', marginBottom: 8 }}><Sparkle size={26} /></div>
          <h3 className="title" style={{ fontSize: 21, marginBottom: 8 }}>Понравилось?</h3>
          <p className="body" style={{ marginBottom: 18 }}>Создавайте новую сказку каждый вечер — без ограничений.</p>
          <button className="btn btn-gold" onClick={onContinue}>Попробовать 7 дней бесплатно</button>
        </div>
      </div>
    </div>
  );
}
const readP = { fontFamily: 'var(--serif)', fontSize: 19, lineHeight: 1.72, color: 'var(--text)', margin: '0 0 18px', textWrap: 'pretty' };

// ── Paywall ──────────────────────────────────────────────────────
function PaywallScreen({ data, onTrial, onFree }) {
  const [plan, setPlan] = useStateG('year');
  const name = data.name.trim() || 'малыша';
  const benefits = [
    'Безлимит коротких сказок каждый вечер',
    'Сериалы на 7, 14 и 30 вечеров',
    'HD-иллюстрации в едином стиле',
    `Герой, похожий на вашего ребёнка`,
  ];
  return (
    <NightScreen stars={48} seed={33} scroll contentStyle={{ paddingTop: 62, paddingBottom: 40 }}>
      <div className="anim-screen" style={{ textAlign: 'center', marginBottom: 24 }}>
        <div className="float" style={{ display: 'inline-block', marginBottom: 12 }}><MoonIcon size={64} /></div>
        <h2 className="display" style={{ fontSize: 30, marginBottom: 12 }}>Откройте Сказочник<br />полностью</h2>
        <p className="body" style={{ maxWidth: 300, margin: '0 auto' }}>7 дней бесплатно. Затем — по цене одной книжки в месяц.</p>
      </div>

      <div className="glass-card" style={{ padding: '18px 20px', marginBottom: 16 }}>
        {benefits.map((b, i) => (
          <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 13, padding: '9px 0' }}>
            <div style={{ width: 24, height: 24, borderRadius: '50%', flexShrink: 0, background: 'linear-gradient(135deg,#d9ccff,var(--accent))', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <CheckMini size={14} />
            </div>
            <span style={{ fontSize: 15.5, color: 'var(--text)' }}>{b}</span>
          </div>
        ))}
      </div>

      {/* plan toggle */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 11, marginBottom: 20 }}>
        {[
          { id: 'year', name: 'Family · год', price: '4 167 ₽ / мес', sub: 'оплата 49 990 ₽ в год', badge: 'Выгода 40%' },
          { id: 'month', name: 'Family · месяц', price: '699 ₽ / мес', sub: 'гибко, отмена в любой момент', badge: null },
        ].map((p) => {
          const sel = plan === p.id;
          return (
            <div key={p.id} className={"tile" + (sel ? " selected" : "")} onClick={() => setPlan(p.id)}
              style={{ padding: '16px 18px', display: 'flex', alignItems: 'center', gap: 14 }}>
              <div style={{ width: 22, height: 22, borderRadius: '50%', flexShrink: 0, border: '2px solid ' + (sel ? 'var(--accent)' : 'var(--border-strong)'), display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                {sel && <div style={{ width: 11, height: 11, borderRadius: '50%', background: 'var(--accent)' }} />}
              </div>
              <div style={{ flex: 1 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                  <span style={{ fontSize: 16, fontWeight: 600, color: 'var(--text)' }}>{p.name}</span>
                  {p.badge && <span style={{ fontSize: 11, fontWeight: 600, color: 'var(--gold)', background: 'var(--gold-soft)', borderRadius: 999, padding: '3px 9px' }}>{p.badge}</span>}
                </div>
                <div className="caption" style={{ marginTop: 3 }}>{p.sub}</div>
              </div>
              <div style={{ fontSize: 15.5, fontWeight: 600, color: 'var(--text)' }}>{p.price}</div>
            </div>
          );
        })}
      </div>

      <button className="btn btn-gold" onClick={onTrial}>
        <Sparkle size={16} color="#2b1c0c" /> Попробовать 7 дней бесплатно
      </button>
      <button className="btn btn-ghost" onClick={onFree} style={{ marginTop: 4 }}>Продолжить с Free</button>
      <div style={{ display: 'flex', gap: 18, justifyContent: 'center', marginTop: 10 }}>
        {['Восстановить', 'Условия', 'Конфиденциальность'].map((t) => (
          <span key={t} className="caption" style={{ fontSize: 11.5 }}>{t}</span>
        ))}
      </div>
    </NightScreen>
  );
}

// ── Done ─────────────────────────────────────────────────────────
function DoneScreen({ data, trial, onRestart, onHome }) {
  const name = data.name.trim() || 'малыш';
  return (
    <NightScreen stars={64} seed={34}>
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', textAlign: 'center' }}>
        <div className="rise" style={{ position: 'relative', marginBottom: 30 }}>
          <div style={{ position: 'absolute', inset: -24, borderRadius: '50%', background: 'radial-gradient(circle, rgba(230,168,92,0.3), transparent 65%)' }} />
          <HeroAvatar size={132} skin={data.skin} hair={data.hair} hairStyle={data.hairStyle} outfit={data.outfit} float />
          <Sparkle size={20} style={{ position: 'absolute', top: 0, right: 8 }} />
          <Sparkle size={14} color="#fff" style={{ position: 'absolute', bottom: 18, left: 0 }} />
        </div>
        <div className="kicker rise" style={{ animationDelay: '.06s', color: 'var(--gold)', marginBottom: 14 }}>
          {trial ? 'Пробный период активен' : 'Профиль создан'}
        </div>
        <h2 className="display rise" style={{ animationDelay: '.12s', fontSize: 32, marginBottom: 16 }}>Всё готово,<br />{name} ждёт сказку</h2>
        <p className="body rise" style={{ animationDelay: '.18s', maxWidth: 290 }}>
          Каждый вечер вас будет ждать новая добрая история. Спокойных снов!
        </p>
      </div>
      <div className="rise" style={{ animationDelay: '.24s', paddingBottom: 46 }}>
        <button className="btn btn-primary" onClick={onHome}>Перейти к сказкам</button>
        <button className="btn btn-ghost" onClick={onRestart} style={{ marginTop: 2 }}>Пройти онбординг заново</button>
      </div>
    </NightScreen>
  );
}

Object.assign(window, {
  GEN_STEPS, storyFor, GenerateScreen, RevealScreen, ReadingScreen, PaywallScreen, DoneScreen,
});
