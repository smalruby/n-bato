# syntax=docker/dockerfile:1
# n-bato の PDF を作る Lambda のイメージ(#22、docs/design/pdf-lambda.md 1.2)。
#   docker build --platform linux/amd64 -t n-bato-pdf-renderer lambda/pdf-renderer
# x86_64 にする: @sparticuz/chromium の npm の包みに入っているのは x64 だけ。
# Lambda は root でない利用者で動くので、Chromium とフォントはだれでも読める・Chromium は動かせる権限にする(包みが取り出すと 0700 になる)。

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

# 組み立て: TypeScript を JS にし、Chromium を取り出しておく
FROM --platform=linux/amd64 public.ecr.aws/lambda/nodejs:22@sha256:468c53b1f8cdc6678e5377ccb87c73cf00005b0bad0ba1d03de8d89589b591f7 AS build
WORKDIR /build
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY tsconfig.json tsconfig.build.json config.json ./
COPY schema ./schema
COPY src ./src
COPY scripts ./scripts
COPY --from=fonts /out/ /build/fonts/
ARG RENDERER_BUILD=local
RUN npx tsc -p tsconfig.build.json && \
    AWS_EXECUTION_ENV=AWS_Lambda_nodejs22.x node dist/scripts/extract-chromium.js /build/chromium && \
    RENDERER_BUILD=${RENDERER_BUILD} node dist/scripts/write-build-meta.js /build/fonts /build/chromium/version.txt /build/build.json && \
    chmod -R a+rX /build/chromium /build/fonts && chmod 755 /build/chromium/chromium && \
    npm prune --omit=dev --no-audit --no-fund

# 動かすもの
FROM --platform=linux/amd64 public.ecr.aws/lambda/nodejs:22@sha256:468c53b1f8cdc6678e5377ccb87c73cf00005b0bad0ba1d03de8d89589b591f7
COPY --from=build /build/chromium /opt/chromium
COPY --from=build /build/fonts /var/task/fonts
COPY fonts.conf /var/task/fonts/fonts.conf
COPY --from=build /build/build.json /var/task/build.json
COPY --from=build /build/node_modules /var/task/node_modules
COPY --from=build /build/dist /var/task/dist
COPY --from=build /build/package.json /var/task/package.json
ENV CHROMIUM_PATH=/opt/chromium/chromium \
    LD_LIBRARY_PATH=/opt/chromium/lib:/opt/chromium:/var/lang/lib:/lib64:/usr/lib64:/var/runtime:/var/runtime/lib:/var/task:/var/task/lib:/opt/lib \
    FONTCONFIG_PATH=/var/task/fonts \
    FONTCONFIG_FILE=/var/task/fonts/fonts.conf
CMD ["dist/src/handler.handler"]
