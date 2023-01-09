# build
FROM bitwalker/alpine-elixir:1.14 as build

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
FROM alpine:3.16

ENV REPLACE_OS_VARS=true
ENV RELEASE_NODE=deuterium
RUN mkdir -p /opt/app
COPY --from=build /export/ /opt/app
RUN apk add libstdc++ libgcc ncurses-libs libexecinfo

EXPOSE 4369
ENTRYPOINT ["/opt/app/deutexrium/bin/deutexrium"]
CMD ["start"]
