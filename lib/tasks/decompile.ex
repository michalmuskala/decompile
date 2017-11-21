defmodule Mix.Tasks.Decompile do
  use Mix.Task

  def run(args) do
    {opts, modules} = OptionParser.parse!(args, strict: [to: :string])

    modules
    |> Enum.map(&get_beam!/1)
    |> Enum.each(&decompile(&1, opts))
  end

  defp get_beam!(module_or_path) do
    with :non_existing <- :code.which(Module.concat([module_or_path])),
         :non_existing <- :code.which(String.to_atom(module_or_path)),
         :non_existing <- get_beam_file(module_or_path),
         :non_existing <- :code.where_is_file(basename(module_or_path)) do
      Mix.raise("Could not find .beam file for #{module_or_path}")
    end
  end

  defp basename(path) do
    String.to_charlist(Path.basename(path))
  end

  defp get_beam_file(path) do
    list = List.to_string(path)

    if File.exists?(path) and not match?({:error, _, _}, :beam_lib.info(list)) do
      list
    else
      :non_existing
    end
  end

  defp decompile(path, opts) do
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

  defp get_format(to: format), do: map_format(format)
  defp get_format(_), do: Mix.raise("--to option is required")

  defp map_format("ex"), do: :expanded
  defp map_format("erl"), do: :erlang
  defp map_format("asm"), do: :to_asm
  defp map_format("kernel"), do: :to_kernel
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
          "Failed to extract elixir debug info for module #{inspect(module)}: #{inspect(error)}"
        )
    end
  end

  defp from_debug_info(:erlang, module, backend, data) do
    case backend.debug_info(:erlang_v1, module, data, []) do
      {:ok, erlang_forms} ->
        format_erlang_forms(module, erlang_forms)

      {:error, error} ->
        Mix.raise(
          "Failed to extract erlang debug info for module #{inspect(module)}: #{inspect(error)}"
        )
    end
  end

  defp from_debug_info(other, module, backend, data) do
    case backend.debug_info(:core_v1, module, data, []) do
      {:ok, core} ->
        from_core(other, module, core)

      {:error, error} ->
        Mix.raise(
          "Failed to extract core debug info for module #{inspect(module)}: #{inspect(error)}"
        )
    end
  end

  defp from_abstract_code(:erlang, module, forms) do
    format_erlang_forms(module, forms)
  end

  defp from_abstract_code(other, module, forms) do
    case :compile.noenv_forms(forms, [:to_core]) do
      {:ok, ^module, core} ->
        from_core(other, module, core)

      {:ok, ^module, core, _warnings} ->
        from_core(other, module, core)
    end
  end

  defp format_elixir_info(module, elixir_info) do
    data =
      [
        "defmodule ", inspect(module), " do\n",
        Enum.map(elixir_info.definitions, &format_definition/1),
        "end\n"
      ]
      |> IO.iodata_to_binary()
      |> Code.format_string!()

    File.write("#{module}.ex", data)
  end

  defp format_definition({{name, _arity}, kind, _meta, heads}) do
    Enum.map(heads, fn {_meta, args, _what?, body} ->
      [
        "  #{kind} #{name}(#{Enum.map_join(args, ", ", &Macro.to_string/1)}) do\n",
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

  defp from_core(format, module, core) do
    raise "heh"
  end
end
