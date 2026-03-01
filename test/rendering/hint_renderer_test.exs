defmodule Kerto.Rendering.HintRendererTest do
  use ExUnit.Case, async: true

  alias Kerto.Graph.{Identity, Node, Relationship}
  alias Kerto.Rendering.{Context, HintRenderer}

  defp make_node(kind, name) do
    Node.new(kind, name, "01JABC")
  end

  defp make_rel(source_kind, source_name, relation, target_kind, target_name, opts \\ []) do
    source_id = Identity.compute_id(source_kind, source_name)
    target_id = Identity.compute_id(target_kind, target_name)
    weight = Keyword.get(opts, :weight, 0.5)
    observations = Keyword.get(opts, :observations, 1)

    %Relationship{
      source: source_id,
      target: target_id,
      relation: relation,
      weight: weight,
      observations: observations,
      first_seen: "01JABC",
      last_seen: "01JABC",
      evidence: ["test evidence"]
    }
  end

  defp make_context(kind, name, rels, other_nodes \\ []) do
    node = make_node(kind, name)

    node_lookup =
      [node | other_nodes]
      |> Enum.map(&{&1.id, &1})
      |> Map.new()

    Context.new(node, rels, node_lookup)
  end

  describe "render/1" do
    test "empty contexts returns empty string" do
      assert HintRenderer.render([]) == ""
    end

    test "context with no relevant relations returns empty string" do
      other = make_node(:module, "lib")
      rel = make_rel(:file, "auth.ex", :part_of, :module, "lib")
      ctx = make_context(:file, "auth.ex", [rel], [other])

      assert HintRenderer.render([ctx]) == ""
    end

    test "context with caution relation produces hint line" do
      deploy = make_node(:file, "deploy.sh")
      rel = make_rel(:file, "auth.ex", :breaks, :file, "deploy.sh", weight: 0.82, observations: 3)
      ctx = make_context(:file, "auth.ex", [rel], [deploy])

      result = HintRenderer.render([ctx])
      assert result =~ "[kerto] auth.ex"
      assert result =~ "breaks"
      assert result =~ "deploy.sh"
      assert result =~ "0.82"
      assert result =~ "3x"
    end

    test "coupling relation produces hint line" do
      other = make_node(:file, "store.ex")

      rel =
        make_rel(:file, "engine.ex", :often_changes_with, :file, "store.ex",
          weight: 0.6,
          observations: 5
        )

      ctx = make_context(:file, "engine.ex", [rel], [other])

      result = HintRenderer.render([ctx])
      assert result =~ "[kerto] engine.ex"
      assert result =~ "often_changes_with"
      assert result =~ "store.ex"
      assert result =~ "5x"
    end

    test "structure relations are skipped" do
      target = make_node(:module, "lib")
      rel = make_rel(:file, "auth.ex", :depends_on, :module, "lib")
      ctx = make_context(:file, "auth.ex", [rel], [target])

      assert HintRenderer.render([ctx]) == ""
    end

    test "max 5 lines" do
      contexts =
        for i <- 1..8 do
          target = make_node(:file, "target_#{i}.ex")

          rel =
            make_rel(:file, "file_#{i}.ex", :breaks, :file, "target_#{i}.ex",
              weight: 0.7,
              observations: 2
            )

          make_context(:file, "file_#{i}.ex", [rel], [target])
        end

      result = HintRenderer.render(contexts)
      lines = String.split(result, "\n", trim: true)
      assert length(lines) <= 5
    end

    test "deduplicates across contexts" do
      deploy = make_node(:file, "deploy.sh")
      rel = make_rel(:file, "auth.ex", :breaks, :file, "deploy.sh", weight: 0.8, observations: 2)
      ctx1 = make_context(:file, "auth.ex", [rel], [deploy])
      ctx2 = make_context(:file, "auth.ex", [rel], [deploy])

      result = HintRenderer.render([ctx1, ctx2])
      count = result |> String.split("breaks") |> length()
      # "breaks" appears once in the output, meaning split produces 2 parts
      assert count == 2
    end

    test "caution relations sort before coupling relations" do
      target1 = make_node(:file, "deploy.sh")
      target2 = make_node(:file, "store.ex")

      caution_rel =
        make_rel(:file, "auth.ex", :breaks, :file, "deploy.sh", weight: 0.5, observations: 1)

      coupling_rel =
        make_rel(:file, "auth.ex", :often_changes_with, :file, "store.ex",
          weight: 0.9,
          observations: 10
        )

      ctx = make_context(:file, "auth.ex", [coupling_rel, caution_rel], [target1, target2])

      result = HintRenderer.render([ctx])
      breaks_pos = :binary.match(result, "breaks") |> elem(0)
      coupling_pos = :binary.match(result, "often_changes_with") |> elem(0)
      assert breaks_pos < coupling_pos
    end

    test "multiple relationships for same node joined with pipe" do
      target1 = make_node(:file, "deploy.sh")
      target2 = make_node(:concept, "cache-bug")

      rel1 =
        make_rel(:file, "auth.ex", :breaks, :file, "deploy.sh", weight: 0.8, observations: 3)

      rel2 =
        make_rel(:file, "auth.ex", :caused_by, :concept, "cache-bug",
          weight: 0.7,
          observations: 2
        )

      ctx = make_context(:file, "auth.ex", [rel1, rel2], [target1, target2])

      result = HintRenderer.render([ctx])
      assert result =~ "|"
      lines = String.split(result, "\n", trim: true)
      assert length(lines) == 1
    end
  end
end
