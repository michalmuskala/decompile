defmodule Mix.Tasks.Decompile do
  alias Decompile.Decompiler
  use Mix.Task

  def run(args) do
    {opts, modules} = OptionParser.parse!(args, strict: [to: :string, stdout: :boolean])

    Mix.Task.run("loadpaths")
    Decompiler.run(modules, opts)
  end
end
