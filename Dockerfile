# build
FROM elixir:1.16-otp-25-alpine as build

COPY config config
COPY lib lib
COPY priv priv
COPY mix.exs mix.exs
COPY mix.lock mix.lock
COPY .git .git

RUN apk add musl-dev build-base git
RUN apk add libexecinfo-dev --repository=https://dl-cdn.alpinelinux.org/alpine/v3.12/main
#                           ^^^^ BAD!!!
RUN export MIX_ENV=prod && \
    rm -rf _build && \
    mix deps.get && \
    mix release

RUN mkdir /export && \
    cp -r _build/prod/rel/deutexrium/ /export

# deploy
FROM alpine:3

ENV REPLACE_OS_VARS=true
ENV RELEASE_NODE=deuterium
RUN mkdir -p /opt/app
COPY --from=build /export/ /opt/app

RUN apk add \
    libstdc++ libgcc ncurses-libs \ 
    imagemagick \
    font-noto ttf-linux-libertine
RUN apk add libexecinfo --repository=https://dl-cdn.alpinelinux.org/alpine/v3.12/main
#                       ^^^^ BAD!!!

RUN printf "-kernel inet_dist_listen_min 25565 inet_dist_listen_max 25565 +spp true" > vm.args
ENV RELEASE_VM_ARGS=vm.args

EXPOSE 4369
EXPOSE 25565
EXPOSE 4040
VOLUME ["/var/deutexrium"]
ENTRYPOINT ["/opt/app/deutexrium/bin/deutexrium"]
CMD ["start"]
