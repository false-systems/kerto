defmodule Kerto.Graph.IdentityTest do
  use ExUnit.Case, async: true

  alias Kerto.Graph.Identity

  describe "compute_id/2" do
    test "produces a binary hash" do
      id = Identity.compute_id(:file, "auth.go")
      assert is_binary(id)
    end

    test "same inputs produce same id" do
      id1 = Identity.compute_id(:file, "auth.go")
      id2 = Identity.compute_id(:file, "auth.go")
      assert id1 == id2
    end

    test "different name produces different id" do
      id1 = Identity.compute_id(:file, "auth.go")
      id2 = Identity.compute_id(:file, "main.go")
      assert id1 != id2
    end

    test "different kind produces different id" do
      id1 = Identity.compute_id(:file, "auth")
      id2 = Identity.compute_id(:module, "auth")
      assert id1 != id2
    end

    test "returns hex-encoded string" do
      id = Identity.compute_id(:file, "auth.go")
      assert Regex.match?(~r/^[0-9a-f]+$/, id)
    end

    test "consistent length" do
      id1 = Identity.compute_id(:file, "a")
      id2 = Identity.compute_id(:pattern, "very-long-pattern-name-that-goes-on")
      assert byte_size(id1) == byte_size(id2)
    end
  end

  describe "canonicalize_name/2" do
    test "normalizes file paths" do
      assert Identity.canonicalize_name(:file, "./src/../src/auth.go") ==
               Identity.canonicalize_name(:file, "src/auth.go")
    end

    test "strips trailing slash from file paths" do
      assert Identity.canonicalize_name(:file, "src/auth/") == "src/auth"
    end

    test "strips leading ./ from file paths" do
      assert Identity.canonicalize_name(:file, "./auth.go") == "auth.go"
    end

    test "lowercases pattern names" do
      assert Identity.canonicalize_name(:pattern, "Circuit Breaker") == "circuit breaker"
    end

    test "lowercases error names" do
      assert Identity.canonicalize_name(:error, "OOM_KILL") == "oom_kill"
    end

    test "preserves module names as-is" do
      assert Identity.canonicalize_name(:module, "Kerto.Graph.EWMA") == "Kerto.Graph.EWMA"
    end

    test "preserves decision names as-is" do
      assert Identity.canonicalize_name(:decision, "Use JWT") == "Use JWT"
    end

    test "preserves concept names as-is" do
      assert Identity.canonicalize_name(:concept, "Authentication") == "Authentication"
    end
  end
end
