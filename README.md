# Frog Linux

Frog Linux is a fancy and opinionated reskin of Arch Linux running on the
CachyOS kernel.

It is basically Arch with KDE Plasma, Calamares, some defaults I like, and more
frog stuff than strictly necessary. It is not trying to reinvent Linux.

## Building

You need Docker or Podman, then run:

```sh
./scripts/build-local.sh
```

Or `./scripts/build-local.ps1` on Windows. The ISO ends up in `output/`.

That is pretty much it.