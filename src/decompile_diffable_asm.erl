-module(decompile_diffable_asm).

-export([format/1, beam_listing/2]).

format(Asm0) ->
    try
        {ok,Asm1} = beam_a:module(Asm0, []),
        Asm2 = renumber_asm(Asm1),
        {ok,Asm} = beam_z:module(Asm2, []),
        {ok, Asm}
    catch
        Class:Reason ->
            {error, Class, Reason}
    end.

renumber_asm({Mod,Exp,Attr,Fs0,NumLabels}) ->
    EntryLabels = maps:from_list(entry_labels(Fs0)),
    Fs = [fix_func(F, EntryLabels) || F <- Fs0],
    {Mod,Exp,Attr,Fs,NumLabels}.

entry_labels(Fs) ->
    [{Entry,{Name,Arity}} || {function,Name,Arity,Entry,_} <- Fs].

fix_func({function,Name,Arity,Entry0,Is0}, LabelMap0) ->
    Entry = maps:get(Entry0, LabelMap0),
    LabelMap = label_map(Is0, 1, LabelMap0),
    Is = replace(Is0, [], LabelMap),
    {function,Name,Arity,Entry,Is}.

label_map([{label,Old}|Is], New, Map) ->
    case maps:is_key(Old, Map) of
        false ->
            label_map(Is, New+1, Map#{Old=>New});
        true ->
            label_map(Is, New, Map)
    end;
label_map([_|Is], New, Map) ->
    label_map(Is, New, Map);
label_map([], _New, Map) ->
    Map.


replace([{label,Lbl}|Is], Acc, D) ->
    replace(Is, [{label,label(Lbl, D)}|Acc], D);
%% Drop line informations. They create noise in the diffs
replace([{line,_}|Is], Acc, D) ->
    replace(Is, Acc, D);
replace([{test,Test,{f,Lbl},Ops}|Is], Acc, D) ->
    replace(Is, [{test,Test,{f,label(Lbl, D)},Ops}|Acc], D);
replace([{test,Test,{f,Lbl},Live,Ops,Dst}|Is], Acc, D) ->
    replace(Is, [{test,Test,{f,label(Lbl, D)},Live,Ops,Dst}|Acc], D);
replace([{select,I,R,{f,Fail0},Vls0}|Is], Acc, D) ->
    Vls = lists:map(fun ({f,L}) -> {f,label(L, D)};
			(Other) -> Other
		    end, Vls0),
    Fail = label(Fail0, D),
    replace(Is, [{select,I,R,{f,Fail},Vls}|Acc], D);
replace([{'try',R,{f,Lbl}}|Is], Acc, D) ->
    replace(Is, [{'try',R,{f,label(Lbl, D)}}|Acc], D);
replace([{'catch',R,{f,Lbl}}|Is], Acc, D) ->
    replace(Is, [{'catch',R,{f,label(Lbl, D)}}|Acc], D);
replace([{jump,{f,Lbl}}|Is], Acc, D) ->
    replace(Is, [{jump,{f,label(Lbl, D)}}|Acc], D);
replace([{loop_rec,{f,Lbl},R}|Is], Acc, D) ->
    replace(Is, [{loop_rec,{f,label(Lbl, D)},R}|Acc], D);
replace([{loop_rec_end,{f,Lbl}}|Is], Acc, D) ->
    replace(Is, [{loop_rec_end,{f,label(Lbl, D)}}|Acc], D);
replace([{wait,{f,Lbl}}|Is], Acc, D) ->
    replace(Is, [{wait,{f,label(Lbl, D)}}|Acc], D);
replace([{wait_timeout,{f,Lbl},To}|Is], Acc, D) ->
    replace(Is, [{wait_timeout,{f,label(Lbl, D)},To}|Acc], D);
replace([{bif,Name,{f,Lbl},As,R}|Is], Acc, D) when Lbl =/= 0 ->
    replace(Is, [{bif,Name,{f,label(Lbl, D)},As,R}|Acc], D);
replace([{gc_bif,Name,{f,Lbl},Live,As,R}|Is], Acc, D) when Lbl =/= 0 ->
    replace(Is, [{gc_bif,Name,{f,label(Lbl, D)},Live,As,R}|Acc], D);
replace([{call,Ar,{f,Lbl}}|Is], Acc, D) ->
    replace(Is, [{call,Ar,{f,label(Lbl,D)}}|Acc], D);
replace([{make_fun2,{f,Lbl},U1,U2,U3}|Is], Acc, D) ->
    replace(Is, [{make_fun2,{f,label(Lbl, D)},U1,U2,U3}|Acc], D);
replace([{bs_init,{f,Lbl},Info,Live,Ss,Dst}|Is], Acc, D) when Lbl =/= 0 ->
    replace(Is, [{bs_init,{f,label(Lbl, D)},Info,Live,Ss,Dst}|Acc], D);
replace([{bs_put,{f,Lbl},Info,Ss}|Is], Acc, D) when Lbl =/= 0 ->
    replace(Is, [{bs_put,{f,label(Lbl, D)},Info,Ss}|Acc], D);
replace([{put_map=I,{f,Lbl},Op,Src,Dst,Live,List}|Is], Acc, D)
  when Lbl =/= 0 ->
    replace(Is, [{I,{f,label(Lbl, D)},Op,Src,Dst,Live,List}|Acc], D);
replace([{get_map_elements=I,{f,Lbl},Src,List}|Is], Acc, D) when Lbl =/= 0 ->
    replace(Is, [{I,{f,label(Lbl, D)},Src,List}|Acc], D);
replace([{recv_mark=I,{f,Lbl}}|Is], Acc, D) ->
    replace(Is, [{I,{f,label(Lbl, D)}}|Acc], D);
replace([{recv_set=I,{f,Lbl}}|Is], Acc, D) ->
    replace(Is, [{I,{f,label(Lbl, D)}}|Acc], D);
replace([I|Is], Acc, D) ->
    replace(Is, [I|Acc], D);
replace([], Acc, _) ->
    lists:reverse(Acc).

label(Old, D) when is_integer(Old) ->
    maps:get(Old, D).

%%%
%%% Run tasks in parallel.
%%%

p_run(Test, List) ->
    N = erlang:system_info(schedulers) * 2,
    p_run_loop(Test, List, N, [], 0).

p_run_loop(_, [], _, [], Errors) ->
    io:put_chars("\r \n"),
    case Errors of
	0 ->
            ok;
	N ->
	    io:format("~p errors\n", [N]),
            halt(1)
    end;
p_run_loop(Test, [H|T], N, Refs, Errors) when length(Refs) < N ->
    {_,Ref} = erlang:spawn_monitor(fun() -> exit(Test(H)) end),
    p_run_loop(Test, T, N, [Ref|Refs], Errors);
p_run_loop(Test, List, N, Refs0, Errors0) ->
    io:format("\r~p ", [length(List)+length(Refs0)]),
    receive
	{'DOWN',Ref,process,_,Res} ->
	    Errors = case Res of
                         ok -> Errors0;
                         error -> Errors0 + 1
                     end,
	    Refs = Refs0 -- [Ref],
	    p_run_loop(Test, List, N, Refs, Errors)
    end.

%%%
%%% Borrowed from beam_listing and tweaked.
%%%

beam_listing(Stream, {Mod,Exp,Attr,Code,NumLabels}) ->
    Head = ["%% -*- encoding:latin-1 -*-\n",
            io_lib:format("{module, ~p}.  %% version = ~w\n",
                          [Mod, beam_opcodes:format_number()]),
            io_lib:format("\n{exports, ~p}.\n", [Exp]),
            io_lib:format("\n{attributes, ~p}.\n", [Attr]),
            io_lib:format("\n{labels, ~p}.\n", [NumLabels])],
    ok = file:write(Stream, Head),
    lists:foreach(
      fun ({function,Name,Arity,Entry,Asm}) ->
              S = [io_lib:format("\n\n{function, ~w, ~w, ~w}.\n",
                                 [Name,Arity,Entry])|format_asm(Asm)],
              ok = file:write(Stream, S)
      end, Code).

format_asm([{label,_}=I|Is]) ->
    [io_lib:format("  ~p", [I]),".\n"|format_asm(Is)];
format_asm([I|Is]) ->
    [io_lib:format("    ~p", [I]),".\n"|format_asm(Is)];
format_asm([]) -> [].
