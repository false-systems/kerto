defmodule Kerto.Interface.ULIDTest do
  use ExUnit.Case, async: true

  # Verify the delegate still works
  test "Interface.ULID delegates to Graph.ULID" do
    ulid = Kerto.Interface.ULID.generate()
    assert is_binary(ulid)
    assert String.length(ulid) == 26
  end
end
