// app.jsx — root state machine + tweaks
const { useState: useStateA, useEffect: useEffectA } = React;

const ORDER = ['welcome', 'value', 'name', 'age', 'appearance', 'interests', 'world', 'generate', 'reveal', 'reading', 'paywall', 'done'];
const PROFILE_IDX = { name: 0, age: 1, appearance: 2, interests: 3, world: 4 };

const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "accent": "#B8A7FF",
  "nightlight": false,
  "reduceMotion": false
}/*EDITMODE-END*/;

function hexToRgba(hex, a) {
  const n = parseInt(hex.slice(1), 16);
  return `rgba(${n >> 16},${(n >> 8) & 255},${n & 255},${a})`;
}

function useFitScale(w, h, pad = 36) {
  const [scale, setScale] = useStateA(1);
  useEffectA(() => {
    const fit = () => {
      const s = Math.min(1, (window.innerWidth - pad) / w, (window.innerHeight - pad) / h);
      setScale(s > 0 ? s : 1);
    };
    fit();
    window.addEventListener('resize', fit);
    return () => window.removeEventListener('resize', fit);
  }, [w, h, pad]);
  return scale;
}

function App() {
  const [t, setTweak] = useTweaks(TWEAK_DEFAULTS);
  const scale = useFitScale(402, 874);
  const [step, setStep] = useStateA('welcome');
  const [trial, setTrial] = useStateA(false);
  const [data, setData] = useStateA({
    name: '', age: 5, gender: 'none',
    skin: 1, hair: 1, hairStyle: 'short', outfit: 0,
    interests: [], world: 'forest',
  });
  const patch = (p) => setData((d) => ({ ...d, ...p }));
  const go = (s) => setStep(s);
  const [activeKid, setActiveKid] = useStateA('k1');
  const [storyData, setStoryData] = useStateA(null);
  const [inApp, setInApp] = useStateA(false);
  const [lastTab, setLastTab] = useStateA('home');
  const kids = [
    { id: 'k1', name: data.name.trim() || 'Аня', age: data.age, skin: data.skin, hair: data.hair, hairStyle: data.name.trim() ? data.hairStyle : 'long', outfit: data.outfit,
      interests: data.interests.length ? data.interests : ['Животные', 'Феи', 'Море'], world: data.world },
    { id: 'k2', name: 'Миша', age: 3, skin: 1, hair: 3, hairStyle: 'short', outfit: 1, interests: ['Машинки', 'Космос', 'Динозавры'], world: 'space' },
  ];
  const kidData = (k) => ({ ...data, ...k, name: k.name });
  const onTab = (id) => { if (id !== 'create') setLastTab(id); go(id); };
  const openStory = (s) => { setStoryData(kidData(kids.find((k) => k.id === s.kid) || kids[0])); setInApp(true); go('reading'); };
  const enterApp = () => { setInApp(true); go('home'); };

  // apply accent tweak to CSS vars
  useEffectA(() => {
    const r = document.documentElement;
    r.style.setProperty('--accent', t.accent);
    r.style.setProperty('--accent-deep', shade(t.accent, -34));
    r.style.setProperty('--accent-soft', hexToRgba(t.accent, 0.16));
  }, [t.accent]);

  useEffectA(() => {
    document.documentElement.classList.toggle('no-motion', !!t.reduceMotion);
  }, [t.reduceMotion]);

  let screen;
  switch (step) {
    case 'welcome':
      screen = <WelcomeScreen onStart={() => go('value')} />; break;
    case 'value':
      screen = <ValueScreen onBack={() => go('welcome')} onDone={() => go('name')} />; break;
    case 'name':
      screen = <NameScreen step={PROFILE_IDX.name} data={data} setData={patch} onBack={() => go('value')} onNext={() => go('age')} />; break;
    case 'age':
      screen = <AgeScreen step={PROFILE_IDX.age} data={data} setData={patch} onBack={() => go('name')} onNext={() => go('appearance')} />; break;
    case 'appearance':
      screen = <AppearanceScreen step={PROFILE_IDX.appearance} data={data} setData={patch} onBack={() => go('age')} onNext={() => go('interests')} />; break;
    case 'interests':
      screen = <InterestsScreen step={PROFILE_IDX.interests} data={data} setData={patch} onBack={() => go('appearance')} onNext={() => go('world')} />; break;
    case 'world':
      screen = <WorldScreen step={PROFILE_IDX.world} data={data} setData={patch} onBack={() => go('interests')} onNext={() => go('generate')} />; break;
    case 'generate':
      screen = <GenerateScreen data={inApp && storyData ? storyData : data} onDone={() => go('reveal')} />; break;
    case 'reveal':
      screen = <RevealScreen data={inApp && storyData ? storyData : data} onRead={() => go('reading')} />; break;
    case 'reading':
      screen = <ReadingScreen data={inApp && storyData ? storyData : data} onBack={() => go(inApp ? lastTab : 'reveal')} onContinue={() => go(inApp ? lastTab : 'paywall')} />; break;
    case 'home':
      screen = <HomeScreen kids={kids} activeId={activeKid} setActive={setActiveKid} onTab={onTab} onOpen={openStory} onCreate={() => go('create')} />; break;
    case 'library':
      screen = <LibraryScreen kids={kids} onTab={onTab} onOpen={openStory} />; break;
    case 'kids':
      screen = <KidsScreen kids={kids} activeId={activeKid} setActive={setActiveKid} onTab={onTab} onAdd={() => { setInApp(false); go('name'); }} />; break;
    case 'create':
      screen = <CreateScreen kids={kids} activeId={activeKid} onClose={() => go(lastTab)}
        onGenerate={(o) => { setStoryData({ ...kidData(o.kid), world: o.world }); setInApp(true); go('generate'); }} />; break;
    case 'paywall':
      screen = <PaywallScreen data={data} onTrial={() => { setTrial(true); go('done'); }} onFree={() => { setTrial(false); go('done'); }} />; break;
    case 'done':
      screen = <DoneScreen data={data} trial={trial} onHome={enterApp} onRestart={() => { setInApp(false); setStep('welcome'); }} />; break;
    default:
      screen = <WelcomeScreen onStart={() => go('value')} />;
  }

  return (
    <React.Fragment>
      <div style={{ width: 402 * scale, height: 874 * scale }}>
        <div style={{ width: 402, height: 874, transform: `scale(${scale})`, transformOrigin: 'top left' }}>
          <IOSDevice dark>
            <div key={step} style={{ position: 'absolute', inset: 0 }}>
              {screen}
              {t.nightlight && (
                <div style={{ position: 'absolute', inset: 0, zIndex: 40, pointerEvents: 'none',
                  background: 'rgba(255,168,72,0.10)', mixBlendMode: 'multiply' }} />
              )}
            </div>
          </IOSDevice>
        </div>
      </div>

      <TweaksPanel>
        <TweakSection label="Оформление" />
        <TweakColor label="Акцент" value={t.accent}
          options={['#B8A7FF', '#7FD4C8', '#F0A6C0', '#E6A85C']}
          onChange={(v) => setTweak('accent', v)} />
        <TweakToggle label="Тёплый ночник" value={t.nightlight}
          onChange={(v) => setTweak('nightlight', v)} />
        <TweakSection label="Навигация" />
        <TweakSelect label="Экран" value={step} options={[
          { value: 'welcome', label: 'Онбординг: старт' }, { value: 'paywall', label: 'Пейвол' },
          { value: 'home', label: 'Главная' }, { value: 'library', label: 'Библиотека' },
          { value: 'create', label: 'Новая сказка' }, { value: 'kids', label: 'Дети' }]}
          onChange={(v) => { if (['home','library','kids','create'].includes(v)) setInApp(true); if (v !== 'create') setLastTab(['home','library','kids'].includes(v) ? v : lastTab); go(v); }} />
        <TweakToggle label="Меньше движения" value={t.reduceMotion}
          onChange={(v) => setTweak('reduceMotion', v)} />
      </TweaksPanel>
    </React.Fragment>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<App />);
