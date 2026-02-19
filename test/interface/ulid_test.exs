defmodule Kerto.Interface.ULIDTest do
  use ExUnit.Case, async: true

  alias Kerto.Interface.ULID

  describe "generate/0" do
    test "returns 26-character string" do
      ulid = ULID.generate()
      assert is_binary(ulid)
      assert String.length(ulid) == 26
    end

    test "uses Crockford Base32 characters only" do
      ulid = ULID.generate()
      assert ulid =~ ~r/^[0123456789ABCDEFGHJKMNPQRSTVWXYZ]{26}$/
    end

    test "generates unique values" do
      ulids = for _ <- 1..100, do: ULID.generate()
      assert length(Enum.uniq(ulids)) == 100
    end

    test "generates sortable values (later is greater)" do
      ulid1 = ULID.generate()
      Process.sleep(20)
      ulid2 = ULID.generate()
      assert ulid2 > ulid1
    end
  end
end
