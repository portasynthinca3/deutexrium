#!/usr/bin/env sh

iex --erl "-pa epmd_docker/ebin -epmd_module epmd_docker -setcookie deutexrium -sname shell" --remsh deuterium@$1
