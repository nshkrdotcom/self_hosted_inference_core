defmodule SelfHostedInferenceCore.MixProject do
  use Mix.Project

  def project do
    [
      app: :self_hosted_inference_core,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      description:
        "Core Elixir primitives for building reliable self-hosted inference clients, provider adapters, transport boundaries, and operational controls for private AI runtimes.",
      package: package(),
      docs: docs(),
      source_url: "https://github.com/nshkrdotcom/self_hosted_inference_core",
      homepage_url: "https://github.com/nshkrdotcom/self_hosted_inference_core",
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      name: "self_hosted_inference_core",
      licenses: ["MIT"],
      links: %{
        "Changelog" =>
          "https://github.com/nshkrdotcom/self_hosted_inference_core/blob/master/CHANGELOG.md",
        "GitHub" => "https://github.com/nshkrdotcom/self_hosted_inference_core"
      },
      files: [
        "assets/*.svg",
        "CHANGELOG.md",
        "LICENSE",
        "README.md",
        "lib",
        "mix.exs"
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_extras: [
        Guides: ["README.md"],
        Project: ["CHANGELOG.md", "LICENSE"]
      ]
    ]
  end
end
