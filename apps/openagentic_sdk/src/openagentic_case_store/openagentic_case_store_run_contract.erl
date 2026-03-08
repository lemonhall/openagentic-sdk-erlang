-module(openagentic_case_store_run_contract).
-export([validate_report_contract/2, missing_markdown_sections/2, markdown_has_section/2, missing_required_fact_fields/2, fact_field_missing/2, fact_field_value/2, field_atom/1, format_missing_sections/1, format_missing_fact_fields/1]).

validate_report_contract(Version0, Delivery0) ->
  Version = openagentic_case_store_common_core:ensure_map(Version0),
  Delivery = openagentic_case_store_common_core:ensure_map(Delivery0),
  ReportContract = openagentic_case_store_common_core:ensure_map(openagentic_case_store_common_lookup:get_in_map(Version, [spec, report_contract], #{})),
  Markdown = openagentic_case_store_common_lookup:get_bin(Delivery, [report_markdown], <<>>),
  Facts = openagentic_case_store_common_core:ensure_list_of_maps(openagentic_case_store_common_lookup:get_in_map(Delivery, [facts], [])),
  Artifacts = openagentic_case_store_common_core:ensure_list_of_maps(openagentic_case_store_common_lookup:get_in_map(Delivery, [artifacts], [])),
  RequiredSections = [openagentic_case_store_common_core:to_bin(Item) || Item <- openagentic_case_store_common_lookup:get_list(ReportContract, [required_sections, requiredSections], [])],
  MissingSections = missing_markdown_sections(Markdown, RequiredSections),
  RequiredFactFields = [openagentic_case_store_common_core:to_bin(Item) || Item <- openagentic_case_store_common_lookup:get_list(ReportContract, [required_fact_fields, requiredFactFields], [])],
  MissingFactFields = missing_required_fact_fields(Facts, RequiredFactFields),
  case {Artifacts =:= [], MissingSections, MissingFactFields} of
    {true, _, _} ->
      {error, <<"report_contract_rejected">>, <<"artifacts.json must contain at least one formal artifact reference">>};
    {false, [_ | _], _} ->
      {error, <<"report_contract_rejected">>, format_missing_sections(MissingSections)};
    {false, [], [_ | _]} ->
      {error, <<"report_contract_rejected">>, format_missing_fact_fields(MissingFactFields)};
    _ ->
      ok
  end.

missing_markdown_sections(_Markdown, []) -> [];
missing_markdown_sections(Markdown0, Sections0) ->
  Markdown = string:lowercase(openagentic_case_store_common_core:to_bin(Markdown0)),
  [Section || Section <- Sections0, not markdown_has_section(Markdown, string:lowercase(openagentic_case_store_common_core:to_bin(Section)))].

markdown_has_section(Markdown, Section) ->
  Patterns = [<<"## ", Section/binary>>, <<"# ", Section/binary>>, <<"### ", Section/binary>>],
  lists:any(fun (Pattern) -> binary:match(Markdown, Pattern) =/= nomatch end, Patterns).

missing_required_fact_fields(_Facts, []) -> [];
missing_required_fact_fields(Facts, Fields) ->
  Missing =
    [
      Field
     || Field <- Fields,
        lists:any(fun (Fact) -> fact_field_missing(openagentic_case_store_common_core:ensure_map(Fact), Field) end, Facts)
    ],
  openagentic_case_store_common_core:unique_binaries(Missing).

fact_field_missing(Fact, Field) ->
  openagentic_case_store_common_core:trim_bin(fact_field_value(Fact, Field)) =:= <<>>.

fact_field_value(Fact, Field) ->
  case maps:get(Field, Fact, undefined) of
    undefined ->
      case field_atom(Field) of
        undefined -> <<>>;
        Atom -> openagentic_case_store_common_core:to_bin(maps:get(Atom, Fact, <<>>))
      end;
    Value ->
      openagentic_case_store_common_core:to_bin(Value)
  end.

field_atom(Bin) when is_binary(Bin) ->
  try binary_to_existing_atom(Bin, utf8) of
    Atom -> Atom
  catch
    _:_ -> undefined
  end;
field_atom(Atom) when is_atom(Atom) -> Atom;
field_atom(_) -> undefined.

format_missing_sections(Sections) ->
  iolist_to_binary([<<"report_contract missing markdown sections: ">>, binary:join([openagentic_case_store_common_core:to_bin(Section) || Section <- Sections], <<", ">>)]).

format_missing_fact_fields(Fields) ->
  iolist_to_binary([<<"report_contract missing required fact fields: ">>, binary:join([openagentic_case_store_common_core:to_bin(Field) || Field <- Fields], <<", ">>)]).
