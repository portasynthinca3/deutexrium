# build
FROM elixir:otp-24-alpine as build

COPY config config
COPY lib lib
COPY priv priv
COPY mix.exs mix.exs
COPY mix.lock mix.lock

RUN apk add build-base libexecinfo-dev
RUN export MIX_ENV=prod && \
    rm -rf _build && \
    mix deps.get && \
    mix release

RUN mkdir /export && \
    cp -r _build/prod/rel/deutexrium/ /export

# deploy
FROM elixir:otp-24-alpine

ENV REPLACE_OS_VARS=true
ENV RELEASE_NODE=deuterium
RUN mkdir -p /opt/app
COPY --from=build /export/ /opt/app

RUN apk add \
    libstdc++ libgcc ncurses-libs libexecinfo \ 
    imagemagick \
    ttf-noto ttf-linux-libertine

RUN printf "-kernel inet_dist_listen_min 25565 inet_dist_listen_max 25565 +spp" > vm.args
ENV RELEASE_VM_ARGS=vm.args

EXPOSE 4369
EXPOSE 25565
VOLUME ["/var/deutexrium"]
ENTRYPOINT ["/opt/app/deutexrium/bin/deutexrium"]
CMD ["start"]
