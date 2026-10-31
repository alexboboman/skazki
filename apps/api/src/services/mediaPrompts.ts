export interface ParsedStory {
  /** Leading `# Heading` of the raw text, without the hashes. */
  title?: string;
  /** Body paragraphs with every marker removed; the heading is not part of it. */
  text: string;
  moral?: string;
  closing?: string;
  /** Series only: what happened in this part, for the writer of the next one. */
  summary?: string;
  /** Series only, part 1: the recurring characters and the setting, in English. */
  seed?: string;
  images: ImageCue[];
  /** Stored as metadata only: the worker ignores them until the matching feature flag exists. */
  audioCues: string[];
  videoCues: string[];
}

export interface ImageCue {
  prompt: string;
  /** Number of the body paragraph this image follows (1-based, the heading does not count). */
  afterParagraph: number;
}

const MARKER = /\[(IMAGE|ILLUSTRATION|AUDIO_CUE|VIDEO_CUE|MORAL|CLOSING|SUMMARY|SEED):\s*([^\]]*?)\s*\]/gi;

/**
 * Splits the raw Claude output into title, body text, moral, closing line and media cues.
 * `[ILLUSTRATION: ...]` is accepted as a legacy alias of `[IMAGE: ...]`.
 */
export function parseMediaMarkers(raw: string): ParsedStory {
  const images: ImageCue[] = [];
  const audioCues: string[] = [];
  const videoCues: string[] = [];
  const paragraphs: string[] = [];
  let title: string | undefined;
  let moral: string | undefined;
  let closing: string | undefined;
  let summary: string | undefined;
  let seed: string | undefined;

  for (const block of raw.split(/\n{2,}/)) {
    const cues: Array<{ kind: string; value: string }> = [];
    const stripped = block.replace(MARKER, (_match, kind: string, value: string) => {
      cues.push({ kind: kind.toUpperCase(), value });
      return "";
    });
    const clean = stripped.replace(/[ \t]+\n/g, "\n").trim();

    if (clean && title === undefined && paragraphs.length === 0 && /^#+\s/.test(clean)) {
      title = clean.replace(/^#+\s*/, "").trim();
    } else if (clean) {
      paragraphs.push(clean);
    }

    for (const cue of cues) {
      if (cue.kind === "AUDIO_CUE") {
        audioCues.push(cue.value);
      } else if (cue.kind === "VIDEO_CUE") {
        videoCues.push(cue.value);
      } else if (cue.kind === "MORAL") {
        moral ||= cue.value || undefined;
      } else if (cue.kind === "CLOSING") {
        closing ||= cue.value || undefined;
      } else if (cue.kind === "SUMMARY") {
        summary ||= cue.value || undefined;
      } else if (cue.kind === "SEED") {
        seed ||= cue.value || undefined;
      } else if (cue.value) {
        images.push({ prompt: cue.value, afterParagraph: Math.max(paragraphs.length, 1) });
      }
    }
  }

  return { title, text: paragraphs.join("\n\n"), moral, closing, summary, seed, images, audioCues, videoCues };
}
