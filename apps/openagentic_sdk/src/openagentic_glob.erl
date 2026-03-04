-module(openagentic_glob).

-export([match/2, relpath/2, to_re/1]).

%% Kotlin parity:
%% - '*' matches within a segment ([^/]*)
%% - '?' matches within a segment ([^/])
%% - '**/' matches zero or more directories (?:.*/)?
%% - '**' matches anything (.*)
match(RelPath0, Pattern0) ->
  RelPath = norm_path(RelPath0),
  Pattern = norm_path(Pattern0),
  case string:trim(Pattern) of
    "" ->
      false;
    _ ->
      Re = to_re(Pattern),
      case re:run(RelPath, Re, [{capture, none}]) of
        match -> true;
        nomatch -> false
      end
  end.

relpath(Root0, Full0) ->
  Root = normalize_abs(Root0),
  Full = normalize_abs(Full0),
  Root2 =
    case Root of
      [] -> [];
      _ ->
        case lists:last(Root) of
          $/ -> Root;
          _ -> Root ++ "/"
        end
    end,
  case lists:prefix(Root2, Full) of
    true -> lists:nthtail(length(Root2), Full);
    false -> Full
  end.

%% internal
normalize_abs(P) ->
  lower_drive(norm_path(filename:absname(ensure_list(P)))).

lower_drive([A, $: | Rest]) when A >= $A, A =< $Z ->
  [A + 32, $: | Rest];
lower_drive(Other) ->
  Other.

norm_path(P0) ->
  P1 = ensure_list(P0),
  lists:flatten(string:replace(string:trim(P1), "\\", "/", all)).

to_re(Pattern0) ->
  Pattern = norm_path(Pattern0),
  ReBin = iolist_to_binary(lists:reverse(glob_to_re_loop(Pattern, 0, length(Pattern), ["^"]))),
  {ok, Mp} = re:compile(ReBin),
  Mp.

glob_to_re_loop(_P, I, Len, Acc) when I >= Len ->
  ["$" | Acc];
glob_to_re_loop(P, I, Len, Acc) ->
  Ch = lists:nth(I + 1, P),
  case Ch of
    $* ->
      IsDouble = I + 1 < Len andalso lists:nth(I + 2, P) =:= $*,
      case IsDouble of
        true ->
          FollowedBySlash = I + 2 < Len andalso lists:nth(I + 3, P) =:= $/,
          case FollowedBySlash of
            true ->
              %% **/ matches zero or more directories
              glob_to_re_loop(P, I + 3, Len, ["(?:.*/)?" | Acc]);
            false ->
              %% ** matches anything (including '/')
              glob_to_re_loop(P, I + 2, Len, [".*" | Acc])
          end;
        false ->
          glob_to_re_loop(P, I + 1, Len, ["[^/]*" | Acc])
      end;
    $? ->
      glob_to_re_loop(P, I + 1, Len, ["[^/]" | Acc]);
    $. -> glob_to_re_loop(P, I + 1, Len, [[ $\\, $. ] | Acc]);
    $+ -> glob_to_re_loop(P, I + 1, Len, [[ $\\, $+ ] | Acc]);
    $( -> glob_to_re_loop(P, I + 1, Len, [[ $\\, $( ] | Acc]);
    $) -> glob_to_re_loop(P, I + 1, Len, [[ $\\, $) ] | Acc]);
    $[ -> glob_to_re_loop(P, I + 1, Len, [[ $\\, $[ ] | Acc]);
    $] -> glob_to_re_loop(P, I + 1, Len, [[ $\\, $] ] | Acc]);
    ${ -> glob_to_re_loop(P, I + 1, Len, [[ $\\, ${ ] | Acc]);
    $} -> glob_to_re_loop(P, I + 1, Len, [[ $\\, $} ] | Acc]);
    $^ -> glob_to_re_loop(P, I + 1, Len, [[ $\\, $^ ] | Acc]);
    $$ -> glob_to_re_loop(P, I + 1, Len, [[ $\\, $$ ] | Acc]);
    $| -> glob_to_re_loop(P, I + 1, Len, [[ $\\, $| ] | Acc]);
    $\\ -> glob_to_re_loop(P, I + 1, Len, [[ $\\, $\\ ] | Acc]);
    _ ->
      glob_to_re_loop(P, I + 1, Len, [[Ch] | Acc])
  end.

ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(I) when is_integer(I) -> integer_to_list(I);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).
