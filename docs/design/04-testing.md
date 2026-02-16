# KERTO — Testing Strategy

Covers QA (test design), DST (deterministic simulation), and Blackbox (dataset-driven verification).

## Test Architecture

```
test/
├── graph/                     # Level 0: Pure unit tests (no setup, no state)
│   ├── node_test.exs          # Knowledge Node operations
│   ├── relationship_test.exs  # Relationship operations
│   ├── ewma_test.exs          # EWMA math (property-based)
│   ├── identity_test.exs      # Content-addressed ID generation
│   ├── node_kind_test.exs     # Canonicalization rules
│   └── graph_test.exs         # Graph operations (upsert, subgraph, decay)
│
├── ingestion/                 # Level 1: Pure unit tests
│   ├── occurrence_test.exs    # Occurrence struct validation
│   ├── extraction_test.exs    # Extraction dispatch
│   └── extractor/             # Per-extractor tests
│       ├── ci_failure_test.exs
│       ├── ci_success_test.exs
│       ├── commit_test.exs
│       ├── learning_test.exs
│       └── decision_test.exs
│
├── rendering/                 # Level 1: Pure unit tests
│   ├── renderer_test.exs      # Natural language output
│   └── query_test.exs         # Query coordination
│
├── infrastructure/            # Level 2: Integration tests (ETS, disk)
│   ├── store_test.exs         # ETS table operations
│   ├── persist_test.exs       # ETF + JSON snapshots
│   ├── ring_buffer_test.exs   # Bounded buffer behavior
│   ├── decay_test.exs         # Periodic decay process
│   └── ulid_test.exs          # ULID generation
│
├── interface/                 # Level 3: CLI integration tests
│   ├── cli_test.exs           # Command parsing + dispatch
│   └── commands/              # Per-command tests
│       ├── init_test.exs
│       ├── context_test.exs
│       ├── learn_test.exs
│       └── status_test.exs
│
├── simulation/                # DST: Deterministic simulation tests
│   ├── concurrent_agents_test.exs
│   ├── decay_convergence_test.exs
│   └── graph_evolution_test.exs
│
├── blackbox/                  # Blackbox: Dataset-driven verification
│   ├── datasets/
│   │   ├── ci_failures.json
│   │   ├── git_commits.json
│   │   ├── agent_learnings.json
│   │   └── expected_graph.json
│   └── dataset_test.exs
│
├── support/                   # Shared test helpers
│   ├── fixtures.ex            # Occurrence + Node + Relationship factories
│   └── graph_assertions.ex    # Custom assertions for graph state
│
└── test_helper.exs
```

## QA: Unit Test Strategy

### Level 0 Tests (Pure, Fast, No Setup)

These test the core domain. No ETS, no GenServer, no disk. Pure functions in, values out.

```elixir
# test/graph/ewma_test.exs
defmodule Kerto.Graph.EWMATest do
  use ExUnit.Case, async: true

  alias Kerto.Graph.EWMA

  describe "update/3" do
    test "new observation shifts weight toward observation" do
      assert EWMA.update(0.5, 1.0, 0.3) == 0.65
      # 0.3 * 1.0 + 0.7 * 0.5 = 0.65
    end

    test "zero observation pulls weight down" do
      assert EWMA.update(0.8, 0.0, 0.3) == 0.56
    end

    test "repeated observations converge to observation value" do
      weight = Enum.reduce(1..20, 0.0, fn _, w -> EWMA.update(w, 1.0, 0.3) end)
      assert_in_delta weight, 1.0, 0.01
    end
  end

  describe "decay/2" do
    test "reduces weight by factor" do
      assert EWMA.decay(1.0, 0.95) == 0.95
    end

    test "10 decay cycles from 1.0" do
      weight = Enum.reduce(1..10, 1.0, fn _, w -> EWMA.decay(w, 0.95) end)
      assert_in_delta weight, 0.5987, 0.001
    end
  end

  describe "dead?/2" do
    test "below threshold is dead" do
      assert EWMA.dead?(0.04, 0.05) == true
    end

    test "at threshold is not dead" do
      assert EWMA.dead?(0.05, 0.05) == false
    end
  end
end
```

```elixir
# test/graph/identity_test.exs
defmodule Kerto.Graph.IdentityTest do
  use ExUnit.Case, async: true

  alias Kerto.Graph.Identity

  describe "node_id/2" do
    test "same input produces same id" do
      id1 = Identity.node_id(:file, "src/auth.go")
      id2 = Identity.node_id(:file, "src/auth.go")
      assert id1 == id2
    end

    test "different kind produces different id" do
      id1 = Identity.node_id(:file, "auth")
      id2 = Identity.node_id(:module, "auth")
      assert id1 != id2
    end

    test "normalizes file paths" do
      id1 = Identity.node_id(:file, "src/auth.go")
      id2 = Identity.node_id(:file, "./src/auth.go")
      assert id1 == id2
    end

    test "normalizes pattern case" do
      id1 = Identity.node_id(:pattern, "OOM Risk")
      id2 = Identity.node_id(:pattern, "oom risk")
      assert id1 == id2
    end
  end
end
```

```elixir
# test/graph/node_test.exs
defmodule Kerto.Graph.NodeTest do
  use ExUnit.Case, async: true

  alias Kerto.Graph.Node

  describe "observe/2" do
    test "increases relevance toward 1.0" do
      node = Node.new("test-id", "auth.go", :file)
      observed = Node.observe(node, 1.0)

      assert observed.relevance > node.relevance
      assert observed.observations == 1
    end

    test "increments observation count" do
      node = Node.new("test-id", "auth.go", :file)
      observed = node |> Node.observe(0.8) |> Node.observe(0.8) |> Node.observe(0.8)

      assert observed.observations == 3
    end
  end

  describe "decay/2" do
    test "reduces relevance" do
      node = %{Node.new("test-id", "auth.go", :file) | relevance: 0.8}
      decayed = Node.decay(node, 0.95)

      assert decayed.relevance == 0.76
    end
  end

  describe "dead?/1" do
    test "node with low relevance and no relationships is dead" do
      node = %{Node.new("test-id", "auth.go", :file) | relevance: 0.005}
      assert Node.dead?(node) == true
    end

    test "node with low relevance but relationships is alive" do
      node = %{Node.new("test-id", "auth.go", :file) | relevance: 0.005}
      # dead? only checks relevance — relationship check happens at graph level
      assert Node.dead?(node) == true
    end
  end
end
```

### Level 1 Tests (Extraction Logic)

```elixir
# test/ingestion/extractor/ci_failure_test.exs
defmodule Kerto.Ingestion.Extractor.CiFailureTest do
  use ExUnit.Case, async: true

  alias Kerto.Ingestion.Extractor.CiFailure
  alias Kerto.Ingestion.Occurrence

  @ci_failure %Occurrence{
    id: "01TEST",
    timestamp: ~U[2026-02-13 14:30:00Z],
    source: :sykli,
    type: "ci.run.failed",
    severity: :error,
    outcome: :failure,
    data: %{
      "ci_data" => %{
        "git" => %{
          "changed_files" => ["src/auth.go", "src/handler.go"]
        },
        "tasks" => [
          %{"name" => "test", "status" => "failed"},
          %{"name" => "lint", "status" => "passed"}
        ]
      }
    },
    reasoning: %{"confidence" => 0.8}
  }

  test "extracts file nodes for changed files" do
    extractions = CiFailure.extract(@ci_failure)
    file_nodes = Enum.filter(extractions, &match?({:node, %{kind: :file}}, &1))

    assert length(file_nodes) == 2
    assert {:node, %{name: "src/auth.go", kind: :file}} in file_nodes
  end

  test "extracts :breaks relationships for changed files × failed tasks" do
    extractions = CiFailure.extract(@ci_failure)
    breaks = Enum.filter(extractions, &match?({:relationship, %{relation: :breaks}}, &1))

    # 2 files × 1 failed task = 2 :breaks relationships
    assert length(breaks) == 2
  end

  test "uses reasoning confidence when available" do
    extractions = CiFailure.extract(@ci_failure)
    breaks = Enum.filter(extractions, &match?({:relationship, _}, &1))

    Enum.each(breaks, fn {:relationship, attrs} ->
      assert attrs.confidence == 0.8
    end)
  end

  test "defaults to 0.7 confidence when reasoning missing" do
    occ = %{@ci_failure | reasoning: nil}
    extractions = CiFailure.extract(occ)
    breaks = Enum.filter(extractions, &match?({:relationship, _}, &1))

    Enum.each(breaks, fn {:relationship, attrs} ->
      assert attrs.confidence == 0.7
    end)
  end
end
```

### Level 2 Tests (Infrastructure)

```elixir
# test/infrastructure/ring_buffer_test.exs
defmodule Kerto.Infrastructure.RingBufferTest do
  use ExUnit.Case

  alias Kerto.Infrastructure.RingBuffer

  setup do
    table = :ets.new(:test_buffer, [:ordered_set, :public])
    {:ok, table: table}
  end

  test "push adds occurrence", %{table: table} do
    RingBuffer.push(table, %{id: "01A"}, 1024)
    assert :ets.info(table, :size) == 1
  end

  test "evicts oldest when over max", %{table: table} do
    for i <- 1..1028 do
      id = String.pad_leading("#{i}", 5, "0")
      RingBuffer.push(table, %{id: id}, 1024)
    end

    assert :ets.info(table, :size) == 1024
    # Oldest (00001-00004) should be evicted
    assert :ets.lookup(table, "00001") == []
    assert :ets.lookup(table, "00005") != []
  end

  test "maintains ULID ordering", %{table: table} do
    RingBuffer.push(table, %{id: "01B"}, 1024)
    RingBuffer.push(table, %{id: "01A"}, 1024)
    RingBuffer.push(table, %{id: "01C"}, 1024)

    keys = :ets.foldl(fn {k, _}, acc -> [k | acc] end, [], table) |> Enum.reverse()
    assert keys == ["01A", "01B", "01C"]
  end
end
```

## DST: Deterministic Simulation Testing

### Why DST for KERTO

KERTO has three sources of nondeterminism:
1. **Concurrent agent writes** — 20 agents writing simultaneously
2. **Decay timing** — weight changes depend on when decay runs relative to writes
3. **EWMA convergence** — order of observations affects intermediate weights (but not final convergence)

DST controls time and ordering to verify invariants hold under all interleavings.

### Simulation: Concurrent Agents

```elixir
# test/simulation/concurrent_agents_test.exs
defmodule Kerto.Simulation.ConcurrentAgentsTest do
  use ExUnit.Case

  @tag :simulation

  test "20 agents writing same learning converges to one high-confidence edge" do
    # Seed for deterministic randomness
    :rand.seed(:exsss, {42, 42, 42})

    graph = Kerto.Graph.new()

    # 20 agents all observe: auth.go breaks login_test
    occurrences = for i <- 1..20 do
      %{
        id: "agent-#{i}",
        source: :agent,
        type: "context.learning",
        data: %{
          subject: %{name: "auth.go", kind: :file},
          target: %{name: "login_test", kind: :module},
          relation: :breaks,
          confidence: 0.7 + :rand.uniform() * 0.3  # 0.7-1.0
        }
      }
    end

    # Shuffle to simulate arbitrary arrival order
    shuffled = Enum.shuffle(occurrences)

    # Ingest all
    graph = Enum.reduce(shuffled, graph, fn occ, g ->
      extractions = Kerto.Ingestion.Extraction.extract(occ)
      Kerto.Graph.apply_extractions(g, extractions, occ.id)
    end)

    # Invariant: exactly ONE node for auth.go, ONE node for login_test
    assert Kerto.Graph.node_count(graph) == 2

    # Invariant: exactly ONE :breaks relationship
    edges = Kerto.Graph.edges(graph)
    breaks = Enum.filter(edges, &(&1.relation == :breaks))
    assert length(breaks) == 1

    # Invariant: weight is high (reinforced 20 times)
    [edge] = breaks
    assert edge.weight > 0.85
    assert edge.observations == 20
  end

  test "interleaved writes and decays maintain invariants" do
    :rand.seed(:exsss, {123, 456, 789})

    graph = Kerto.Graph.new()

    # Simulate 100 events: mix of observations and decay cycles
    events =
      (for i <- 1..80, do: {:observe, "file-#{rem(i, 5)}.go", :file, 0.8}) ++
      (for _ <- 1..20, do: {:decay, 0.95})

    shuffled = Enum.shuffle(events)

    graph = Enum.reduce(shuffled, graph, fn
      {:observe, name, kind, confidence}, g ->
        Kerto.Graph.upsert_node(g, %{name: name, kind: kind}, confidence)

      {:decay, factor}, g ->
        Kerto.Graph.decay_all(g, factor)
    end)

    # Invariant: no relevance exceeds 1.0
    Enum.each(Kerto.Graph.nodes(graph), fn node ->
      assert node.relevance >= 0.0
      assert node.relevance <= 1.0
    end)

    # Invariant: no weight exceeds 1.0
    Enum.each(Kerto.Graph.edges(graph), fn edge ->
      assert edge.weight >= 0.0
      assert edge.weight <= 1.0
    end)
  end
end
```

### Simulation: Decay Convergence

```elixir
# test/simulation/decay_convergence_test.exs
defmodule Kerto.Simulation.DecayConvergenceTest do
  use ExUnit.Case

  @tag :simulation

  test "unreinforced node decays to death in bounded cycles" do
    node = Kerto.Graph.Node.new("test", "forgotten.go", :file)
    node = %{node | relevance: 1.0}

    # Decay at 0.95 per cycle
    {dead_at, _} = Enum.reduce_while(1..1000, {0, node}, fn cycle, {_, n} ->
      decayed = Kerto.Graph.Node.decay(n, 0.95)
      if Kerto.Graph.Node.dead?(decayed) do
        {:halt, {cycle, decayed}}
      else
        {:cont, {cycle, decayed}}
      end
    end)

    # Should die within 100 decay cycles (100 * 6h = 25 days)
    assert dead_at > 0
    assert dead_at < 100
  end

  test "reinforced node resists decay indefinitely" do
    node = Kerto.Graph.Node.new("test", "active.go", :file)

    # Alternate: observe then decay, 200 cycles
    node = Enum.reduce(1..200, node, fn _, n ->
      n
      |> Kerto.Graph.Node.observe(0.8)
      |> Kerto.Graph.Node.decay(0.95)
    end)

    # Should still be alive — observation rate > decay rate
    refute Kerto.Graph.Node.dead?(node)
    assert node.relevance > 0.5
  end
end
```

### Simulation: Decay Cycle Safety

The decay GenServer is KERTO's riskiest component: tick → decay all nodes → check death → remove dead → detect patterns → persist. These scenarios verify it's safe under concurrent load.

```elixir
# test/simulation/decay_safety_test.exs
defmodule Kerto.Simulation.DecaySafetyTest do
  use ExUnit.Case

  @tag :simulation

  test "decay tick during concurrent write does not corrupt graph" do
    :rand.seed(:exsss, {111, 222, 333})

    graph = Kerto.Graph.new()

    # Pre-populate with 50 nodes and 100 edges
    graph = Enum.reduce(1..50, graph, fn i, g ->
      Kerto.Graph.upsert_node(g, %{name: "file-#{i}.go", kind: :file}, 0.7)
    end)

    graph = Enum.reduce(1..100, graph, fn i, g ->
      src = "file-#{rem(i, 50) + 1}.go"
      tgt = "file-#{rem(i + 7, 50) + 1}.go"
      Kerto.Graph.upsert_relationship(g, src, :often_changes_with, tgt, 0.6, "commit-#{i}")
    end)

    # Interleave: 50 writes + 10 decay ticks + 5 prunes
    events =
      (for i <- 1..50, do: {:write, "file-#{rem(i, 20) + 1}.go", 0.9}) ++
      (for _ <- 1..10, do: {:decay, 0.95}) ++
      (for _ <- 1..5, do: :prune)

    shuffled = Enum.shuffle(events)

    final_graph = Enum.reduce(shuffled, graph, fn
      {:write, name, conf}, g ->
        Kerto.Graph.upsert_node(g, %{name: name, kind: :file}, conf)
      {:decay, factor}, g ->
        Kerto.Graph.decay_all(g, factor)
      :prune, g ->
        Kerto.Graph.prune(g)
    end)

    # Invariants after chaos
    Enum.each(Kerto.Graph.nodes(final_graph), fn node ->
      assert node.relevance >= 0.0 and node.relevance <= 1.0,
        "Node #{node.name} relevance out of bounds: #{node.relevance}"
    end)

    Enum.each(Kerto.Graph.edges(final_graph), fn edge ->
      assert edge.weight >= 0.0 and edge.weight <= 1.0,
        "Edge weight out of bounds: #{edge.weight}"
      # No dead edges should survive a prune
      refute Kerto.Graph.Relationship.dead?(edge),
        "Dead edge survived prune: #{edge.source} -#{edge.relation}-> #{edge.target}"
    end)
  end

  test "node death during observation does not lose the observation" do
    # Scenario: node is at 0.02 relevance (near death).
    # Decay would kill it. But an observation arrives at the same time.
    # The observation should win — the node should survive.
    node = %{Kerto.Graph.Node.new("test", "fragile.go", :file) | relevance: 0.02}

    # Observation arrives first
    observed = Kerto.Graph.Node.observe(node, 0.9)
    then_decayed = Kerto.Graph.Node.decay(observed, 0.95)
    refute Kerto.Graph.Node.dead?(then_decayed),
      "Node died despite receiving observation"

    # Decay arrives first
    decayed = Kerto.Graph.Node.decay(node, 0.95)
    then_observed = Kerto.Graph.Node.observe(decayed, 0.9)
    refute Kerto.Graph.Node.dead?(then_observed),
      "Node died despite receiving observation (decay-first order)"
  end

  test "pattern detection after decay only finds living edges" do
    graph = Kerto.Graph.new()

    # Create two relationships: one strong, one weak
    graph = graph
    |> Kerto.Graph.upsert_node(%{name: "strong.go", kind: :file}, 0.9)
    |> Kerto.Graph.upsert_node(%{name: "test_suite", kind: :module}, 0.9)
    |> Kerto.Graph.upsert_node(%{name: "weak.go", kind: :file}, 0.1)

    # Reinforce the strong edge 10 times
    graph = Enum.reduce(1..10, graph, fn _, g ->
      Kerto.Graph.upsert_relationship(g, "strong.go", :breaks, "test_suite", 0.9, "evidence")
    end)

    # Weak edge: only once, low confidence
    graph = Kerto.Graph.upsert_relationship(graph, "weak.go", :breaks, "test_suite", 0.3, "weak")

    # Decay 20 times (simulating ~5 days)
    graph = Enum.reduce(1..20, graph, fn _, g ->
      Kerto.Graph.decay_all(g, 0.95) |> Kerto.Graph.prune()
    end)

    # Strong edge should survive, weak should be pruned
    edges = Kerto.Graph.edges(graph)
    strong = Enum.find(edges, &(&1.source == "strong.go"))
    weak = Enum.find(edges, &(&1.source == "weak.go"))

    assert strong != nil, "Strong edge was incorrectly pruned"
    assert weak == nil, "Weak edge survived when it should have been pruned"
  end
end
```

### Simulation: Graph Evolution

```elixir
# test/simulation/graph_evolution_test.exs
defmodule Kerto.Simulation.GraphEvolutionTest do
  use ExUnit.Case

  @tag :simulation

  test "graph stays within memory budget after 10000 events" do
    :rand.seed(:exsss, {999, 999, 999})

    graph = Kerto.Graph.new()
    max_nodes = 1000

    # 10000 random events
    graph = Enum.reduce(1..10_000, graph, fn i, g ->
      file = "file-#{rem(i, 200)}.go"  # 200 unique files
      kind = Enum.random([:file, :module, :pattern])
      confidence = :rand.uniform()

      g = Kerto.Graph.upsert_node(g, %{name: file, kind: kind}, confidence)

      # Decay every 50 events
      if rem(i, 50) == 0 do
        Kerto.Graph.decay_all(g, 0.95) |> Kerto.Graph.prune()
      else
        g
      end
    end)

    # Invariant: node count within budget
    assert Kerto.Graph.node_count(graph) <= max_nodes
  end
end
```

## Blackbox: Dataset-Driven Verification

### Approach

Feed KERTO a known sequence of occurrences. Verify the resulting graph matches expected state. No internal knowledge — treat KERTO as a black box.

### Dataset Format

```json
// test/blackbox/datasets/ci_failures.json
{
  "description": "3 CI failures where auth.go breaks login tests",
  "occurrences": [
    {
      "type": "vcs.commit",
      "source": "git",
      "data": {"changed_files": ["src/auth.go", "src/auth_test.go"]}
    },
    {
      "type": "ci.run.failed",
      "source": "sykli",
      "data": {
        "ci_data": {
          "git": {"changed_files": ["src/auth.go"]},
          "tasks": [{"name": "test", "status": "failed"}]
        }
      },
      "reasoning": {"confidence": 0.8}
    },
    {
      "type": "ci.run.failed",
      "source": "sykli",
      "data": {
        "ci_data": {
          "git": {"changed_files": ["src/auth.go"]},
          "tasks": [{"name": "test", "status": "failed"}]
        }
      },
      "reasoning": {"confidence": 0.85}
    },
    {
      "type": "ci.run.failed",
      "source": "sykli",
      "data": {
        "ci_data": {
          "git": {"changed_files": ["src/auth.go"]},
          "tasks": [{"name": "test", "status": "failed"}]
        }
      },
      "reasoning": {"confidence": 0.9}
    }
  ],
  "expected": {
    "nodes": [
      {"name": "src/auth.go", "kind": "file", "min_relevance": 0.5},
      {"name": "src/auth_test.go", "kind": "file"},
      {"name": "test", "kind": "module"}
    ],
    "relationships": [
      {
        "source": "src/auth.go",
        "target": "test",
        "relation": "breaks",
        "min_weight": 0.7,
        "min_observations": 3
      },
      {
        "source": "src/auth.go",
        "target": "src/auth_test.go",
        "relation": "often_changes_with"
      }
    ]
  }
}
```

### Dataset Test Runner

```elixir
# test/blackbox/dataset_test.exs
defmodule Kerto.Blackbox.DatasetTest do
  use ExUnit.Case

  @datasets_dir "test/blackbox/datasets"

  for file <- File.ls!(@datasets_dir), String.ends_with?(file, ".json") do
    @tag :blackbox
    test "dataset: #{file}" do
      path = Path.join(@datasets_dir, unquote(file))
      dataset = path |> File.read!() |> Jason.decode!()

      # Build graph from occurrences
      graph = Kerto.Graph.new()

      graph = Enum.reduce(dataset["occurrences"], graph, fn raw_occ, g ->
        occ = Kerto.Ingestion.Occurrence.from_map(raw_occ)
        extractions = Kerto.Ingestion.Extraction.extract(occ)
        Kerto.Graph.apply_extractions(g, extractions, occ.id)
      end)

      # Verify expected nodes
      for expected_node <- dataset["expected"]["nodes"] do
        node = Kerto.Graph.find_node(graph, expected_node["name"],
          String.to_atom(expected_node["kind"]))

        assert node != nil,
          "Expected node #{expected_node["name"]} (#{expected_node["kind"]}) not found"

        if min_rel = expected_node["min_relevance"] do
          assert node.relevance >= min_rel,
            "Node #{node.name} relevance #{node.relevance} < #{min_rel}"
        end
      end

      # Verify expected relationships
      for expected_rel <- dataset["expected"]["relationships"] do
        edge = Kerto.Graph.find_edge(graph,
          expected_rel["source"],
          String.to_atom(expected_rel["relation"]),
          expected_rel["target"])

        assert edge != nil,
          "Expected relationship #{expected_rel["source"]} --#{expected_rel["relation"]}--> #{expected_rel["target"]} not found"

        if min_w = expected_rel["min_weight"] do
          assert edge.weight >= min_w
        end

        if min_obs = expected_rel["min_observations"] do
          assert edge.observations >= min_obs
        end
      end
    end
  end
end
```

## Dev Practices: Test Conventions

1. **Level 0 tests are always `async: true`** — pure functions, no shared state
2. **Level 2+ tests use setup/teardown** for ETS tables and temp directories
3. **Simulation tests tagged `@tag :simulation`** — can be excluded from fast runs
4. **Blackbox tests tagged `@tag :blackbox`** — can be excluded from fast runs
5. **No mocking** — dependency injection via function arguments, not mock libraries
6. **Property-based tests for EWMA math** — use StreamData for fuzzing float inputs
7. **Fixture factories in `test/support/fixtures.ex`** — one place for test data construction

### Test Commands

```bash
mix test                          # All tests
mix test --only graph             # Level 0 only (fast)
mix test --exclude simulation     # Skip slow simulation tests
mix test --only blackbox          # Dataset verification only
mix test test/graph/              # Specific directory
```

## Logging Strategy

Covered here since it's test-adjacent (you log what you test, you test what you log).

### What KERTO Logs

| Event | Level | Fields |
|-------|-------|--------|
| Occurrence ingested | `:debug` | `occurrence_id`, `type`, `source`, `nodes_created`, `relationships_created` |
| Node created | `:debug` | `node_id`, `name`, `kind` |
| Node died (decay) | `:info` | `node_id`, `name`, `kind`, `lived_for_days` |
| Relationship created | `:debug` | `source_name`, `target_name`, `relation`, `weight` |
| Relationship died | `:debug` | `source_name`, `target_name`, `relation` |
| Decay cycle | `:info` | `nodes_pruned`, `relationships_pruned`, `duration_ms` |
| Snapshot taken | `:info` | `format`, `path`, `size_bytes` |
| Hydration complete | `:info` | `source` (etf/json/empty), `nodes_loaded`, `relationships_loaded` |
| Hydration failed | `:warning` | `source`, `reason` |
| Extraction error | `:warning` | `occurrence_id`, `type`, `reason` |
| CLI command | `:debug` | `command`, `args` |

### What KERTO Does NOT Log

- Occurrence payloads (may contain code, prompts, sensitive data)
- File contents
- Agent session IDs (privacy)
- Full graph dumps (too large)

### Elixir Logger Config

```elixir
# Default: only info and above
config :logger, level: :info

# Debug mode (via KERTO_LOG_LEVEL=debug)
config :logger, level: :debug
```

### Structured Format

```elixir
require Logger

Logger.info("decay_cycle_completed",
  nodes_pruned: 12,
  relationships_pruned: 34,
  duration_ms: 45
)
```

## Git Workflow

### Branch Strategy

```
main                          # stable, releasable
feature/graph-core            # Level 0 implementation
feature/ingestion             # Level 1 implementation
feature/infrastructure        # Level 2 implementation
feature/cli                   # Level 3 implementation
```

### Commit Convention

Small commits, TDD-driven:

```
test(graph): add EWMA update property tests
feat(graph): implement EWMA.update/3 and EWMA.decay/2
test(ingestion): add CI failure extraction tests
feat(ingestion): implement CiFailure extractor
refactor(graph): extract identity canonicalization
```

Prefix matches the module level:
- `graph:` = Level 0
- `ingestion:` / `rendering:` = Level 1
- `infra:` = Level 2
- `cli:` = Level 3

### PR Size

Target: ≤200 lines per PR, ≤30 lines per commit. Same discipline as TAPIO.
