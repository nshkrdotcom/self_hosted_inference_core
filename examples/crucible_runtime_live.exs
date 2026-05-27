if System.get_env("CRUCIBLE_LIVE_MODEL") in ["1", "true"] do
  IO.inspect(%{ok: false, example: "crucible_runtime_live", reason: :live_model_not_configured})
else
  IO.inspect(%{ok: true, example: "crucible_runtime_live", skipped: true, reason: :live_not_enabled})
end
