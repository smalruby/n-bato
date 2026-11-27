# syntax=docker/dockerfile:1
# n-bato の PDF を作る Lambda のイメージ(#22、docs/design/pdf-lambda.md 1.2)。
#   docker build --platform linux/amd64 -t n-bato-pdf-renderer lambda/pdf-renderer
# x86_64 にする(Lambda の関数と同じ。Chrome for Testing の Linux 版も x64 だけ)。
# Chromium は Google の Chrome for Testing の chrome-headless-shell(puppeteer-core が対応する版)。zip は SHA-256 で固定する。
#   @sparticuz/chromium をやめた: 143〜158 のどの版も、包みの勧めどおりに立ち上げても x86_64 の ubuntu・Lambda のイメージで
#   何も出さずに止まった。同じところで chrome-headless-shell はすぐ動いた(2026-11-27、#22 の CI の切り分け)。
# Lambda は root でない利用者で動くので、Chromium とフォントはだれでも読める・Chromium は動かせる権限にする。

# フォント: 本番の Rails(Dockerfile の ruby:*-slim、Debian)と同じ fonts-noto-cjk のファイルを使う
ARG RUBY_VERSION=4.0.10
FROM --platform=linux/amd64 docker.io/library/ruby:${RUBY_VERSION}-slim AS fonts
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y fonts-noto-cjk fontconfig && \
    mkdir -p /out && \
    cp /usr/share/fonts/opentype/noto/NotoSerifCJK-Regular.ttc /usr/share/fonts/opentype/noto/NotoSerifCJK-Bold.ttc \
       /usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc /usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc /out/ && \
    for f in /out/*.ttc; do fc-query --format='%{charset}\n' "$f"; done > /out/coverage.txt && \
    rm -rf /var/lib/apt/lists/*

# Chromium: Chrome for Testing の chrome-headless-shell を落として確かめる
FROM --platform=linux/amd64 docker.io/library/ruby:${RUBY_VERSION}-slim AS chromium
ARG CHROME_VERSION=158.0.8127.88
ARG CHROME_SHA256=63401333cc587645bfaeea7f0c90958b327d249251e23954a47f30112ca23d5b
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y ca-certificates curl unzip && \
    curl -sSfL -o /tmp/hs.zip "https://storage.googleapis.com/chrome-for-testing-public/${CHROME_VERSION}/linux64/chrome-headless-shell-linux64.zip" && \
    echo "${CHROME_SHA256}  /tmp/hs.zip" | sha256sum -c - && \
    unzip -q /tmp/hs.zip -d /tmp && \
    mv /tmp/chrome-headless-shell-linux64 /out && \
    echo "${CHROME_VERSION}" > /out/version.txt && \
    chmod -R a+rX /out && chmod 755 /out/chrome-headless-shell && \
    rm -rf /tmp/hs.zip /var/lib/apt/lists/*

# 組み立て: TypeScript を JS にする
FROM --platform=linux/amd64 public.ecr.aws/lambda/nodejs:22@sha256:468c53b1f8cdc6678e5377ccb87c73cf00005b0bad0ba1d03de8d89589b591f7 AS build
WORKDIR /build
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY tsconfig.json tsconfig.build.json config.json ./
COPY schema ./schema
COPY src ./src
COPY scripts ./scripts
COPY --from=fonts /out/ /build/fonts/
COPY --from=chromium /out/version.txt /build/chromium-version.txt
ARG RENDERER_BUILD=local
RUN npx tsc -p tsconfig.build.json && \
    RENDERER_BUILD=${RENDERER_BUILD} node dist/scripts/write-build-meta.js /build/fonts /build/chromium-version.txt /build/build.json && \
    chmod -R a+rX /build/fonts && \
    npm prune --omit=dev --no-audit --no-fund

# 動かすもの
FROM --platform=linux/amd64 public.ecr.aws/lambda/nodejs:22@sha256:468c53b1f8cdc6678e5377ccb87c73cf00005b0bad0ba1d03de8d89589b591f7
# chrome-headless-shell が読む .so(Amazon Linux 2023 の包み。ldd で足りないと出たもの)
RUN dnf install -y --nodocs nss nspr atk at-spi2-atk at-spi2-core dbus-libs libX11 libXcomposite libXdamage libXext libXfixes \
      libXrandr mesa-libgbm expat libxcb libxkbcommon systemd-libs alsa-lib && \
    dnf clean all && rm -rf /var/cache/dnf
COPY --from=chromium /out /opt/chromium
COPY --from=build /build/fonts /var/task/fonts
COPY fonts.conf /var/task/fonts/fonts.conf
COPY --from=build /build/build.json /var/task/build.json
COPY --from=build /build/node_modules /var/task/node_modules
COPY --from=build /build/dist /var/task/dist
COPY --from=build /build/package.json /var/task/package.json
ENV CHROMIUM_PATH=/opt/chromium/chrome-headless-shell \
    FONTCONFIG_PATH=/var/task/fonts \
    FONTCONFIG_FILE=/var/task/fonts/fonts.conf
CMD ["dist/src/handler.handler"]
