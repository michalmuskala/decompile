defmodule DecompilerTest do
  use ExUnit.Case

  test "works" do
    res = Decompile.Decompiler.process("test/files/Elixir.MyAppWeb.Router.beam", to: "expanded")
  end
end
