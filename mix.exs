# `build_support/` is not shipped in the published package, so its absence is
# how this file knows it is running inside a consumer's deps/ rather than in a
# source checkout. Guard on the file, not on a directory shape: a shape test
# breaks when the repo is vendored at a different depth or used as a git dep.
workspace_helper = Path.expand("build_support/dependency_sources.exs", __DIR__)

if File.regular?(workspace_helper) and not Code.ensure_loaded?(DependencySources) do
  Code.require_file(workspace_helper)
end

defmodule SelfHostedInferenceCore.MixProject do
  use Mix.Project

  @workspace_checkout? File.regular?(Path.expand("build_support/dependency_sources.exs", __DIR__))

  @version "0.2.0"
  @source_url "https://github.com/nshkrdotcom/self_hosted_inference_core"
  @homepage_url "https://hex.pm/packages/self_hosted_inference_core"

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
      deps: deps(),
      aliases: aliases()
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
      workspace_dep(:execution_plane, "~> 0.3.0"),
      workspace_dep(:execution_plane_process, "~> 0.3.0"),
      workspace_dep(:crucible_provider_contracts, "~> 0.1.0"),
      workspace_dep(:crucible_signal, "~> 0.1.0"),
      workspace_dep(:crucible_signal_trace, "~> 0.1.0"),
      workspace_dep(:crucible_tap, "~> 0.1.0"),
      {:telemetry, "~> 1.4.2"},
      {:ex_doc, "~> 0.40.3", only: :dev, runtime: false},
      {:credo, "~> 1.7.19", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4.7", only: :dev, runtime: false}
    ]
  end

  # In a source checkout the registry decides the source (path first). In a
  # published package there is no registry, and the requirement stated here is
  # the whole answer.
  defp workspace_dep(app, hex_requirement, opts \\ []) do
    if @workspace_checkout? do
      apply(DependencySources, :dep, [app, __DIR__, opts])
    else
      if opts == [], do: {app, hex_requirement}, else: {app, hex_requirement, opts}
    end
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
        "build_support",
        "examples",
        "guides",
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
        "guides/crucible_runtime.md": [title: "Crucible Runtime"],
        "guides/real_model_live_gates.md": [title: "Real Model Live Gates"],
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
          "guides/crucible_runtime.md",
          "guides/real_model_live_gates.md",
          "guides/startup_kinds.md"
        ],
        Examples: ["examples/README.md"],
        "Project Reference": ["CHANGELOG.md", "LICENSE"]
      ],
      groups_for_modules: [
        "Public API": [
          SelfHostedInferenceCore,
          SelfHostedInferenceCore.CrucibleRuntime,
          SelfHostedInferenceCore.Health,
          SelfHostedInferenceCore.Readiness,
          SelfHostedInferenceCore.Backend,
          SelfHostedInferenceCore.Ollama,
          SelfHostedInferenceCore.Simulation
        ],
        Contracts: [
          SelfHostedInferenceCore.InstanceSpec,
          SelfHostedInferenceCore.AdapterRef,
          SelfHostedInferenceCore.RouteLogits,
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

  defp aliases do
    [
      ci: [
        "deps.get",
        "format --check-formatted",
        "compile --warnings-as-errors",
        "cmd mix test",
        "credo --strict",
        "dialyzer --format short",
        "docs"
      ]
    ]
  end
end
