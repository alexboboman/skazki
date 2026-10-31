import type { Appearance, ChildProfile, LengthMinutes, WorldId } from "../../../../packages/shared/src/index.js";

/** How the story prompt describes each world (Russian, the language of the story prompt). */
export const WORLD_PROMPTS: Record<WorldId, string> = {
  forest: "волшебный лес с говорящими животными",
  ocean: "подводный мир с добрыми морскими жителями",
  space: "далёкий космос со звёздами и дружелюбными планетами",
  castle: "сказочная страна замков и добрых рыцарей",
  clouds: "облачное королевство высоко над землёй",
  jungle: "тёплые джунгли с дружелюбными зверями"
};

export const DEFAULT_WORLD: WorldId = "forest";

// Palette indexes match the client's SKIN_TONES, HAIR_COLORS and OUTFITS (see docs/design/prototype/ui.jsx).
const SKIN = ["very light", "light", "medium", "tan", "dark brown"];
const HAIR = ["dark brown", "brown", "chestnut", "blond", "platinum blond", "black"];
const OUTFIT = ["purple", "teal", "coral", "blue", "pink"];

export const SKIN_COUNT = SKIN.length;
export const HAIR_COUNT = HAIR.length;
export const OUTFIT_COUNT = OUTFIT.length;

/** Reading aloud runs at roughly 110 words a minute. */
const WORDS_PER_MINUTE = 110;

const WORDS_FOR_MINUTES: Record<LengthMinutes, number> = { 4: 450, 7: 780, 12: 1200 };

export function wordsForMinutes(minutes: LengthMinutes): number {
  return WORDS_FOR_MINUTES[minutes];
}

export function readingMinutes(text: string): number {
  const words = text.split(/\s+/).filter(Boolean).length;
  return Math.max(1, Math.round(words / WORDS_PER_MINUTE));
}

/** English look description, reused verbatim in every illustration prompt so the hero stays the same. */
export function describeHero(hero: ChildProfile): string {
  const kind = hero.gender === "boy" ? "boy" : hero.gender === "girl" ? "girl" : "child";
  const base = `${hero.name}, a ${hero.age}-year-old ${kind}`;
  const look = hero.appearance && describeAppearance(hero.appearance);
  return look ? `${base} with ${look}` : base;
}

function describeAppearance(a: Appearance): string {
  return `${SKIN[a.skin]} skin, ${a.hairStyle} ${HAIR[a.hair]} hair, wearing a ${OUTFIT[a.outfit]} outfit`;
}

export function heroesNames(heroes: ChildProfile[]): string {
  return heroes.map((hero) => hero.name).join(" и ");
}
