%{
  deps: %{
    execution_plane: %{
      path: "../execution_plane/core/execution_plane",
      github: %{
        repo: "nshkrdotcom/execution_plane",
        branch: "main",
        subdir: "core/execution_plane"
      },
      hex: "~> 0.3.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    execution_plane_process: %{
      path: "../execution_plane/runtimes/execution_plane_process",
      github: %{
        repo: "nshkrdotcom/execution_plane",
        branch: "main",
        subdir: "runtimes/execution_plane_process"
      },
      hex: "~> 0.3.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    crucible_signal: %{
      path: "../../North-Shore-AI/crucible_signal",
      github: %{repo: "North-Shore-AI/crucible_signal", branch: "main"},
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    crucible_tap: %{
      path: "../../North-Shore-AI/crucible_tap",
      github: %{repo: "North-Shore-AI/crucible_tap", branch: "main"},
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    crucible_signal_trace: %{
      path: "../../North-Shore-AI/crucible_signal_trace",
      github: %{repo: "North-Shore-AI/crucible_signal_trace", branch: "main"},
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    crucible_provider_contracts: %{
      path: "../../North-Shore-AI/crucible_provider_contracts",
      github: %{repo: "North-Shore-AI/crucible_provider_contracts", branch: "main"},
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    }
  }
}
