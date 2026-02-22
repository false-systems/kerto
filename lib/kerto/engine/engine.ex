defmodule Kerto.Engine do
  @moduledoc """
  Level 2: The stateful core. Supervisor + public API facade.

  Owns three children:
  - OccurrenceLog: ring buffer for mesh sync replay
  - Store: ETS-backed graph with ingest pipeline
  - Decay: periodic EWMA decay timer

  Start order matters: OccurrenceLog → Store → Decay.
  one_for_one: independent processes, isolated failures.
  """

  use Supervisor

  alias Kerto.Engine.{Config, Decay, OccurrenceLog, Store}

  # --- Supervisor ---

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    prefix = Keyword.get(opts, :name, __MODULE__)
    max_occ = Keyword.get(opts, :max_occurrences, Config.get(:max_occurrences))
    decay_interval = Keyword.get(opts, :decay_interval_ms, Config.get(:decay_interval_ms))
    decay_factor = Keyword.get(opts, :decay_factor, Config.get(:decay_factor))
    persistence_path = Keyword.get(opts, :persistence_path)

    log_name = child_name(prefix, :log)
    store_name = child_name(prefix, :store)
    decay_name = child_name(prefix, :decay)

    children = [
      {OccurrenceLog, name: log_name, max: max_occ},
      {Store, name: store_name, persistence_path: persistence_path},
      {Decay,
       name: decay_name, store: store_name, interval_ms: decay_interval, factor: decay_factor}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # --- Public Facade ---

  @spec ingest(atom(), map()) :: :ok
  def ingest(engine \\ __MODULE__, occurrence) do
    OccurrenceLog.append(child_name(engine, :log), occurrence)
    Store.ingest(child_name(engine, :store), occurrence)
    :ok
  end

  @spec get_node(atom(), atom(), String.t()) :: {:ok, map()} | :error
  def get_node(engine \\ __MODULE__, kind, name) do
    Store.get_node(child_name(engine, :store), kind, name)
  end

  @spec get_graph(atom()) :: map()
  def get_graph(engine \\ __MODULE__) do
    Store.get_graph(child_name(engine, :store))
  end

  @spec decay(atom(), float()) :: :ok
  def decay(engine \\ __MODULE__, factor) do
    Store.decay(child_name(engine, :store), factor)
  end

  @spec occurrences_since(atom(), String.t() | nil) :: [map()]
  def occurrences_since(engine \\ __MODULE__, sync_point) do
    OccurrenceLog.since(child_name(engine, :log), sync_point)
  end

  @spec occurrence_count(atom()) :: non_neg_integer()
  def occurrence_count(engine \\ __MODULE__) do
    OccurrenceLog.count(child_name(engine, :log))
  end

  @spec node_count(atom()) :: non_neg_integer()
  def node_count(engine \\ __MODULE__) do
    Store.node_count(child_name(engine, :store))
  end

  @spec relationship_count(atom()) :: non_neg_integer()
  def relationship_count(engine \\ __MODULE__) do
    Store.relationship_count(child_name(engine, :store))
  end

  @spec delete_node(atom(), atom(), String.t()) :: :ok | {:error, :not_found}
  def delete_node(engine \\ __MODULE__, kind, name) do
    Store.delete_node(child_name(engine, :store), kind, name)
  end

  @spec delete_relationship(atom(), atom(), String.t(), atom(), atom(), String.t()) ::
          :ok | {:error, :not_found}
  def delete_relationship(
        engine \\ __MODULE__,
        source_kind,
        source_name,
        relation,
        target_kind,
        target_name
      ) do
    Store.delete_relationship(
      child_name(engine, :store),
      source_kind,
      source_name,
      relation,
      target_kind,
      target_name
    )
  end

  @spec list_nodes(atom(), keyword()) :: [Kerto.Graph.Node.t()]
  def list_nodes(engine \\ __MODULE__, opts \\ []) do
    graph = get_graph(engine)
    Kerto.Graph.Graph.list_nodes(graph, opts)
  end

  @spec context(atom(), atom(), String.t(), keyword()) :: {:ok, String.t()} | {:error, :not_found}
  def context(engine \\ __MODULE__, kind, name, opts \\ []) do
    graph = get_graph(engine)

    case Kerto.Rendering.Query.query_context(graph, kind, name, "", opts) do
      {:ok, ctx} -> {:ok, Kerto.Rendering.Renderer.render(ctx)}
      error -> error
    end
  end

  @spec status(atom()) :: map()
  def status(engine \\ __MODULE__) do
    %{
      nodes: node_count(engine),
      relationships: relationship_count(engine),
      occurrences: occurrence_count(engine)
    }
  end

  # --- Private ---

  defp child_name(prefix, :log), do: :"#{prefix}.log"
  defp child_name(prefix, :store), do: :"#{prefix}.store"
  defp child_name(prefix, :decay), do: :"#{prefix}.decay"
end
