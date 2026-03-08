defmodule Kerto.Plugin do
  @moduledoc """
  Behaviour for passive learning plugins.

  Plugins scan external sources (agent logs, conversation state, etc.)
  and emit occurrences that feed the standard ingestion pipeline.

  Each plugin must identify itself and implement a scan that returns
  occurrences found since the given sync point (ULID timestamp).
  """

  alias Kerto.Ingestion.Occurrence

  @doc "Human-readable agent name (e.g. \"claude\", \"logs\")."
  @callback agent_name() :: String.t()

  @doc """
  Scan for new occurrences since `last_sync` (a ULID string, or nil for first scan).

  Returns a list of occurrences to ingest. The PluginRunner will
  call `Engine.ingest/2` for each returned occurrence.
  """
  @callback scan(last_sync :: String.t() | nil) :: [Occurrence.t()]
end
