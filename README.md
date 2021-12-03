# My Nix flake

Nix flake for my dotfiles

## First time installation

```bash
nix registry add mypkgs github:stasjok/flake
nix profile install mypkgs
```

## Upgrade

```bash
nix profile upgrade defaultPackage.x86_64-linux
```
