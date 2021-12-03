{
  description = "Nix flake for my dotfiles";

  inputs = {

    nixos-21-05 = {
      type = "github";
      owner = "NixOS";
      repo = "nixpkgs";
      # Released on 2021-11-29 21:50:19 via https://hydra.nixos.org/eval/1726412
      rev = "2553aee74fed8c2205a4aeb3ffd206ca14ede60f";
    };

    nixos-21-11 = {
      type = "github";
      owner = "NixOS";
      repo = "nixpkgs";
      # Released on 2021-11-29 16:25:56 via https://hydra.nixos.org/eval/1726250
      rev = "8e6b3914626900ad8f465c3e3541edbb86a95d41";
    };

    nixpkgs-unstable = {
      type = "github";
      owner = "NixOS";
      repo = "nixpkgs";
      # Released on 2021-11-29 20:21:59 via https://hydra.nixos.org/eval/1726352
      rev = "f366af7a1b3891d9370091ab03150d3a6ee138fa";
    };

    # Legacy sources from packages.nix
    nixpkgs-unstable-for-vimplugins = {
      type = "tarball";
      url = https://releases.nixos.org/nixpkgs/nixpkgs-21.11pre309670.253aecf69ed/nixexprs.tar.xz;
      narHash = "sha256-pDftXg89gm1k/ACrgeiyv3qhNCif9F6z/Jb33Za89t4=";
    };

    hurricanehrndz-nixcfg = {
      type = "github";
      owner = "hurricanehrndz";
      repo = "nixcfg";
      rev = "993b3d67315563bfc4f9000e8e2e1d96c7d06ffe";
      flake = false;
    };

  };

  outputs =
    { self
    , nixos-21-05
    , nixos-21-11
    , nixpkgs-unstable
    , nixpkgs-unstable-for-vimplugins
    , hurricanehrndz-nixcfg
    }:

    let
      # Nixpkgs
      stable-21-05 = nixos-21-05.legacyPackages.x86_64-linux;
      stable-21-11 = nixos-21-11.legacyPackages.x86_64-linux;
      unstable = nixpkgs-unstable.legacyPackages.x86_64-linux;
      vimplugins = nixpkgs-unstable-for-vimplugins.legacyPackages.x86_64-linux;
      stable-current = stable-21-11;
      # Shortcuts
      inherit (stable-current)
        fetchFromGitHub
        ;
    in
    {
      # Provide all upstream packages
      legacyPackages.x86_64-linux = stable-current;

      # Provide a package for nix profile with all my packages combined
      defaultPackage.x86_64-linux = stable-current.buildEnv {
        name = "nix-profile-${self.lastModifiedDate or "1"}";
        paths = builtins.attrValues self.packages.x86_64-linux;
        extraOutputsToInstall = [ "man" "doc" ];
        pathsToLink = [
          "/bin"
          "/share/man"
          "/share/doc"
          "/share/fish/vendor_completions.d"
          "/share/fish/vendor_conf.d"
          "/share/fish/vendor_functions.d"
          "/share/vim-plugins"
        ];
      };

      # My packages separately
      packages.x86_64-linux = {
        # Packages from current stable
        nix = stable-current.nix_2_4;
        inherit (stable-current)
          cacert
          bash
          fish
          tmux
          git
          gnupg
          exa
          bat
          fd
          ripgrep
          fzf
          delta
          python3
          black
          ansible_2_9
          ansible-lint
          yamllint
          shellcheck
          shfmt
          stylua
          ;
        inherit (stable-current.nodePackages)
          bash-language-server
          node2nix
          ;
        # Packages from unstable
        inherit (unstable)
          neovim-unwrapped
          sumneko-lua-language-server
          ;
        inherit (unstable.nodePackages)
          pyright
          ;

        packer-nvim = vimplugins.vimPlugins.packer-nvim.overrideAttrs (oldAttrs: {
          # I need to change package name, because packer does :packadd packer.nvim
          pname = "packer.nvim";
          version = "2021-09-04";
          src = fetchFromGitHub {
            owner = "wbthomason";
            repo = "packer.nvim";
            rev = "daec6c759f95cd8528e5dd7c214b18b4cec2658c";
            sha256 = "1mavf0rwrlvwd9bmxj1nnyd32jqrzn4wpiman8wpakf5dcn1i8gb";
          };
        });

        telescope-fzf-native-nvim = vimplugins.vimPlugins.telescope-fzf-native-nvim;

        nvim-treesitter-parsers = with stable-current; let
          nvim-ts-grammars = stable-current.callPackage "${hurricanehrndz-nixcfg}/nix/pkgs/nvim-ts-grammars" { };
        in
        linkFarm "nvim-treesitter-parsers" (
          lib.attrsets.mapAttrsToList
            (name: drv:
              {
                name =
                  "share/vim-plugins/nvim-treesitter-parsers/parser/"
                    + (lib.strings.removePrefix "tree-sitter-"
                    (lib.strings.removeSuffix "-grammar" name))
                    + stdenv.hostPlatform.extensions.sharedLibrary;
                path = "${drv}/parser.so";
              }
            )
            (removeAttrs nvim-ts-grammars.builtGrammars [
              "tree-sitter-elixir" # doesn't install (error in derivation)
              "tree-sitter-gdscript" # ABI version mismatch
              "tree-sitter-ocamllex" # ABI version mismatch
              "tree-sitter-swift" # ABI version mismatch
            ])
        );

        # We need version 0.2 for ansible 2.9
        mitogen = stable-current.python39Packages.mitogen.overrideAttrs (oldAttrs: rec {
          name = "python3.9-mitogen-${version}";
          version = "0.2.10";
          src = fetchFromGitHub {
            owner = "mitogen-hq";
            repo = "mitogen";
            rev = "v${version}";
            sha256 = "sha256-SFwMgK1IKLwJS8k8w/N0A/+zMmBj9EN6m/58W/e7F4Q=";
          };
        });

        rnix-lsp = unstable.rnix-lsp.overrideAttrs (oldAttrs: rec {
          version = "2021-11-15+9462b0d";
          src = fetchFromGitHub {
            owner = "nix-community";
            repo = "rnix-lsp";
            rev = "9462b0d20325a06f7e43b5a0469ec2c92e60f5fe";
            sha256 = "0mhzm4k7jkrq8r06mi49i04zvg0j1j6b54aqwyy104k8l32802d5";
          };
          cargoDeps = stable-current.rustPlatform.fetchCargoTarball {
            inherit src;
            name = "rnix-lsp-${version}-vendor.tar.gz";
            hash = "sha256:0fpzmp5cnj3s1x5xnp2ffxkwlgyrmfmkgz0k23b2b0rpl94d1x17";
          };
        });
      } // import ./node-packages/node-composition.nix { pkgs = stable-current; };

    };
}
