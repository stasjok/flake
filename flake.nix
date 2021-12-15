{
  description = "Nix flake for my dotfiles";

  inputs = {

    nixos-21-05 = {
      type = "github";
      owner = "NixOS";
      repo = "nixpkgs";
      # Released on 2021-11-29 21:50:19 via https://hydra.nixos.org/eval/1726412
      rev = "2553aee74fed8c2205a4aeb3ffd206ca14ede60f";
      narHash = "sha256-fkOqSkfOkl8tqxDd+zJU4kAgyLXp/ouaP+U9gpjEZZs=";
    };

    nixos-21-11 = {
      type = "github";
      owner = "NixOS";
      repo = "nixpkgs";
      # Released on 2021-11-29 16:25:56 via https://hydra.nixos.org/eval/1726250
      rev = "8e6b3914626900ad8f465c3e3541edbb86a95d41";
      narHash = "sha256-gLVjBxvI5tLMl2BzbGnpgVppnAxTrkrVeCyBQ5N6VQs=";
    };

    nixpkgs-unstable = {
      type = "github";
      owner = "NixOS";
      repo = "nixpkgs";
      # Hydra evaluation https://hydra.nixos.org/eval/1727142 (2021-12-02 11:53:30)
      rev = "56cbe42f1668338d05febfbb866e32f2c865609a";
      narHash = "sha256-iZ+rgyRx3JVyylXYxSyW01liDWEn+O8cKnin6cMzOFU=";
    };

  };

  outputs =
    { self
    , nixos-21-05
    , nixos-21-11
    , nixpkgs-unstable
    } @ args:

    let
      # Current stable nixpkgs
      current-version = nixos-21-11;
      # Nixpkgs legacyPackages
      stable-21-05 = nixos-21-05.legacyPackages.x86_64-linux;
      stable-21-11 = nixos-21-11.legacyPackages.x86_64-linux;
      unstable = nixpkgs-unstable.legacyPackages.x86_64-linux;
      stable-current = current-version.legacyPackages.x86_64-linux;
      # Nixpkgs lib
      lib = current-version.lib;
      # Shortcuts
      inherit (stable-current)
        fetchFromGitHub
        ;
    in
    {
      # Provide all upstream packages and lib
      legacyPackages.x86_64-linux = stable-current;
      inherit lib;

      # Provide a package for nix profile with all my packages combined
      defaultPackage.x86_64-linux = stable-current.buildEnv {
        name = "nix-profile-${self.lastModifiedDate or "1"}";
        paths = builtins.attrValues self.packages.x86_64-linux;
        extraOutputsToInstall = [ "man" ];
        pathsToLink = [
          "/bin"
          "/share/man"
          "/share/nixpkgs"
          "/share/fish/vendor_completions.d"
          "/share/fish/vendor_conf.d"
          "/share/fish/vendor_functions.d"
        ];
        buildInputs = [ stable-current.man-db ];

        postBuild = ''
          mandb --no-straycats $out/share/man
          whatis --manpath=$out/share/man --wildcard '*' | sort > $out/share/man/whatis
          rm --dir $out/share/man/index.* $out/share/man/cat*
        '';
      };

      # My packages separately
      packages.x86_64-linux = rec {
        # Packages from current stable
        nix = stable-current.nix_2_4;
        inherit (stable-current)
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
          sumneko-lua-language-server
          ;
        inherit (unstable.nodePackages)
          pyright
          ;

        # Overrided packages
        neovimWithPlugins =
          with unstable; let
            configure.packages.nix.start = with vimPlugins; [
              packer-nvim
              # Remove dependencies because they are managed by packer
              (telescope-fzf-native-nvim.overrideAttrs (_: { dependencies = [ ]; }))
              # TODO: build grammars using nvim-treesitter lock file
              (linkFarm "nvim-treesitter-parsers" [{
                name = "parser";
                path = tree-sitter.withPlugins (_: tree-sitter.allGrammars);
              }])
            ];
            vimPackDir = vimUtils.packDir configure.packages;
            nvimDataDir = linkFarm "nvim-data-dir" [{ name = "nvim/site"; path = vimPackDir; }];
            nvimWrapperDataDirArgs = [ "--set" "XDG_DATA_DIRS" nvimDataDir ];
            nvimWrapperDisablePerlArgs = [
              "--add-flags"
              (lib.escapeShellArgs [ "--cmd" "let g:loaded_perl_provider=0" ])
            ];
            neovimConfig = neovimUtils.makeNeovimConfig {
              withPython3 = false;
              withRuby = false;
              inherit configure;
            };
            # Use vim-pack-dir as env, not as vimrc
            wrapNeovimArgs = neovimConfig // {
              wrapRc = false;
              wrapperArgs = neovimConfig.wrapperArgs ++ nvimWrapperDataDirArgs ++ nvimWrapperDisablePerlArgs;
            };
          in
          wrapNeovimUnstable neovim-unwrapped wrapNeovimArgs;

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

        rnix-lsp =
          let
            cargo = stable-current.cargo.override { inherit cacert; };
            fetchCargoTarball = stable-current.rustPlatform.fetchCargoTarball.override { inherit cargo; };
          in
          unstable.rnix-lsp.overrideAttrs (oldAttrs: rec {
            version = "2021-11-15+9462b0d";
            src = fetchFromGitHub {
              owner = "nix-community";
              repo = "rnix-lsp";
              rev = "9462b0d20325a06f7e43b5a0469ec2c92e60f5fe";
              sha256 = "0mhzm4k7jkrq8r06mi49i04zvg0j1j6b54aqwyy104k8l32802d5";
            };
            cargoDeps = fetchCargoTarball {
              inherit src;
              name = "rnix-lsp-${version}-vendor.tar.gz";
              hash = "sha256:0fpzmp5cnj3s1x5xnp2ffxkwlgyrmfmkgz0k23b2b0rpl94d1x17";
            };
          });

        cacert = stable-current.cacert.override {
          extraCertificateFiles = [ ./cacerts/absolutbank_root_2017.crt ];
        };

        # Reference input sources in order to avoid garbage collection
        sources =
          let
            inputs = removeAttrs args [ "self" ];
            nixpkgs-sources = lib.mapAttrsToList
              (name: value: { name = "share/nixpkgs/${name}"; path = value.outPath; })
              inputs;
          in
          stable-current.linkFarm "nixpkgs-sources" nixpkgs-sources;
      } // import ./node-packages/node-composition.nix { pkgs = stable-current; };
    };
}

