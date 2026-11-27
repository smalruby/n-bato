// 旗の一覧そのものを固定する(足し忘れ・外し忘れを見つける。docs/design/pdf-lambda.md 3.2)
import { CHROMIUM_FLAGS, FORBIDDEN_FLAGS, chromiumFlags } from '../src/flags';

test('旗の一覧が決めたとおり', () => {
  expect(CHROMIUM_FLAGS).toMatchSnapshot();
});

test('通信の禁止を弱める旗が無い', () => {
  for (const f of FORBIDDEN_FLAGS) {
    expect(CHROMIUM_FLAGS.some((x) => x === f || x.startsWith(`${f}=`))).toBe(false);
  }
  expect(CHROMIUM_FLAGS).not.toContain('--disable-web-security');
  expect(CHROMIUM_FLAGS).not.toContain('--allow-running-insecure-content');
});

test('本番では環境変数で旗を変えられない', () => {
  expect(chromiumFlags({ PDF_FLAGS_ADD: '--single-process', PDF_FLAGS_REMOVE: '--no-sandbox' })).toEqual([...CHROMIUM_FLAGS]);
});

test('実験のときだけ足し引きでき、禁止の旗は足せない', () => {
  const flags = chromiumFlags({ PDF_EXPERIMENT: '1', PDF_FLAGS_ADD: '--single-process --js-flags=--max-old-space-size=96', PDF_FLAGS_REMOVE: '--disable-dev-shm-usage' });
  expect(flags).toContain('--single-process');
  expect(flags).toContain('--js-flags=--max-old-space-size=96');
  expect(flags).not.toContain('--disable-dev-shm-usage');
  expect(() => chromiumFlags({ PDF_EXPERIMENT: '1', PDF_FLAGS_ADD: '--disable-web-security' })).toThrow();
});
