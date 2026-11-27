// 分かっている失敗(docs/design/pdf-lambda.md 4.4)。Lambda は例外を投げずに status: "error" で返す。
// retryable は「ジョブがやり直してよいか」の目安。分類(transient・heavy など)と回数は Rails のジョブが決める。
export const ERROR_CODES = {
  INVALID_REQUEST: false,
  UNSUPPORTED_PROTOCOL: false,
  DEADLINE_EXCEEDED: false,
  INPUT_NOT_FOUND: true,
  INPUT_CHECKSUM_MISMATCH: true,
  INPUT_TOO_LARGE: false,
  TOO_MANY_PAGES: false,
  OUTPUT_TOO_LARGE: false,
  RENDER_TIMEOUT: true,
  BROWSER_CRASHED: true,
  BROWSER_LAUNCH_FAILED: true,
  S3_ERROR: true,
  INTERNAL: false,
} as const;

export type ErrorCode = keyof typeof ERROR_CODES;

// detail に入れるのは例外の種類の名前か、決まった短い文だけ(中身・URL・ファイルの名前を入れない。2.4)
export class RenderError extends Error {
  constructor(
    readonly code: ErrorCode,
    readonly detail: string,
  ) {
    super(code);
    this.name = 'RenderError';
  }
}

export const errorKind = (e: unknown): string => {
  if (e && typeof e === 'object') {
    const name = (e as { name?: unknown }).name;
    if (typeof name === 'string' && /^[A-Za-z0-9_.]{1,80}$/.test(name)) return name;
    const ctor = (e as object).constructor?.name;
    if (ctor && /^[A-Za-z0-9_.]{1,80}$/.test(ctor)) return ctor;
  }
  return typeof e;
};
