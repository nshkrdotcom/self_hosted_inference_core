Mix.Task.run("app.start")

alias SelfHostedInferenceCore.ConsumerManifest
alias SelfHostedInferenceCore.Ollama

root_url =
  System.get_env("OLLAMA_ROOT_URL") ||
    SelfHostedInferenceCore.Ollama.AttachSpec.default_root_url()

model_identity = System.get_env("OLLAMA_MODEL") || "llama3.2"

consumer =
  ConsumerManifest.new!(
    consumer: :jido_integration_req_llm,
    accepted_runtime_kinds: [:service],
    accepted_management_modes: [:externally_managed],
    accepted_protocols: [:openai_chat_completions],
    required_capabilities: %{streaming?: true},
    optional_capabilities: %{tool_calling?: :unknown},
    constraints: %{startup_kind: :attach_existing_service},
    metadata: %{example: :ollama_attach}
  )

:ok = Ollama.register_backend()

attach_spec = %{
  root_url: root_url,
  model_identity: model_identity,
  ready_timeout_ms: 5_000,
  readiness_interval_ms: 100,
  health_interval_ms: 1_000
}

with {:ok, first} <-
       Ollama.resolve_endpoint(
         attach_spec,
         consumer,
         owner_ref: "example-owner-a",
         ttl_ms: 30_000
       ),
     {:ok, second} <-
       Ollama.resolve_endpoint(
         attach_spec,
         consumer,
         owner_ref: "example-owner-b",
         ttl_ms: 30_000
       ) do
  IO.puts("First instance id:   #{first.instance.instance_id}")
  IO.puts("Second instance id:  #{second.instance.instance_id}")
  IO.puts("Endpoint:            #{first.endpoint.base_url}")
  IO.puts("Reused instance?:    #{inspect(second.reused?)}")
  IO.puts("Management mode:     #{inspect(first.endpoint.management_mode)}")
  IO.puts("Model identity:      #{first.endpoint.model_identity}")
  IO.puts("Lease refs differ?:  #{inspect(first.lease.lease_ref != second.lease.lease_ref)}")

  :ok = SelfHostedInferenceCore.stop_instance(first.instance.instance_id)

  {:ok, third} =
    Ollama.resolve_endpoint(
      attach_spec,
      consumer,
      owner_ref: "example-owner-c",
      ttl_ms: 30_000
    )

  IO.puts("Endpoint after stop: #{third.endpoint.base_url}")
  IO.puts("Reattached after stop?: #{inspect(third.instance.instance_id != nil)}")

  :ok = SelfHostedInferenceCore.release_lease(first.instance.instance_id, first.lease.lease_ref)
  :ok = SelfHostedInferenceCore.release_lease(second.instance.instance_id, second.lease.lease_ref)
  :ok = SelfHostedInferenceCore.release_lease(third.instance.instance_id, third.lease.lease_ref)
else
  {:error, reason} ->
    IO.puts("Failed to attach to Ollama: #{inspect(reason)}")

    IO.puts("""
    Ensure an external Ollama daemon is already running and the requested model is pulled.

      OLLAMA_ROOT_URL=#{root_url}
      OLLAMA_MODEL=#{model_identity}
    """)

    System.halt(1)
end
