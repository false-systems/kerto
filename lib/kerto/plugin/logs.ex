defmodule Kerto.Plugin.Logs do
  @moduledoc """
  Generic log reader plugin.

  Reads log files from configurable paths and extracts occurrences
  based on pattern matching. Useful for CI logs, build output, etc.
  """

  @behaviour Kerto.Plugin

  @impl true
  def agent_name, do: "logs"

  @impl true
  def scan(_last_sync) do
    # TODO: Implement log file scanning
    #
    # Expected flow:
    #   1. Read configured log paths from .kerto/plugins.exs
    #   2. Tail new lines since last_sync
    #   3. Pattern-match for errors, warnings, file references
    #   4. Emit appropriate occurrences
    []
  end
end
