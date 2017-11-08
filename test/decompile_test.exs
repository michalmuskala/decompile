defmodule DecompileTest do
  use ExUnit.Case
  doctest Decompile

  test "greets the world" do
    assert Decompile.hello() == :world
  end
end
