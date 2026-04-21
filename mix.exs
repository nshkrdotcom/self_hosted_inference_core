defmodule SelfHostedInferenceCore.MixProject do
  use Mix.Project

  @version "0.1.0"
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
      execution_plane_dep(),
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
    ]
  end

  defp execution_plane_dep do
    resolve_local_or_git_dep(
      :execution_plane,
      "EXECUTION_PLANE_PATH",
      "../execution_plane",
      [github: "nshkrdotcom/execution_plane", branch: "main"],
      override: true
    )
  end

  defp resolve_local_or_git_dep(app, env_var, sibling_relative_path, fallback_opts, opts) do
    path =
      case System.get_env(env_var) do
        nil -> Path.expand(sibling_relative_path, __DIR__)
        "" -> Path.expand(sibling_relative_path, __DIR__)
        configured -> Path.expand(configured)
      end

    if File.dir?(path) do
      {app, Keyword.merge([path: path], opts)}
    else
      {app, Keyword.merge(fallback_opts, opts)}
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
          SelfHostedInferenceCore.Ollama
        ],
        Contracts: [
          SelfHostedInferenceCore.InstanceSpec,
          SelfHostedInferenceCore.EndpointDescriptor,
          SelfHostedInferenceCore.BackendManifest,
          SelfHostedInferenceCore.ConsumerManifest,
          SelfHostedInferenceCore.CompatibilityResult,
          SelfHostedInferenceCore.LeaseRef,
          SelfHostedInferenceCore.Ollama.AttachSpec
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
