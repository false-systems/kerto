defmodule Kerto.Engine.OccurrenceLog do
  @moduledoc """
  Ring buffer of recent occurrences backed by ETS.

  ULID keys = automatic time ordering. FIFO eviction when full.
  Mesh sync replays from this log via `since/2`.
  """

  use GenServer

  alias Kerto.Ingestion.Occurrence

  @default_max 1024

  # --- Client API ---

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec append(GenServer.server(), Occurrence.t()) :: :ok
  def append(server \\ __MODULE__, occurrence) do
    GenServer.call(server, {:append, occurrence})
  end

  @spec all(GenServer.server()) :: [Occurrence.t()]
  def all(server \\ __MODULE__) do
    GenServer.call(server, :all)
  end

  @spec since(GenServer.server(), String.t() | nil) :: [Occurrence.t()]
  def since(server \\ __MODULE__, sync_point) do
    GenServer.call(server, {:since, sync_point})
  end

  @spec count(GenServer.server()) :: non_neg_integer()
  def count(server \\ __MODULE__) do
    GenServer.call(server, :count)
  end

  # --- Server Callbacks ---

  @impl true
  def init(opts) do
    max = Keyword.get(opts, :max, @default_max)
    table = :ets.new(:occurrence_log, [:ordered_set, :private])
    {:ok, %{table: table, max: max}}
  end

  @impl true
  def handle_call({:append, %Occurrence{} = occ}, _from, state) do
    :ets.insert(state.table, {occ.source.ulid, occ})

    if :ets.info(state.table, :size) > state.max do
      oldest = :ets.first(state.table)
      :ets.delete(state.table, oldest)
    end

    {:reply, :ok, state}
  end

  def handle_call(:all, _from, state) do
    result =
      :ets.tab2list(state.table)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(&elem(&1, 1))

    {:reply, result, state}
  end

  def handle_call({:since, nil}, _from, state) do
    result =
      :ets.tab2list(state.table)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(&elem(&1, 1))

    {:reply, result, state}
  end

  def handle_call({:since, sync_point}, _from, state) when is_binary(sync_point) do
    result =
      :ets.tab2list(state.table)
      |> Enum.filter(fn {ulid, _occ} -> ulid > sync_point end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(&elem(&1, 1))

    {:reply, result, state}
  end

  def handle_call(:count, _from, state) do
    {:reply, :ets.info(state.table, :size), state}
  end
end
