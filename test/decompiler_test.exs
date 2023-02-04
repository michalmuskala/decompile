defmodule DecompilerTest do
  use ExUnit.Case
  alias Decompile.Decompiler

  test "works" do
    Decompiler.process("test/files/Elixir.Decompile.Decompiler.beam", to: "ex", write: true)
  end
end
