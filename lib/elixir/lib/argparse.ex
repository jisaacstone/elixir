defmodule ArgumentParser do
  defstruct flag_args: [],
    position_args: [:args, nargs: :*],
    description: "",
    epilog: "",
    prefix_char: ?-,
    add_help: true,
    strict: true

  @type t :: %ArgumentParser{}

  @type argument :: [
    argtype,
    action: action,
    choices: [term],
    required: boolean,
    default: term,
    help: String.t,
    metavar: atom]

  @type argtype :: atom | [String.t]

  @type action :: 
    :store |
    {:store, nargs} |
    {:store, convert} |
    {:store, nargs, convert} |
    {:store_const, term} |
    :store_true |
    :store_false |
    :append |
    {:append, nargs} |
    {:append, convert} |
    {:append, nargs, convert} |
    {:append_const, term, atom} |
    :count |
    :help |
    {:version, String.t}

  @type nargs :: pos_integer | :'?' | :* | :+ | :remainder

  @type convert :: ((String.t) -> term)

  @narg_atoms [:'?', :*, :+, :remainder]

  @spec parse([String.t], t) :: %{}
  def parse(args, parser) do
    parse(args, parser, %{})
  end
  defp parse([], options, parsed) do
    check_required_args_present(options, parsed)
  end
  defp parse([<<pc, ?h>> | _],
             %{add_help: true, prefix_char: pc} = options, _) do
    print_help(options)
  end
  defp parse([<<pc, pc, ?h, ?e, ?l, ?p>> | _],
             %{add_help: true, prefix_char: pc} = options, _) do
    print_help(options)
  end
  defp parse([<<pc, pc, _ :: binary>> = arg | rest],
             %{prefix_char: pc} = options,
             parsed) do
    argument = get_argument(arg, options.flag_args, options.strict)
    {parsed, rest} = apply_argument(argument, rest, parsed, options)
    parse(rest, options, parsed)
  end
  defp parse([<<pc, aliased :: binary>> | rest],
             %{prefix_char: pc} = options,
             parsed) do
    {parsed, rest} = unalias_and_apply(aliased, rest, parsed, options)
    parse(rest, options, parsed)
  end
  defp parse(args,
             %{position_args: [hd | tl]} = options,
             parsed) do
    {parsed, rest} = apply_argument(hd, args, parsed, options)
    parse(rest, %{options | position_args: tl}, parsed)
  end

  defp check_required_args_present(options, parsed) do
    case Stream.concat(options.position_args, options.flag_args) |>
         Stream.map(&key_for/1) |>
         Enum.reject(&Dict.has_key?(parsed, &1)) do
      [] -> parsed
      missing_args ->
        exit_bad_args("Missing required args: #{inspect(missing_args)}")
    end
  end

  defp print_help(options) do
    (desc = Keyword.get(options, :description)) && IO.puts(desc)
    IO.inspect options.flag_args
    IO.inpsect options.position_args
    (epilog = Keyword.get(options, :epilog)) && IO.puts(epilog)
    exit(:normal)
  end

  defp get_argument(arg, [], true) do
    exit_bad_args("invalid argument: #{arg}")
  end
  defp get_argument(<<_, _, arg :: binary>>, [], false) do
    [String.to_atom(arg)]
  end
  defp get_argument(arg, [[flags | _] = hd | tl], strict) do
    if arg in flags do hd else get_argument(arg, tl, strict) end
  end

  defp unalias_and_apply(<<>>, args, parsed, _) do
    {args, parsed}
  end
  defp unalias_and_apply(<<alias, rest :: binary>>, args, parsed, options) do
    argument = get_argument(alias, args, strict)
    {args, parsed} = apply_argument(argument, args, parsed, options)
    unalias_and_apply(rest, args, strict, parsed)
  end

  defp exit_bad_args(message) do
    IO.puts(message)
    exit(:normal)
  end

  defp key_for([name | _]) when is_atom(name) do
    name
  end
  defp key_for([flags | _]) when is_list(flags) do
    case Enum.max_by(flags, &String.length/1) do
      <<pc, pc, arg :: binary>> ->
        String.to_atom(arg)
      <<pc, arg :: binary>> ->
        String.to_atom(arg)
    end
  end

  defp apply_argument(argument, args, parsed) do
    apply_action(
      Keyword.get(argument, :action, :store),
      args,
      key_for(argument),
      parsed)
  end

  defp apply_action(action, _, key, %{key: _}, _)
  when (is_atom(action) and action != :append)
  or (is_tuple(action) and not elem(action, 0) in [:append, :append_const]) do
    exit_bad_args("duplicate key #{key}")
  end
  defp apply_action(:store, [hd | args], key, parsed, _options) do
    {args, Dict.put(parsed, key, hd)}
  end
  defp apply_action({:store, f}, [hd | args], key, parsed, _options)
  when is_function(f) do
    {args, Dict.put(parsed, key, f.(hd))}
  end
  defp apply_action({:store, n}, args, key, parsed, options)
  when is_number(n) or n in @narg_atoms do
    {value, rest} = fetch_nargs(args, n, options)
    {rest, Dict.put(parsed, key, value)}
  end
  defp apply_action({:store, n, f}, args, key, parsed, options)
  when is_function(f) and (is_number(n) or n in @narg_atoms) do
    {value, rest} = fetch_nargs(args, n, options)
    {rest, Dict.put(parsed, key, f.(value))}
  end
  defp apply_action(:store_true, args, key, parsed, _options) do
    {args, Dict.put(parsed, key, true)
  end
  defp apply_action(:store_false, args, key, parsed, _options) do
    {args, Dict.put(parsed, key, false)
  end
  defp apply_action({:store_const, const}, args, key, parsed, _options) do
    {args, Dict.put(parsed, key, const)
  end
  defp apply_action(:append, [hd | args], key, parsed, _options) do
    {args, Dict.update(parsed, key, [hd], &([hd | &1])}
  end
  defp apply_action({:append, f}, [hd | args], key, parsed, _options)
  when is_function(f) do
    value = f.(hd)
    {args, Dict.update(parsed, key, [value], &([value | &1])}
  end
  defp apply_action({:append, n}, args, key, parsed, options)
  when is_number(n) or n in @narg_atoms do
    {value, rest} = fetch_nargs(args, n, options)
    {args, Dict.update(parsed, key, [value], &([value | &1])}
  end
  defp apply_action({:append, n, f}, args, key, parsed, options)
  when is_function(f) and (is_number(n) or n in @narg_atoms) do
    {value, rest} = fetch_nargs(args, n, options)
    value = f.(value)
    {args, Dict.update(parsed, key, [value], &([value | &1])}
  end
  defp apply_action({:append_const, const, key}, args, _key, parsed, _options) do
    {args, Dict.update(parsed, key, [const], &([const | &1])}
  end
  defp apply_action(:count, args, key, parsed, _options) do
    {args, Dict.update(parsed, key, 1, &(&1 + 1))}
  end
  defp apply_action(:help, _, _, _, options) do
    print_help(options)
  end
  defp apply_action({:version, version}, _, _, _, _) do
    IO.puts(version)
    exit(:normal)
  end

  defp fetch_nargs(args, n, _options) when is_number(n) do
    Enum.split(args, n)
  end
  defp fetch_nargs(args, :remainder, _options) do
    {args, []}
  end
  defp fetch_nargs(args, :*, options) do
    Enum.split_while(args, &(not is_flag(&1, options.prefix_char)))
  end
  defp fetch_nargs(args, :+, options) do
    case Enum.split_while(args, &(not is_flag(&1, options.prefix_char))) do
      {[], _} -> exit_bad_args("Missing value")
      result  -> result
    end
  end
  defp fetch_nargs([hd | tl] = args, :'?', options) do
    if is_flag(hd, options.prefix_char) do
      {[], args}
    else
      {hd, tl}
    end
  end
  defp fetch_nargs([], :'?', _) do
    {[], []}
  end
end
