import { covers, missingGlyphs, parseCoverage, textOf } from '../src/glyphs';

test('fc-query の charset の形を読み、重なりをまとめる', () => {
  const c = parseCoverage('20-7e a0-ff\n3000-30ff 3001 4e00-9fff\nff01-ff5e');
  expect(c).toEqual([[0x20, 0x7e], [0xa0, 0xff], [0x3000, 0x30ff], [0x4e00, 0x9fff], [0xff01, 0xff5e]]);
  expect(covers(c, 0x41)).toBe(true);
  expect(covers(c, 0x80)).toBe(false);
  expect(covers(c, 0x9fff)).toBe(true);
  expect(() => parseCoverage('zz')).toThrow();
});

test('文だけを取り出す(style・script・コメント・属性を除き、文字参照を読む)', () => {
  expect(textOf('<style>.a{content:"Ω"}</style><!-- Ω --><p class="Ω">a&amp;b&#x41;&#66;&nbsp;</p><script>Ω</script>').replace(/ /g, '')).toBe('a&bAB\u00a0');
});

test('空白・異体字セレクタは数えず、上限の数で切る', () => {
  const c = parseCoverage('20-7e');
  const html = `<p>a　️\u{e0100}‍${'ĀāĂ'}</p>`;
  expect(missingGlyphs(html, c, 2)).toEqual({ count: 3, codepoints: ['U+0100', 'U+0101'] });
  expect(missingGlyphs(html, null, 2)).toEqual({ count: 0, codepoints: [] });
});
