{ inputs, pkgs, ... }:
let
  system = pkgs.system;

  aiJail = inputs.ai-jail.packages.${system}.default;
  aiMemory = inputs.ai-memory.packages.${system}.default;
  codex = inputs.codex.packages.${system}.default;

  agentSession = pkgs.writeShellApplication {
    name = "pc-agent-session";

    runtimeInputs = [
      aiJail
      aiMemory
      codex
      pkgs.coreutils
      pkgs.git
      pkgs.gh
      pkgs.jq
      pkgs.nodejs_24
      pkgs.unzip
      pkgs.zip
    ];

    text = ''
      set -euo pipefail

      project="''${1:-/home/agent/Dev}"
      if [ "$#" -gt 0 ]; then
        shift
      fi

      project="$(realpath -e -- "$project")"
      case "$project" in
        /home/agent/Dev|/home/agent/Dev/*|/home/felipe/Dev|/home/felipe/Dev/*)
          ;;
        *)
          echo "Projeto recusado: $project" >&2
          echo "Use um projeto em /home/felipe/Dev ou /home/agent/Dev." >&2
          exit 2
          ;;
      esac

      cd "$project"

      exec ai-jail \
        --network \
        --agent-state \
        --deny-path '.env' \
        --deny-path '.env.local' \
        --deny-path '.env.*.local' \
        --deny-path 'credentials.json' \
        --deny-path 'secrets/**' \
        codex "$@"
    '';
  };

  launcher = pkgs.writeShellApplication {
    name = "agente";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.sudo
    ];

    text = ''
      set -euo pipefail

      project="''${1:-$PWD}"
      if [ "$#" -gt 0 ]; then
        shift
      fi

      exec sudo -u agent -H ${agentSession}/bin/pc-agent-session "$project" "$@"
    '';
  };
in
{
  environment.systemPackages = [
    launcher
    agentSession
    aiJail
    aiMemory
    codex
  ];

  security.sudo.extraRules = [
    {
      users = [ "felipe" ];
      runAs = "agent";
      commands = [
        {
          command = "${agentSession}/bin/pc-agent-session";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  systemd.services.ai-memory = {
    description = "ai-memory for the isolated Codex account";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];

    environment = {
      HOME = "/home/agent";
    };

    preStart = ''
      install -d -m 0700 /home/agent/.config/ai-memory
      install -d -m 0700 /home/agent/.local/share/ai-memory

      if [ ! -f /home/agent/.config/ai-memory/config.toml ]; then
        ${aiMemory}/bin/ai-memory \
          --data-dir /home/agent/.local/share/ai-memory \
          --config /home/agent/.config/ai-memory/config.toml \
          init
      fi
    '';

    script = ''
      exec ${aiMemory}/bin/ai-memory \
        --data-dir /home/agent/.local/share/ai-memory \
        --config /home/agent/.config/ai-memory/config.toml \
        serve --transport http
    '';

    serviceConfig = {
      User = "agent";
      Group = "pcsetup-agent";
      Restart = "on-failure";
      RestartSec = "5s";
      NoNewPrivileges = true;
      PrivateTmp = true;
    };
  };

  systemd.services.ai-memory-codex-integration = {
    description = "Configure ai-memory integration for Codex";
    wantedBy = [ "multi-user.target" ];
    after = [ "ai-memory.service" ];
    requires = [ "ai-memory.service" ];

    environment = {
      HOME = "/home/agent";
    };

    script = ''
      ${aiMemory}/bin/ai-memory \
        --data-dir /home/agent/.local/share/ai-memory \
        --config /home/agent/.config/ai-memory/config.toml \
        install-mcp --client codex --apply

      ${aiMemory}/bin/ai-memory \
        --data-dir /home/agent/.local/share/ai-memory \
        --config /home/agent/.config/ai-memory/config.toml \
        install-hooks --agent codex --apply
    '';

    serviceConfig = {
      Type = "oneshot";
      User = "agent";
      Group = "pcsetup-agent";
      NoNewPrivileges = true;
    };
  };
}
