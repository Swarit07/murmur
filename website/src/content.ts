import { APP, GLYPH } from './lib/icons';
import { local, repoUrl, site } from './site';

const hk = site.hotkey;

export type OS = 'mac' | 'win' | 'linux';

export const platforms: Record<OS, { label: string; note: string; ext: string; cmd: string; glyph: string }> = {
  mac: { label: 'macOS', note: 'Apple Silicon and Intel', ext: '.dmg', cmd: 'brew install --cask murmur', glyph: GLYPH.mac },
  win: { label: 'Windows', note: 'Windows 10 and 11, x64', ext: '.exe', cmd: 'winget install Murmur.Murmur', glyph: GLYPH.win },
  linux: { label: 'Linux', note: 'x86_64 AppImage', ext: '.AppImage', cmd: 'chmod +x Murmur-x86_64.AppImage', glyph: GLYPH.linux },
};
export const platformOrder: OS[] = ['mac', 'win', 'linux'];

export function detectOS(): OS {
  const ua = navigator.userAgent || '';
  const nav = navigator as Navigator & { userAgentData?: { platform?: string } };
  const plat = nav.userAgentData?.platform || navigator.platform || '';
  if (/win/i.test(plat) || /Windows/i.test(ua)) return 'win';
  if (/linux|x11|cros/i.test(`${plat} ${ua}`) && !/android/i.test(ua)) return 'linux';
  return 'mac';
}

// Terminal lines: c = command, o = output, r = the "ready" line.
export type TermLine = [text: string, kind: 'c' | 'o' | 'r'];
export function terminalSpec(os: OS): TermLine[] {
  const ready = `Murmur is running. Hold ${hk} to talk.`;
  const v = site.version;
  if (os === 'win') return [['> winget install Murmur.Murmur', 'c'], [`Found Murmur [Murmur.Murmur] ${v}`, 'o'], ['Successfully installed', 'o'], ['> murmur', 'c'], [ready, 'r']];
  if (os === 'linux') return [['$ chmod +x Murmur-x86_64.AppImage', 'c'], ['$ ./Murmur-x86_64.AppImage', 'c'], [`Murmur ${v} started`, 'o'], [ready, 'r']];
  return [['$ brew install --cask murmur', 'c'], [`==> Downloading Murmur ${v}`, 'o'], ['==> Installing Murmur.app', 'o'], ['$ open -a Murmur', 'c'], [ready, 'r']];
}

// "{...}" marks words Murmur removes; k numbers them so they can be struck through in order.
export type Word = { w: string; filler: boolean; k: number };
export type Spoken = { words: Word[]; fillers: number };
function parse(str: string): Spoken {
  const words: Word[] = [];
  const re = /\{([^}]*)\}|([^\s{}]+)/g;
  let k = 0;
  for (let m = re.exec(str); m; m = re.exec(str)) {
    if (m[1] !== undefined) m[1].split(/\s+/).filter(Boolean).forEach((w) => words.push({ w, filler: true, k: k++ }));
    else words.push({ w: m[2], filler: false, k: -1 });
  }
  return { words, fillers: k };
}

export const scenarios = [
  { tab: 'Email', title: 'New message', raw: parse('{um} {so} can we push the sync to {thursday — no wait,} friday {—} and {uh} loop in priya'), clean: 'Can we push the sync to Friday and loop in Priya?', badge: '3 fillers removed · 1 correction applied · 0.4s' },
  { tab: 'Chat', title: '#launch-crew', raw: parse("haha yeah that works for me {uh} i'll grab coffee on the way do you want anything"), clean: "Haha yeah, that works for me! I'll grab coffee on the way — do you want anything?", badge: 'Casual tone kept · punctuation added · 0.3s' },
  { tab: 'Code', title: 'dashboard.tsx', raw: parse('{okay} {so} todo fix the use effect cleanup in dashboard update read me dot md then run npm run build'), clean: 'TODO: fix the useEffect cleanup in Dashboard, update README.md, then run npm run build', badge: '4 dictionary terms · 2 fillers removed · 0.4s' },
];

export const demoSteps = [
  { title: 'Hold the key', body: `Press and hold ${hk}, in any app.`, at: 0.6 },
  { title: 'Speak naturally', body: "Ramble, pause, change your mind. That's fine.", at: 0.8 },
  { title: 'Release', body: 'Let go, and Murmur tidies it up.', at: 4.6 },
  { title: "Clean text, right where you're typing", body: "Inserted at your cursor, as if you'd typed it.", at: 5.2 },
];

export const beforeAfter = [
  { raw: parse('{so I think} the main thing is {um} we need to {like} ship the beta before the conference {you know} and then fix onboarding after'), clean: 'The main thing is we need to ship the beta before the conference, then fix onboarding after.' },
  { raw: parse('hey can you send me {the} the slides from {yesterday — actually no,} monday'), clean: 'Hey, can you send me the slides from Monday?' },
  { raw: parse("{okay so} {um} the client review moved to three thirty and {uh} it's in room four b now"), clean: "The client review moved to 3:30, and it's in Room 4B now." },
];

export const apps = [
  ['Mail', APP.mail], ['Notes', APP.notes], ['Chat', APP.chat], ['Docs', APP.docs], ['Terminal', APP.term],
  ['Code editor', APP.code], ['Browser', APP.browser], ['Search', APP.search], ['Calendar', APP.cal], ['Sheets', APP.sheet],
].map(([name, d]) => ({ name, d }));

export const features = [
  { d: 'M3 7h18v10H3z M7 11h.01 M11 11h.01 M15 11h.01 M8 14h8', title: 'Hold to talk, or tap to toggle', body: `Hold ${hk} while you speak, or tap it once to keep listening hands-free. Rebind it to any key you like.` },
  { d: 'M6 11h12v9H6z M8.5 11V8a3.5 3.5 0 0 1 7 0v3', title: local ? 'Transcribed on your machine' : 'Local first, cloud optional', body: local ? 'Speech is recognised by a local model. No account, no upload, and it keeps working offline.' : 'Speech is recognised locally by default. Add a cloud key only if you want it.' },
  { d: 'M4 20h4L19 9l-4-4L4 16z M13.5 6.5l4 4', title: 'Cleanup that still sounds like you', body: 'Fillers go, punctuation arrives, and when you correct yourself mid-sentence, Murmur keeps the correction.' },
  { d: 'M5 4h10a3 3 0 0 1 3 3v13H8a3 3 0 0 1-3-3z M5 17a3 3 0 0 1 3-3h10', title: 'A dictionary for your words', body: 'Teach it names, product terms and code identifiers once. useEffect stays useEffect.' },
  { d: 'M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0 M3 12h18 M12 3c2.5 2.6 3.8 5.6 3.8 9s-1.3 6.4-3.8 9c-2.5-2.6-3.8-5.6-3.8-9S9.5 5.6 12 3z', title: 'More than one language', body: 'Dictate in the languages your speech model supports. [Supported language list to be confirmed.]' },
  { d: 'M5 19L19 5 M9 5h10v10', title: 'Out of the way until you need it', body: 'Murmur waits quietly until you hold the key, then gets out of the way again once the text lands.' },
];

export const privacy = {
  title: local ? 'Your voice never leaves your machine.' : 'Local by default. Cloud only when you ask.',
  body: local
    ? 'Murmur listens only while you hold the key. The audio is transcribed and cleaned up on your own computer, and the text goes straight to your cursor.'
    : 'Out of the box, audio is transcribed on your computer. If you add a cloud API key, the clip from that dictation is sent to the provider you chose — only while that option is on.',
  points: local
    ? ['The microphone is live only while the hotkey is held.', 'Speech recognition and cleanup run on-device.', 'The code is public, so every claim here can be checked.']
    : ['The microphone is live only while the hotkey is held.', 'Cloud transcription is off until you switch it on.', 'The code is public, so every claim here can be checked.'],
};

export const faqs: [q: string, a: string][] = [
  ['Is it really free?', `Yes. Murmur is open-source software under the ${site.license} license. There's no paid tier and no account to create.`],
  ['Does it work offline?', local ? 'Yes. Transcription and cleanup both run on your computer, so Murmur works without a connection.' : 'Yes, by default. Only the optional cloud mode needs a connection.'],
  ['Which apps does it work in?', 'Any app with a text field — mail, chat, documents, browsers, terminals and code editors. Text is inserted wherever your cursor is.'],
  ['How do I change the hotkey?', `Open Murmur's settings, choose the shortcut, and press the key you want instead of ${hk}. You can also switch between hold-to-talk and toggle.`],
  ['What languages does it support?', 'Murmur supports the languages of its speech model. [Add the confirmed language list here.]'],
  ['How do I uninstall it?', 'On macOS, run brew uninstall --cask murmur or drag Murmur to the Trash. On Windows, remove it from Settings → Apps. On Linux, delete the AppImage.'],
  ['How do I contribute?', 'Issues and pull requests are welcome on GitHub. Read CONTRIBUTING.md first, and look for issues labelled "good first issue".'],
];

export const footerCols = [
  { title: 'Product', links: [{ label: 'Download', href: '#download' }, { label: 'How it works', href: '#how' }, { label: 'Features', href: '#features' }, { label: 'Changelog', href: `${repoUrl}/releases` }] },
  { title: 'Open source', links: [{ label: 'GitHub', href: repoUrl }, { label: 'License', href: `${repoUrl}/blob/main/LICENSE` }, { label: 'Releases', href: `${repoUrl}/releases` }, { label: 'Contributing', href: `${repoUrl}/blob/main/CONTRIBUTING.md` }] },
  { title: 'Resources', links: [{ label: 'Docs', href: `${repoUrl}#readme` }, { label: 'FAQ', href: '#faq' }, { label: 'Privacy', href: '#privacy' }] },
  { title: 'Community', links: [{ label: 'Discussions', href: `${repoUrl}/discussions` }, { label: 'Issues', href: `${repoUrl}/issues` }] },
];
