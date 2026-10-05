// Product facts the page quotes. These were the design's editable props in Claude Design.
export const site = {
  hotkey: 'fn',
  transcription: 'Local only' as 'Local only' | 'Local + optional cloud',
  githubUrl: 'https://github.com/Swarit07/murmur',
  version: 'v0.1.0',
  license: 'MIT',
  author: 'Swarit Sheel',
};

export const local = site.transcription === 'Local only';
export const repoUrl = site.githubUrl.replace(/\/$/, '');
export const releasesUrl = `${repoUrl}/releases/latest`;
export const docsUrl = `${repoUrl}#readme`;
