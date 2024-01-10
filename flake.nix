{
  description = "echo-crud sample application";

  # Nixpkgs / NixOS version to use.
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-23.11";

  outputs = { self, nixpkgs }:
    let

      # Generate a user-friendly version number.
      version = builtins.substring 0 8 self.lastModifiedDate;

      # System types to support.
      supportedSystems =
        [ "x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];

      # Helper function to generate an attrset '{ x86_64-linux = f "x86_64-linux"; ... }'.
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Nixpkgs instantiated for supported system types.
      nixpkgsFor = forAllSystems (system:
        import nixpkgs {
          inherit system;
          overlays = [ (final: prev: { go = prev.go_1_21; }) ];
        });
    in {

      # Provide some binary packages for selected system types.
      packages = forAllSystems (system:
        let pkgs = nixpkgsFor.${system};
        in {
          default = pkgs.buildGo121Module {
            pname = "echo-crud";
            inherit version;
            src = ./.;
            vendorHash = null;
          };
        });

      nixosModules.default = { config, lib, pkgs, ... }:
        with lib;
        let cfg = config.lnlsn.services.echo-crud;
        in {
          options.lnlsn.services.echo-crud = {
            enable = mkEnableOption "Enable the Echo Crud service";

            logLevel = mkOption {
              type = with types; enum [ "DEBUG" "INFO" "ERROR" ];
              example = "DEBUG";
              default = "INFO";
              description = "log level for this application";
            };

            port = mkOption {
              type = types.port;
              default = 1323;
              description = "port to listen on";
            };

            package = mkOption {
              type = types.package;
              default = self.packages.${pkgs.system}.default;
              description =
                "package to use for this service (defaults to the one in the flake)";
            };
          };

          config = mkIf cfg.enable {
            systemd.services.echo-crud = {
              description = "Echo CRUD example";
              wantedBy = [ "multi-user.target" ];

              serviceConfig = {
                DynamicUser = "yes";
                # ExecStart = "${cfg.package}/bin/echo-crud --slog-level=${cfg.logLevel} --addr=:${toString cfg.port}";
                ExecStart = "${cfg.package}/bin/echo-crud";
                Restart = "on-failure";
                RestartSec = "5s";
              };
            };
          };
        };

      devShells.default = forAllSystems (system:
        let pkgs = nixpkgsFor.${system};
        in with pkgs;
        mkShell {
          buildInputs = [ go_1_21 gotools go-tools gopls nixpkgs-fmt ];
        });

      checks.x86_64-linux = let pkgs = nixpkgs.legacyPackages.x86_64-linux;
      in {
        basic = pkgs.nixosTest ({
          name = "Echo CRUD";
          nodes.default = { config, pkgs, ... }: {
            imports = [ self.nixosModules.default ];
            lnlsn.services.echo-crud.enable = true;
          };
          testScript = ''
            start_all()

            default.wait_for_unit("echo-crud.service")
            print(default.wait_until_succeeds(
              curl -X POST \
                -H 'Content-Type: application/json' \
                -d '{"name":"Joe Smith"}' \
                localhost:1323/users
            ))
          '';
        });
      };
    };
}
