{
  description = "Nix flake for my dotfiles";

  inputs = {

    nixos-21-05 = {
      type = "github";
      owner = "NixOS";
      repo = "nixpkgs";
      # Released on 2022-01-10 11:30:04 via https://hydra.nixos.org/eval/1737315
      rev = "df123677560db3b0db7c19d71981b11091fbeaf6";
      narHash = "sha256-/7YwWbvkjinc4uu5aUQMRw3xAthhOVH/esm4tCXPzIQ=";
    };

    nixos-21-11 = {
      type = "github";
      owner = "NixOS";
      repo = "nixpkgs";
      # Released on 2022-01-11 12:33:23 via https://hydra.nixos.org/eval/1737543
      rev = "386234e2a61e1e8acf94dfa3a3d3ca19a6776efb";
      narHash = "sha256-6HkxR2WZsm37VoQS7jgp6Omd71iw6t1kP8bDbaqCDuI=";
    };

    nixpkgs-unstable = {
      type = "github";
      owner = "NixOS";
      repo = "nixpkgs";
      # Hydra evaluation https://hydra.nixos.org/eval/1737019 (2022-01-08 23:15:00)
      rev = "32356ce11b8cc5cc421b68138ae8c730cc8ad4a2";
      narHash = "sha256-aHoO6CpPLJK8hLkPJrpMnCRnj3YbfQZ7HNcXcnI83E0=";
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
          ansible-lint
          yamllint
          shellcheck
          shfmt
          stylua
          rnix-lsp
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

        ansibleWithMitogen =
          with stable-current.python3.pkgs; let
            # We need version 0.2 for ansible 2.9
            mitogen_0_2 = mitogen.overridePythonAttrs (oldAttrs: rec {
              version = "0.2.10";
              src = fetchFromGitHub {
                owner = "mitogen-hq";
                repo = "mitogen";
                rev = "v${version}";
                sha256 = "sha256-SFwMgK1IKLwJS8k8w/N0A/+zMmBj9EN6m/58W/e7F4Q=";
              };
            });
          in
          ansible.overridePythonAttrs (oldAttrs: {
            makeWrapperArgs = [
              "--suffix ANSIBLE_STRATEGY_PLUGINS : ${mitogen_0_2}/${python.sitePackages}/ansible_mitogen"
              "--set-default ANSIBLE_STRATEGY mitogen_linear"
            ];
            propagatedBuildInputs = oldAttrs.propagatedBuildInputs ++ [ mitogen_0_2 ];
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

