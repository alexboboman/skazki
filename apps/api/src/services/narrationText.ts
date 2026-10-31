/** What a narrator says for one part of a story: the name, the paragraphs, the moral and the good-night line. Mirrors `ReadableStory.narrationScript` in the iOS app. */
export function narrationText(part: {
  title?: string;
  text: string;
  moral?: string;
  closing?: string;
  /** Set for parts of a series. */
  partNumber?: number;
}): string {
  const blocks: string[] = [];

  if (part.title) {
    blocks.push(part.partNumber ? `Часть ${part.partNumber}. ${part.title}.` : `${part.title}.`);
  }

  blocks.push(...part.text.split(/\n{2,}/).map((paragraph) => paragraph.trim()).filter(Boolean));

  if (part.moral) {
    blocks.push(`Мораль сказки. ${part.moral}`);
  }

  if (part.closing) {
    blocks.push(part.closing);
  }

  return blocks.join("\n\n");
}

/**
 * Splits the text into pieces of at most `maxChars`, on paragraph borders (a long paragraph is split on
 * sentences), so every piece can be voiced by one call and the joins fall on natural pauses.
 */
export function splitForSpeech(text: string, maxChars: number): string[] {
  const pieces: string[] = [];
  let current = "";

  const push = (unit: string) => {
    if (current && current.length + unit.length + 2 > maxChars) {
      pieces.push(current);
      current = "";
    }
    current = current ? `${current}\n\n${unit}` : unit;
  };

  for (const paragraph of text.split(/\n{2,}/).map((item) => item.trim()).filter(Boolean)) {
    if (paragraph.length <= maxChars) {
      push(paragraph);
      continue;
    }

    for (const sentence of splitSentences(paragraph, maxChars)) {
      push(sentence);
    }
  }

  if (current) {
    pieces.push(current);
  }

  return pieces;
}

function splitSentences(paragraph: string, maxChars: number): string[] {
  const sentences = paragraph.match(/[^.!?…]+[.!?…]+["»”)]*\s*|[^.!?…]+$/g) ?? [paragraph];
  const units: string[] = [];

  for (const sentence of sentences.map((item) => item.trim()).filter(Boolean)) {
    // A sentence longer than the limit is cut at the limit; it should not happen in a children's story.
    for (let start = 0; start < sentence.length; start += maxChars) {
      units.push(sentence.slice(start, start + maxChars));
    }
  }

  return units;
}
