defmodule Kerto.Rendering.RendererTest do
  use ExUnit.Case, async: true

  alias Kerto.Rendering.{Context, Renderer}
  alias Kerto.Graph.{Node, Relationship}

  # Helper to build a context quickly
  defp build_context(node, rels, other_nodes \\ []) do
    lookup =
      [node | other_nodes]
      |> Enum.map(&{&1.id, &1})
      |> Map.new()

    Context.new(node, rels, lookup)
  end

  defp file_node(name, opts \\ []) do
    node = Node.new(:file, name, "01J001")
    relevance = Keyword.get(opts, :relevance, node.relevance)
    observations = Keyword.get(opts, :observations, node.observations)
    %{node | relevance: relevance, observations: observations}
  end

  defp module_node(name, opts \\ []) do
    node = Node.new(:module, name, "01J001")
    relevance = Keyword.get(opts, :relevance, node.relevance)
    %{node | relevance: relevance}
  end

  defp decision_node(name) do
    Node.new(:decision, name, "01J001")
  end

  defp rel(source_node, relation, target_node, opts \\ []) do
    weight = Keyword.get(opts, :weight, 0.5)
    observations = Keyword.get(opts, :observations, 1)
    evidence = Keyword.get(opts, :evidence, ["some evidence"])

    base = Relationship.new(source_node.id, relation, target_node.id, "01J001", hd(evidence))

    %{
      base
      | weight: weight,
        observations: observations,
        evidence: evidence
    }
  end

  describe "render/1" do
    test "renders header with name, kind, relevance, observations" do
      node = file_node("auth.go", relevance: 0.82, observations: 12)
      ctx = build_context(node, [])
      output = Renderer.render(ctx)

      assert output =~ "auth.go"
      assert output =~ "file"
      assert output =~ "0.82"
      assert output =~ "12"
    end

    test "renders empty context with just header" do
      node = file_node("auth.go")
      ctx = build_context(node, [])
      output = Renderer.render(ctx)

      assert output =~ "auth.go"
      refute output =~ "Caution"
      refute output =~ "Knowledge"
      refute output =~ "Structure"
    end

    test "renders Caution section for :breaks relationships" do
      auth = file_node("auth.go")
      test_file = file_node("login_test.go")

      breaks_rel =
        rel(auth, :breaks, test_file,
          weight: 0.87,
          observations: 5,
          evidence: ["CI failure: auth.go changed, login_test failed"]
        )

      ctx = build_context(auth, [breaks_rel], [test_file])
      output = Renderer.render(ctx)

      assert output =~ "Caution"
      assert output =~ "breaks"
      assert output =~ "login_test.go"
      assert output =~ "0.87"
    end

    test "renders Caution section for :caused_by relationships" do
      auth = file_node("auth.go")
      cache = Node.new(:concept, "unbounded cache", "01J001")

      caused_rel =
        rel(auth, :caused_by, cache,
          weight: 0.71,
          observations: 3,
          evidence: ["auth.go OOM was caused by unbounded cache"]
        )

      ctx = build_context(auth, [caused_rel], [cache])
      output = Renderer.render(ctx)

      assert output =~ "Caution"
      assert output =~ "caused_by"
      assert output =~ "unbounded cache"
    end

    test "renders Knowledge section for :decided relationships" do
      auth = file_node("auth.go")
      jwt = decision_node("JWT")

      decided_rel =
        rel(auth, :decided, jwt,
          weight: 0.92,
          observations: 2,
          evidence: ["Use JWT over sessions — stateless requirement"]
        )

      ctx = build_context(auth, [decided_rel], [jwt])
      output = Renderer.render(ctx)

      assert output =~ "Knowledge"
      assert output =~ "decided"
      assert output =~ "JWT"
    end

    test "renders Knowledge section for :learned relationships" do
      auth = file_node("auth.go")
      pattern = Node.new(:pattern, "caching", "01J001")

      learned_rel =
        rel(auth, :learned, pattern,
          weight: 0.75,
          evidence: ["uses aggressive caching"]
        )

      ctx = build_context(auth, [learned_rel], [pattern])
      output = Renderer.render(ctx)

      assert output =~ "Knowledge"
      assert output =~ "learned"
    end

    test "renders Structure section for :often_changes_with" do
      auth = file_node("auth.go")
      auth_test = file_node("auth_test.go")

      changes_rel =
        rel(auth, :often_changes_with, auth_test,
          weight: 0.65,
          observations: 8,
          evidence: ["commit: fix auth"]
        )

      ctx = build_context(auth, [changes_rel], [auth_test])
      output = Renderer.render(ctx)

      assert output =~ "Structure"
      assert output =~ "often_changes_with"
      assert output =~ "auth_test.go"
    end

    test "renders Structure section for :depends_on" do
      auth = file_node("auth.go")
      mod = module_node("crypto")

      dep_rel = rel(auth, :depends_on, mod, weight: 0.8)

      ctx = build_context(auth, [dep_rel], [mod])
      output = Renderer.render(ctx)

      assert output =~ "Structure"
      assert output =~ "depends_on"
    end

    test "omits empty sections" do
      auth = file_node("auth.go")
      auth_test = file_node("auth_test.go")

      # Only a Structure relationship, no Caution or Knowledge
      changes_rel = rel(auth, :often_changes_with, auth_test, weight: 0.65)

      ctx = build_context(auth, [changes_rel], [auth_test])
      output = Renderer.render(ctx)

      refute output =~ "Caution"
      refute output =~ "Knowledge"
      assert output =~ "Structure"
    end

    test "sorts relationships by weight descending within sections" do
      auth = file_node("auth.go")
      test1 = file_node("test1.go")
      test2 = file_node("test2.go")

      rel1 = rel(auth, :breaks, test1, weight: 0.5, evidence: ["low weight"])
      rel2 = rel(auth, :breaks, test2, weight: 0.9, evidence: ["high weight"])

      ctx = build_context(auth, [rel1, rel2], [test1, test2])
      output = Renderer.render(ctx)

      # test2 (0.9) should appear before test1 (0.5)
      pos_test2 = :binary.match(output, "test2.go") |> elem(0)
      pos_test1 = :binary.match(output, "test1.go") |> elem(0)
      assert pos_test2 < pos_test1
    end

    test "limits evidence to max 3 items" do
      auth = file_node("auth.go")
      test_file = file_node("test.go")

      many_evidence = ["e1", "e2", "e3", "e4", "e5"]

      breaks_rel =
        rel(auth, :breaks, test_file,
          weight: 0.8,
          evidence: many_evidence
        )

      ctx = build_context(auth, [breaks_rel], [test_file])
      output = Renderer.render(ctx)

      # Should show at most 3 evidence items
      evidence_lines =
        output
        |> String.split("\n")
        |> Enum.filter(&String.contains?(&1, "\""))

      assert length(evidence_lines) <= 3
    end

    test "renders incoming relationships (node is target)" do
      auth = file_node("auth.go")
      other = file_node("handler.go")

      # handler.go breaks auth.go — auth is the target
      incoming_rel = rel(other, :breaks, auth, weight: 0.7, evidence: ["handler breaks auth"])

      ctx = build_context(auth, [incoming_rel], [other])
      output = Renderer.render(ctx)

      assert output =~ "Caution"
      assert output =~ "handler.go"
    end

    test "renders observations count" do
      auth = file_node("auth.go")
      test_file = file_node("test.go")

      breaks_rel = rel(auth, :breaks, test_file, weight: 0.8, observations: 5, evidence: ["e"])

      ctx = build_context(auth, [breaks_rel], [test_file])
      output = Renderer.render(ctx)

      assert output =~ "5"
    end

    test "renders :triggers in Caution section" do
      auth = file_node("auth.go")
      alert = Node.new(:error, "timeout", "01J001")

      triggers_rel = rel(auth, :triggers, alert, weight: 0.6, evidence: ["triggers timeout"])

      ctx = build_context(auth, [triggers_rel], [alert])
      output = Renderer.render(ctx)

      assert output =~ "Caution"
      assert output =~ "triggers"
    end

    test "renders :tried_failed in Knowledge section" do
      auth = file_node("auth.go")
      approach = Node.new(:concept, "sessions", "01J001")

      tried_rel =
        rel(auth, :tried_failed, approach, weight: 0.7, evidence: ["sessions didn't scale"])

      ctx = build_context(auth, [tried_rel], [approach])
      output = Renderer.render(ctx)

      assert output =~ "Knowledge"
      assert output =~ "tried_failed"
    end

    test "renders :part_of in Structure section" do
      auth = file_node("auth.go")
      mod = module_node("auth-service")

      part_rel = rel(auth, :part_of, mod, weight: 0.9, evidence: ["part of auth-service"])

      ctx = build_context(auth, [part_rel], [mod])
      output = Renderer.render(ctx)

      assert output =~ "Structure"
      assert output =~ "part_of"
    end

    test "renders evidence text in quotes" do
      auth = file_node("auth.go")
      test_file = file_node("test.go")

      breaks_rel =
        rel(auth, :breaks, test_file, weight: 0.8, evidence: ["CI failure linked"])

      ctx = build_context(auth, [breaks_rel], [test_file])
      output = Renderer.render(ctx)

      assert output =~ "\"CI failure linked\""
    end

    test "resolves node names from lookup" do
      auth = file_node("auth.go")
      target = file_node("mystery.go")

      breaks_rel = rel(auth, :breaks, target, weight: 0.8, evidence: ["linked"])

      ctx = build_context(auth, [breaks_rel], [target])
      output = Renderer.render(ctx)

      # Should show the name, not the ID
      assert output =~ "mystery.go"
      refute output =~ target.id
    end

    test "handles missing node in lookup gracefully" do
      auth = file_node("auth.go")
      target = file_node("ghost.go")

      breaks_rel = rel(auth, :breaks, target, weight: 0.8, evidence: ["linked"])

      # Don't include target in lookup
      ctx = build_context(auth, [breaks_rel], [])
      output = Renderer.render(ctx)

      # Should still render, using the ID as fallback
      assert output =~ "Caution"
    end

    test "multiple sections render in order: Caution, Knowledge, Structure" do
      auth = file_node("auth.go")
      test_file = file_node("test.go")
      jwt = decision_node("JWT")
      auth_test = file_node("auth_test.go")

      breaks_rel = rel(auth, :breaks, test_file, weight: 0.8, evidence: ["breaks"])
      decided_rel = rel(auth, :decided, jwt, weight: 0.9, evidence: ["decided"])
      changes_rel = rel(auth, :often_changes_with, auth_test, weight: 0.6, evidence: ["changes"])

      ctx =
        build_context(auth, [breaks_rel, decided_rel, changes_rel], [test_file, jwt, auth_test])

      output = Renderer.render(ctx)

      caution_pos = :binary.match(output, "Caution") |> elem(0)
      knowledge_pos = :binary.match(output, "Knowledge") |> elem(0)
      structure_pos = :binary.match(output, "Structure") |> elem(0)

      assert caution_pos < knowledge_pos
      assert knowledge_pos < structure_pos
    end

    test "renders full example from plan" do
      auth = file_node("auth.go", relevance: 0.82, observations: 12)
      login_test = file_node("login_test.go")
      cache = Node.new(:concept, "unbounded cache", "01J001")
      jwt = decision_node("JWT")
      auth_test = file_node("auth_test.go")

      breaks_rel =
        rel(auth, :breaks, login_test,
          weight: 0.87,
          observations: 5,
          evidence: ["CI failure: auth.go changed, login_test failed"]
        )

      caused_rel =
        rel(auth, :caused_by, cache,
          weight: 0.71,
          observations: 3,
          evidence: ["auth.go OOM was caused by unbounded cache"]
        )

      decided_rel =
        rel(auth, :decided, jwt,
          weight: 0.92,
          observations: 2,
          evidence: ["Use JWT over sessions — stateless requirement"]
        )

      changes_rel =
        rel(auth, :often_changes_with, auth_test,
          weight: 0.65,
          observations: 8,
          evidence: ["commit: fix auth"]
        )

      ctx =
        build_context(
          auth,
          [breaks_rel, caused_rel, decided_rel, changes_rel],
          [login_test, cache, jwt, auth_test]
        )

      output = Renderer.render(ctx)

      assert output =~ "auth.go"
      assert output =~ "Caution"
      assert output =~ "Knowledge"
      assert output =~ "Structure"
      assert output =~ "login_test.go"
      assert output =~ "unbounded cache"
      assert output =~ "JWT"
      assert output =~ "auth_test.go"
    end
  end
end
