defmodule SelfHostedInferenceCore.CrucibleArtifacts do
  @moduledoc """
  V5 Crucible artifact path conventions for hosted runtime gates.

  The runtime consumes the same artifact layout as `crucible_bumblebee` so
  standalone and hosted model execution can be compared directly.
  """

  alias CrucibleBumblebee.Artifacts

  @spec root(keyword()) :: Path.t()
  def root(opts \\ []), do: Artifacts.root(opts)

  @spec ensure_layout!(keyword()) :: Path.t()
  def ensure_layout!(opts \\ []), do: Artifacts.ensure_layout!(opts)

  @spec trace_path(String.t(), keyword()) :: Path.t()
  def trace_path(name, opts \\ []), do: Artifacts.trace_path("hosted_#{name}", opts)

  @spec capability_report_path(String.t(), keyword()) :: Path.t()
  def capability_report_path(name, opts \\ []) do
    Artifacts.capability_report_path("hosted_#{name}", opts)
  end

  @spec index_path(keyword()) :: Path.t()
  def index_path(opts \\ []), do: Artifacts.index_path(opts)

  @spec append_index!(map(), keyword()) :: Path.t()
  def append_index!(entry, opts \\ []), do: Artifacts.append_index!(entry, opts)
end
