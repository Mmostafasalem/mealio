import { createElement, type ReactNode } from "react";

// Deliberately bounded Markdown support for the canonical legal documents:
// headings, paragraphs, flat lists, emphasis, code and inline links. All other
// text (including HTML) is rendered as escaped text by React.
function safeHref(value: string): string | undefined {
  const href = value.trim();
  if (/^(?:\.\/)?PRIVACY\.md$/i.test(href)) return "/privacy";
  if (/^(?:\.\/)?SUPPORT\.md$/i.test(href)) return "/support";
  if (/[\u0000-\u0020\u007f]/.test(href)) return undefined;
  try {
    const url = new URL(href);
    if (["http:", "https:", "mailto:"].includes(url.protocol)) return href;
  } catch {
    // Relative paths and malformed URLs stay readable without becoming links.
  }
  return undefined;
}

function inline(text: string, allowLinks = true): ReactNode[] {
  const pattern = /\[([^\]\n]+)\]\(([^\s()]+(?:\([^\s()]*\)[^\s()]*)*)\)|\*\*(.+?)\*\*|__(.+?)__|\*([^*]+)\*|_([^_]+)_|`([^`]+)`/g;
  const nodes: ReactNode[] = [];
  let cursor = 0;
  for (const match of text.matchAll(pattern)) {
    nodes.push(text.slice(cursor, match.index));
    const key = match.index;
    if (match[1] !== undefined) {
      const href = allowLinks ? safeHref(match[2]) : undefined;
      nodes.push(href ? (
        <a key={key} href={href} className="break-words underline underline-offset-4">
          {inline(match[1], false)}
        </a>
      ) : <span key={key}>{inline(match[1], false)}</span>);
    } else if (match[3] !== undefined || match[4] !== undefined) {
      nodes.push(<strong key={key}>{inline(match[3] ?? match[4], allowLinks)}</strong>);
    } else if (match[5] !== undefined || match[6] !== undefined) {
      nodes.push(<em key={key}>{inline(match[5] ?? match[6], allowLinks)}</em>);
    } else {
      nodes.push(<code key={key}>{match[7]}</code>);
    }
    cursor = match.index + match[0].length;
  }
  nodes.push(text.slice(cursor));
  return nodes;
}

export function LegalPage({ markdown }: { markdown: string }) {
  const lines = markdown.replace(/\r\n?/g, "\n").split("\n");
  const blocks: ReactNode[] = [];
  const heading = /^(#{1,6})\s+(.+?)(?:\s+#+)?$/;
  const listItem = /^\s*(?:([-+*])|(\d+)\.)\s+(.+)$/;
  let index = 0;

  while (index < lines.length) {
    const line = lines[index];
    const key = index;
    if (!line.trim()) {
      index++;
      continue;
    }
    const title = line.match(heading);
    if (title) {
      blocks.push(createElement(`h${title[1].length}`, {
        key,
        className: title[1].length === 1
          ? "mb-6 text-3xl font-bold"
          : "mb-3 mt-8 text-xl font-semibold",
      }, inline(title[2])));
      index++;
      continue;
    }
    const firstItem = line.match(listItem);
    if (firstItem) {
      const ordered = firstItem[2] !== undefined;
      const items: ReactNode[] = [];
      while (index < lines.length) {
        const item = lines[index].match(listItem);
        if (!item || (item[2] !== undefined) !== ordered) break;
        const itemKey = index++;
        const text = [item[3]];
        while (index < lines.length && lines[index].trim()
          && !listItem.test(lines[index]) && !heading.test(lines[index])) {
          text.push(lines[index++].trim());
        }
        items.push(<li key={itemKey}>{inline(text.join(" "))}</li>);
      }
      blocks.push(ordered ? (
        <ol key={key} start={Number(firstItem[2])} className="mb-4 list-decimal space-y-2 pl-6">{items}</ol>
      ) : <ul key={key} className="mb-4 list-disc space-y-2 pl-6">{items}</ul>);
      continue;
    }
    const paragraph = [lines[index++].trim()];
    while (index < lines.length && lines[index].trim()
      && !heading.test(lines[index]) && !listItem.test(lines[index])) {
      paragraph.push(lines[index++].trim());
    }
    blocks.push(<p key={key} className="mb-4">{inline(paragraph.join(" "))}</p>);
  }

  return <main className="max-w-prose break-words text-base leading-7 text-foreground">{blocks}</main>;
}
