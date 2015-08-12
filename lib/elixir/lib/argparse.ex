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

  @type nargs :: pos_integer | :'?' | :* | :+ | :collect

  @type convert :: ((String.t) -> term)

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
    exit(:normal)
  end
  defp parse([<<pc, pc, ?h, ?e, ?l, ?p>> | _],
             %{add_help: true, prefix_char: pc} = options, _) do
    print_help(options)
    exit(:normal)
  end
  defp parse([<<pc, pc, _ :: binary>> = arg | rest],
             %{prefix_char: pc} = options,
             parsed) do
    argument = get_argument(arg, options.flag_args, options.strict)
    {parsed, rest} = apply_argument(argument, rest, parsed)
    parse(rest, options, parsed)
  end
  defp parse([<<pc, aliased :: binary>> | rest],
             %{prefix_char: pc} = options,
             parsed) do
    {parsed, rest} = unalias_and_apply(
      aliased, options.flag_args, options.strict, parsed)
    parse(rest, options, parsed)
  end
  defp parse(args,
             %{position_args: [hd | tl]} = options,
             parsed) do
    {parsed, rest} = apply_argument(hd, args, parsed)
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

  defp unalias_and_apply(<<>>, args, _, parsed) do
    {args, parsed}
  end
  defp unalias_and_apply(<<alias, rest :: binary>>, args, strict, parsed) do
    argument = get_argument(alias, args, strict)
    {args, parsed} = apply_argument(argument, args, parsed)
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

  defp apply_action(action, _, key, %{key: _})
  when (is_atom(action) and action != :append)
  or (is_tuple(action) and not elem(action, 0) in [:append, :append_const]) do
    exit_bad_args("duplicate key #{key}")
  end
  defp apply_action(:store, [hd | args], key, parsed) do
    {args, Dict.put(parsed, key, hd)}
  end
  defp apply_action({:store, f}, [hd | args], key, parsed) when is_function(f) do
    {args, Dict.put(parsed, key, f.(hd))}
  end
  defp apply_action({:store, n}, args, key, parsed) when is_number(n) do
    {value, rest} = Enum.split(args, n)
    {rest, Dict.put(parsed, key, value)}
  end
end
