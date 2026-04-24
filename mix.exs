defmodule SelfHostedInferenceCore.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/self_hosted_inference_core"
  @homepage_url "https://hex.pm/packages/self_hosted_inference_core"
  @execution_plane_contracts_version "~> 0.1.0"
  @execution_plane_local_version "~> 0.1.0"
  @execution_plane_process_version "~> 0.1.0"

  def project do
    [
      app: :self_hosted_inference_core,
      name: "SelfHostedInferenceCore",
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description:
        "Service-runtime kernel for self-hosted inference backends, owning readiness, health, lease reuse, and endpoint publication above the transport seam.",
      package: package(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: @homepage_url,
      dialyzer: dialyzer(),
      deps: deps()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :inets, :ssl],
      mod: {SelfHostedInferenceCore.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      execution_plane_contracts_dep(),
      execution_plane_local_dep(),
      execution_plane_process_dep(),
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
    ]
  end

  defp execution_plane_contracts_dep do
    case execution_plane_workspace_dep_path("core/execution_plane_contracts") do
      nil -> {:execution_plane_contracts, @execution_plane_contracts_version}
      path -> {:execution_plane_contracts, path: path}
    end
  end

  defp execution_plane_local_dep do
    case execution_plane_workspace_dep_path("placements/execution_plane_local") do
      nil -> {:execution_plane_local, @execution_plane_local_version}
      path -> {:execution_plane_local, path: path}
    end
  end

  defp execution_plane_process_dep do
    case execution_plane_workspace_dep_path("runtimes/execution_plane_process") do
      nil -> {:execution_plane_process, @execution_plane_process_version}
      path -> {:execution_plane_process, path: path}
    end
  end

  defp execution_plane_workspace_dep_path(relative_child_path) do
    configured_root =
      case System.get_env("EXECUTION_PLANE_PATH") do
        nil -> "../execution_plane"
        "" -> "../execution_plane"
        configured -> configured
      end

    configured_root
    |> Path.join(relative_child_path)
    |> workspace_dep_path("SELF_HOSTED_INFERENCE_CORE_HEX_DEPS")
  end

  defp workspace_dep_path(configured_path, force_hex_env) do
    if prefer_workspace_paths?(force_hex_env) do
      path = Path.expand(configured_path, __DIR__)
      if File.dir?(path), do: path
    end
  end

  defp prefer_workspace_paths?(force_hex_env) do
    workspace_paths_forced?(force_hex_env) or
      (not release_deps_forced?(force_hex_env) and not Enum.member?(Path.split(__DIR__), "deps"))
  end

  defp release_deps_forced?(force_hex_env) do
    force_hex_deps?(force_hex_env) or
      Enum.any?(System.argv(), &(&1 in ["hex.build", "hex.publish"]))
  end

  defp workspace_paths_forced?(force_hex_env) do
    not force_hex_deps?(force_hex_env) and
      System.get_env("FORCE_WORKSPACE_PATH_DEPS") in ["1", "true", "TRUE", "yes", "YES"]
  end

  defp force_hex_deps?(force_hex_env) do
    System.get_env(force_hex_env) in ["1", "true", "TRUE", "yes", "YES"]
  end

  defp package do
    [
      name: "self_hosted_inference_core",
      licenses: ["MIT"],
      links: %{
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
        "GitHub" => @source_url,
        "Hex" => @homepage_url,
        "HexDocs" => "https://hexdocs.pm/self_hosted_inference_core"
      },
      files: [
        "assets/*.svg",
        "CHANGELOG.md",
        "LICENSE",
        "README.md",
        ".formatter.exs",
        "lib",
        "mix.exs"
      ]
    ]
  end

  defp docs do
    [
      main: "overview",
      source_ref: "v#{@version}",
      homepage_url: @homepage_url,
      source_url: @source_url,
      logo: "assets/self_hosted_inference_core.svg",
      assets: %{"assets" => "assets"},
      extras: [
        "README.md": [title: "Overview", filename: "overview"],
        "guides/architecture.md": [title: "Architecture"],
        "guides/backend_packages.md": [title: "Backend Packages"],
        "guides/ollama_attach.md": [title: "Ollama Attach"],
        "guides/runtime_registry.md": [title: "Runtime Registry"],
        "guides/startup_kinds.md": [title: "Startup Kinds"],
        "examples/README.md": [title: "Examples", filename: "examples"],
        "CHANGELOG.md": [title: "Changelog"],
        LICENSE: [title: "License"]
      ],
      groups_for_extras: [
        "Project Overview": ["README.md"],
        Guides: [
          "guides/architecture.md",
          "guides/backend_packages.md",
          "guides/ollama_attach.md",
          "guides/runtime_registry.md",
          "guides/startup_kinds.md"
        ],
        Examples: ["examples/README.md"],
        "Project Reference": ["CHANGELOG.md", "LICENSE"]
      ],
      groups_for_modules: [
        "Public API": [
          SelfHostedInferenceCore,
          SelfHostedInferenceCore.Backend,
          SelfHostedInferenceCore.Ollama,
          SelfHostedInferenceCore.Simulation
        ],
        Contracts: [
          SelfHostedInferenceCore.InstanceSpec,
          SelfHostedInferenceCore.EndpointDescriptor,
          SelfHostedInferenceCore.BackendManifest,
          SelfHostedInferenceCore.ConsumerManifest,
          SelfHostedInferenceCore.CompatibilityResult,
          SelfHostedInferenceCore.LeaseRef,
          SelfHostedInferenceCore.Ollama.AttachSpec,
          SelfHostedInferenceCore.Simulation.Manifest
        ],
        "Runtime Types": [
          SelfHostedInferenceCore.RuntimeSnapshot,
          SelfHostedInferenceCore.Backend.StartupPlan,
          SelfHostedInferenceCore.Backend.TransportPlan
        ]
      ],
      formatters: ["html", "epub", "markdown"]
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:mix, :ex_unit],
      plt_core_path: "priv/plts/core",
      plt_local_path: "priv/plts",
      flags: [:error_handling, :underspecs]
    ]
  end
end
