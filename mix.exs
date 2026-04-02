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
        "Core Elixir primitives for building reliable self-hosted inference clients, provider adapters, transport boundaries, and operational controls for private AI runtimes.",
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
      extra_applications: [:logger],
      mod: {SelfHostedInferenceCore.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      local_or_hex_dep(
        :external_runtime_transport,
        "~> 0.1.0",
        "../external_runtime_transport"
      ),
      local_or_hex_dep(:jason, "~> 1.4", "../external_runtime_transport/deps/jason",
        override: true
      ),
      local_or_hex_dep(
        :erlexec,
        "~> 2.2",
        "../external_runtime_transport/deps/erlexec",
        override: true
      ),
      local_or_hex_dep(:erlex, "~> 0.2", "../external_runtime_transport/deps/erlex",
        override: true
      ),
      local_or_hex_dep(:zoi, "~> 0.14", "../external_runtime_transport/deps/zoi", override: true),
      local_or_hex_dep(:bunt, "~> 1.0", "../external_runtime_transport/deps/bunt", override: true),
      local_or_hex_dep(
        :file_system,
        "~> 1.1",
        "../external_runtime_transport/deps/file_system",
        override: true
      ),
      local_or_hex_dep(
        :earmark_parser,
        "~> 1.4.44",
        "../external_runtime_transport/deps/earmark_parser",
        override: true,
        only: :dev,
        runtime: false
      ),
      local_or_hex_dep(
        :makeup,
        "~> 1.2",
        "../external_runtime_transport/deps/makeup",
        override: true,
        only: :dev,
        runtime: false
      ),
      local_or_hex_dep(
        :makeup_elixir,
        "~> 1.0",
        "../external_runtime_transport/deps/makeup_elixir",
        override: true,
        only: :dev,
        runtime: false
      ),
      local_or_hex_dep(
        :makeup_erlang,
        "~> 1.0",
        "../external_runtime_transport/deps/makeup_erlang",
        override: true,
        only: :dev,
        runtime: false
      ),
      local_or_hex_dep(
        :nimble_parsec,
        "~> 1.4",
        "../external_runtime_transport/deps/nimble_parsec",
        override: true
      ),
      local_or_hex_dep(
        :ex_doc,
        "~> 0.40",
        "../external_runtime_transport/deps/ex_doc",
        override: true,
        only: :dev,
        runtime: false
      ),
      local_or_hex_dep(
        :credo,
        "~> 1.7",
        "../external_runtime_transport/deps/credo",
        override: true,
        only: [:dev, :test],
        runtime: false
      ),
      local_or_hex_dep(
        :dialyxir,
        "~> 1.4",
        "../external_runtime_transport/deps/dialyxir",
        override: true,
        only: :dev,
        runtime: false
      )
    ]
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
          "guides/runtime_registry.md",
          "guides/startup_kinds.md"
        ],
        Examples: ["examples/README.md"],
        "Project Reference": ["CHANGELOG.md", "LICENSE"]
      ],
      groups_for_modules: [
        "Public API": [
          SelfHostedInferenceCore,
          SelfHostedInferenceCore.Backend
        ],
        Contracts: [
          SelfHostedInferenceCore.InstanceSpec,
          SelfHostedInferenceCore.EndpointDescriptor,
          SelfHostedInferenceCore.BackendManifest,
          SelfHostedInferenceCore.ConsumerManifest,
          SelfHostedInferenceCore.CompatibilityResult,
          SelfHostedInferenceCore.LeaseRef
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

  defp local_or_hex_dep(app, version, relative_path, opts \\ []) do
    path = Path.expand(relative_path, __DIR__)

    if local_dep_path?(path) do
      {app, Keyword.put(opts, :path, path)}
    else
      {app, version, opts}
    end
  end

  defp local_dep_path?(path) do
    File.exists?(Path.join(path, "mix.exs")) or File.exists?(Path.join(path, "rebar.config"))
  end
end
