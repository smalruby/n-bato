import { pssKb } from '../src/memory';
describe('メモリの測り方', () => {
  it('PSS が読めないところでも 0 以上の数を返す', () => {
    expect(pssKb('self')).toBeGreaterThanOrEqual(0);
    expect(pssKb(999_999_999)).toBe(0);
  });
});
