defmodule Decompile.Decompiler do
  def run(modules, opts) do
    opts_as_map = Map.new(opts)
    Enum.each(modules, &process(&1, opts_as_map))
  end

  def process(module_or_path, opts) do
    opts = Map.new(opts)
    {module, data} = module_or_path |> get_beam!() |> decompile(opts)

    if Map.get(opts, :write) do
      File.write("#{module}.ex", data)
    end

    {module, data}
  end

  def get_beam!(module_or_path) do
    with :non_existing <- :code.which(module(module_or_path)),
         :non_existing <- :code.which(String.to_atom(module_or_path)),
         :non_existing <- get_beam_file(module_or_path),
         :non_existing <- :code.where_is_file(basename(module_or_path)) do
      Mix.raise("Could not find .beam file for #{module_or_path}")
    end
  end

  def module(string) do
    Module.concat(String.split(string, "."))
  end

  def basename(path) do
    String.to_charlist(Path.basename(path))
  end

  def get_beam_file(path) do
    list = String.to_charlist(path)

    if File.exists?(path) and not match?({:error, _, _}, :beam_lib.info(list)) do
      list
    else
      :non_existing
    end
  end

  def decompile(path, opts) do
    format = get_format(opts)

    case :beam_lib.chunks(path, [:debug_info]) do
      {:ok, {module, [debug_info: {:debug_info_v1, backend, data}]}} ->
        from_debug_info(format, module, backend, data)

      {:error, :beam_lib, {:unknown_chunk, _, _}} ->
        abstract_code_decompile(path, format)

      {:error, :beam_lib, {:missing_chunk, _, _}} ->
        abstract_code_decompile(path, format)

      _ ->
        Mix.raise("Invalid .beam file at #{path}")
    end
  end

  defp get_format(%{to: format}), do: map_format(format)
  defp get_format(_), do: Mix.raise("--to option is required")

  defp map_format("ex"), do: :expanded
  defp map_format("erl"), do: :erlang
  defp map_format("asm"), do: :to_asm
  defp map_format("diffasm"), do: :diff_asm
  defp map_format("disasm"), do: :to_dis
  defp map_format("kernel"), do: :to_kernel
  defp map_format("core"), do: :to_core
  defp map_format(other), do: String.to_atom(other)

  defp abstract_code_decompile(_path, :expanded) do
    Mix.raise("OTP 20 is required for decompiling to the expanded format")
  end

  defp abstract_code_decompile(path, format) do
    case :beam_lib.chunks(path, [:abstract_code]) do
      {:ok, {module, erlang_forms}} ->
        from_abstract_code(format, module, erlang_forms)

      _ ->
        Mix.raise("Missing debug info and abstract code for .beam file at #{path}")
    end
  end

  defp from_debug_info(:expanded, module, backend, data) do
    case backend.debug_info(:elixir_v1, module, data, []) do
      {:ok, elixir_info} ->
        format_elixir_info(module, elixir_info)

      {:error, error} ->
        Mix.raise(
          "Failed to extract Elixir debug info for module #{inspect(module)}: #{inspect(error)}"
        )
    end
  end

  defp from_debug_info(format, module, backend, data) do
    case backend.debug_info(:erlang_v1, module, data, []) do
      {:ok, erlang_forms} when format == :erlang ->
        format_erlang_forms(module, erlang_forms)

      {:ok, erlang_forms} ->
        from_erlang_forms(format, module, erlang_forms)

      {:error, error} ->
        Mix.raise(
          "Failed to extract Erlang debug info for module #{inspect(module)}: #{inspect(error)}"
        )
    end
  end

  defp from_abstract_code(:erlang, module, forms) do
    format_erlang_forms(module, forms)
  end

  defp from_abstract_code(other, module, forms) do
    from_erlang_forms(other, module, forms)
    # case :compile.noenv_forms(forms, [:to_core]) do
    #   {:ok, ^module, core} ->
    #     from_core(other, module, core)

    #   {:ok, ^module, core, _warnings} ->
    #     from_core(other, module, core)
    # end
  end

  defp format_elixir_info(module, elixir_info) do
    data =
      [
        "defmodule ",
        inspect(module),
        " do\n",
        Enum.map(elixir_info.definitions, &format_definition/1),
        "end\n"
      ]
      |> IO.iodata_to_binary()
      |> Code.format_string!()

    {module, data}
  end

  defp format_definition({{name, _arity}, kind, _meta, heads}) do
    Enum.map(heads, fn {_meta, args, _what?, body} ->
      [
        ~s[  #{kind} unquote(:"#{name}")(#{Enum.map_join(args, ", ", &Macro.to_string/1)}) do\n],
        Macro.to_string(body),
        "  end\n"
      ]
    end)
  end

  defp format_erlang_forms(module, erlang_forms) do
    File.open("#{module}.erl", [:write], fn file ->
      Enum.each(erlang_forms, &IO.puts(file, :erl_pp.form(&1)))
    end)
  end

  defp from_erlang_forms(:diff_asm, module, forms) do
    case :compile.noenv_forms(forms, [:S]) do
      {:ok, ^module, res} ->
        {:ok, formatted} = :decompile_diffable_asm.format(res)

        File.open("#{module}.S", [:write], fn file ->
          :decompile_diffable_asm.beam_listing(file, formatted)
        end)

      {:error, error} ->
        Mix.raise("Failed to compile to diffasm for module #{inspect(module)}: #{inspect(error)}")
    end
  end

  defp from_erlang_forms(format, module, forms) do
    case :compile.noenv_forms(forms, [format]) do
      {:ok, ^module, res} ->
        File.open("#{module}.#{ext(format)}", [:write], fn file ->
          :beam_listing.module(file, res)
        end)

      {:error, error} ->
        Mix.raise(
          "Failed to compile to #{inspect(format)} for module #{inspect(module)}: #{inspect(error)}"
        )
    end
  end

  defp ext(:to_core), do: "core"
  defp ext(:to_kernel), do: "kernel"
  defp ext(:to_asm), do: "S"
  defp ext(other), do: other
end
