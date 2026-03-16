defmodule Kerto.Interface.ULID do
  @moduledoc false
  # Moved to Kerto.Graph.ULID (Level 0). This delegate exists for
  # backward compatibility with any code that still references the old path.

  defdelegate generate(), to: Kerto.Graph.ULID
end
