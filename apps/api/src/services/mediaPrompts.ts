export interface ParsedStory {
  /** Story text with all media markers removed. */
  text: string;
  images: ImageCue[];
  /** Stored as metadata only: the worker ignores them until the matching feature flag exists. */
  audioCues: string[];
  videoCues: string[];
}

export interface ImageCue {
  prompt: string;
  /** Number of the paragraph in the clean text this image follows (1-based). */
  afterParagraph: number;
}

const MARKER = /\[(IMAGE|ILLUSTRATION|AUDIO_CUE|VIDEO_CUE):\s*([^\]]*?)\s*\]/gi;

/**
 * Splits the raw Claude output into clean story text and media cues.
 * `[ILLUSTRATION: ...]` is accepted as a legacy alias of `[IMAGE: ...]`.
 */
export function parseMediaMarkers(raw: string): ParsedStory {
  const images: ImageCue[] = [];
  const audioCues: string[] = [];
  const videoCues: string[] = [];
  const paragraphs: string[] = [];

  for (const block of raw.split(/\n{2,}/)) {
    const cues: Array<{ kind: string; value: string }> = [];
    const stripped = block.replace(MARKER, (_match, kind: string, value: string) => {
      cues.push({ kind: kind.toUpperCase(), value });
      return "";
    });
    const clean = stripped.replace(/[ \t]+\n/g, "\n").trim();

    if (clean) {
      paragraphs.push(clean);
    }

    for (const cue of cues) {
      if (cue.kind === "AUDIO_CUE") {
        audioCues.push(cue.value);
      } else if (cue.kind === "VIDEO_CUE") {
        videoCues.push(cue.value);
      } else if (cue.value) {
        images.push({ prompt: cue.value, afterParagraph: Math.max(paragraphs.length, 1) });
      }
    }
  }

  return { text: paragraphs.join("\n\n"), images, audioCues, videoCues };
}
