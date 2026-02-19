defmodule Kerto.Engine.Store do
  @moduledoc """
  Owns the in-memory graph and serializes writes via GenServer.

  All mutations go through this process to ensure serialized updates.
  Read operations are exposed through the GenServer API.
  """

  use GenServer

  alias Kerto.Engine.Applier
  alias Kerto.Graph.{Graph, Identity}
  alias Kerto.Ingestion.Extraction

  # --- Client API ---

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec ingest(GenServer.server(), map()) :: :ok
  def ingest(server \\ __MODULE__, occurrence) do
    GenServer.call(server, {:ingest, occurrence})
  end

  @spec get_node(GenServer.server(), atom(), String.t()) :: {:ok, map()} | :error
  def get_node(server \\ __MODULE__, kind, name) do
    GenServer.call(server, {:get_node, kind, name})
  end

  @spec get_graph(GenServer.server()) :: Graph.t()
  def get_graph(server \\ __MODULE__) do
    GenServer.call(server, :get_graph)
  end

  @spec decay(GenServer.server(), float()) :: :ok
  def decay(server \\ __MODULE__, factor) do
    GenServer.call(server, {:decay, factor})
  end

  @spec apply_ops(GenServer.server(), [tuple()], String.t()) :: :ok
  def apply_ops(server \\ __MODULE__, ops, ulid) do
    GenServer.call(server, {:apply_ops, ops, ulid})
  end

  @spec node_count(GenServer.server()) :: non_neg_integer()
  def node_count(server \\ __MODULE__) do
    GenServer.call(server, :node_count)
  end

  @spec relationship_count(GenServer.server()) :: non_neg_integer()
  def relationship_count(server \\ __MODULE__) do
    GenServer.call(server, :relationship_count)
  end

  @spec delete_node(GenServer.server(), atom(), String.t()) :: :ok | {:error, :not_found}
  def delete_node(server \\ __MODULE__, kind, name) do
    GenServer.call(server, {:delete_node, kind, name})
  end

  @spec delete_relationship(GenServer.server(), atom(), String.t(), atom(), atom(), String.t()) ::
          :ok | {:error, :not_found}
  def delete_relationship(
        server \\ __MODULE__,
        source_kind,
        source_name,
        relation,
        target_kind,
        target_name
      ) do
    GenServer.call(
      server,
      {:delete_relationship, source_kind, source_name, relation, target_kind, target_name}
    )
  end

  @spec dump(GenServer.server()) :: Graph.t()
  def dump(server \\ __MODULE__), do: get_graph(server)

  # --- Server Callbacks ---

  @impl true
  def init(_opts) do
    {:ok, %{graph: Graph.new()}}
  end

  @impl true
  def handle_call({:ingest, occurrence}, _from, state) do
    ops = Extraction.extract(occurrence)
    ulid = occurrence.source.ulid
    graph = Applier.apply_ops(state.graph, ops, ulid)
    {:reply, :ok, %{state | graph: graph}}
  end

  def handle_call({:get_node, kind, name}, _from, state) do
    id = Identity.compute_id(kind, name)
    {:reply, Graph.get_node(state.graph, id), state}
  end

  def handle_call(:get_graph, _from, state) do
    {:reply, state.graph, state}
  end

  def handle_call({:decay, factor}, _from, state) do
    graph = Graph.decay_all(state.graph, factor)
    {:reply, :ok, %{state | graph: graph}}
  end

  def handle_call({:apply_ops, ops, ulid}, _from, state) do
    graph = Applier.apply_ops(state.graph, ops, ulid)
    {:reply, :ok, %{state | graph: graph}}
  end

  def handle_call(:node_count, _from, state) do
    {:reply, Graph.node_count(state.graph), state}
  end

  def handle_call(:relationship_count, _from, state) do
    {:reply, Graph.relationship_count(state.graph), state}
  end

  def handle_call({:delete_node, kind, name}, _from, state) do
    id = Identity.compute_id(kind, name)

    case Graph.delete_node(state.graph, id) do
      {graph, :ok} -> {:reply, :ok, %{state | graph: graph}}
      {_graph, :error} -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(
        {:delete_relationship, src_kind, src_name, relation, tgt_kind, tgt_name},
        _from,
        state
      ) do
    src_id = Identity.compute_id(src_kind, src_name)
    tgt_id = Identity.compute_id(tgt_kind, tgt_name)
    key = {src_id, relation, tgt_id}

    case Graph.delete_relationship(state.graph, key) do
      {graph, :ok} -> {:reply, :ok, %{state | graph: graph}}
      {_graph, :error} -> {:reply, {:error, :not_found}, state}
    end
  end
end
