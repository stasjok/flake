# My Nix flake

Nix flake for my dotfiles

## First time installation

Add to Nix configuration file (`/etc/nix/nix.conf` or `$HOME/.config/nix.conf`):

```
experimental-features = nix-command flakes
```

then:

```bash
nix registry add mypkgs github:stasjok/flake
nix profile install mypkgs
```

## Upgrade

```bash
nix profile upgrade defaultPackage.x86_64-linux
```
