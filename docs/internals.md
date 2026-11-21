# prettier-asm internals

A static Linux x86-64 binary that formats files byte-identically to Prettier 3.6.2. It is
hand-written assembly with no libc. It covers JSON (the `json`, `jsonc`, `json5` and
`json-stringify` parsers), JavaScript in `.js`, `.mjs` and `.cjs` files (the `babel` parser
without JSX, Flow or the proposals other than decorators and `accessor`) and TypeScript in `.ts`, `.mts` and `.cts` files, printed as
Prettier's CLI prints them with its `typescript` parser (`.tsx` is not covered). Input it cannot
format exactly is refused, never guessed at.

## Build

```sh
make            # needs GNU as and ld only; writes build/prettier-asm
```

## Use

```sh
build/prettier-asm --stdin-filepath path/to/file.json < file.json
build/prettier-asm path/to/file.json
```

The parser comes from the file name, as Prettier's language list picks it (`package.json` is
`json-stringify`, `.jsonc` is `jsonc`, and so on). These options are ported: `--print-width`,
`--tab-width`, `--use-tabs`, `--single-quote`, `--no-bracket-spacing`, `--quote-props`,
`--trailing-comma`, `--object-wrap`, `--no-semi`, `--arrow-parens`, `--bracket-same-line`,
`--experimental-ternaries`, `--experimental-operator-position`,
`--embedded-language-formatting`, `--no-config`, `--no-editorconfig`. The config files may set
the same options. Config and ignore files
are read as the next section describes.

Exit 0 means the formatted text is on stdout. On anything not ported the binary writes
`unsupported: <reason>` to stderr and exits 3. With `PRETTIER_ASM_FALLBACK` set to the path of
`prettier.cjs`, it runs `node` with that script and the original arguments instead, replaying
the stdin bytes it already read from a memfd.

## Config and ignore files

The binary looks for the files Prettier's CLI looks for, in the same directories:

- `.gitignore` and `.prettierignore` in the working directory. Each gets a `node_modules` line,
  and the path relative to the working directory is tested against it.
- `.editorconfig` in every directory from the file's up to the project root, stopping at a file
  with `root = true`. The project root is the nearest directory holding a `.git` or `.hg`
  directory, else `/`.
- The first Prettier config file from the file's directory up to `/`, trying the 20 names in
  Prettier's order. `package.json` counts only when it has a truthy `prettier` key.

Each directory from `/` down to the file's is opened once and read with `getdents64`. A name
costs another syscall only when the listing has it. A directory that cannot be read, holds more
than two buffers of entries, or holds a name a case-folding file system could match, is probed
name by name with `newfstatat` instead. From an empty directory 7 levels below `/`, the search is
8 `openat` and 16 `getdents64` calls.

What is applied:

- An ignored file is printed as it was read. Ignore patterns may use `*`, `?`, `**`, slashes,
  `!` and `[a-z0-9_]` classes; they match without regard to case, as the `ignore` package does.
- `.prettierrc`, `.prettierrc.yaml` and `.prettierrc.yml` written as JSON or as `key: value`
  lines, `.prettierrc.json` and `.prettierrc.json5` written as JSON, and the `prettier` key of
  `package.json`. Keys: the ported options, `endOfLine: "lf"`, `$schema`, the options that do not
  change JSON output (`semi`, `arrowParens` and the like), and `overrides` whose globs use names,
  `*`, `?`, `**` segments and flat `{a,b}` groups.
- `.editorconfig` properties `indent_style`, `indent_size`, `tab_width`, `max_line_length`,
  `quote_type` and `end_of_line = lf`, for sections whose globs have no `[...]` class.
- Options from the command line win over config files, as `--config-precedence cli-override`
  does.

What is refused: the other config formats (JSON5 beyond JSON, TOML, JS, `package.yaml`,
YAML beyond `key: value`), unknown options, values outside the ported ranges, `endOfLine` other
than `lf`, `max_line_length = off`, ignore patterns with backslashes, paths that are not
printable ASCII when a pattern or section glob has to match them, `--config`, `--ignore-path`,
`--config-precedence` and `--with-node-modules`. A file argument that is a symbolic link or lies
under `.git`, `node_modules` or another directory Prettier skips is refused too.

## Test

```sh
make test                                    # stage 1 cases, then tests/harness.mjs on the json list
node tests/stage1/run.mjs --options          # also every ported option
node tests/stage1/run.mjs --list files.txt   # also these files, under their own names
node tests/stage1/mutants.mjs                # checks that broken binaries are reported
node tests/stage3/config/run.mjs             # config and ignore files, hand-written and random trees
node tests/stage3/config/fuzz.mjs            # ignore, editorconfig and override globs against Prettier's API
node tests/stage3/config/mutants.mjs         # checks that broken config rules are reported
node tests/stage3/parser/run.mjs             # JS parser against Babel: real, js-fixtures, ts-fixtures
node tests/stage3/parser/run.mjs tests/stage3/parser/cases.mjs   # targeted parser cases
node tests/stage3/parser/mutants.mjs         # checks that broken parsers are reported
node tests/stage3/infra/doc-eval.mjs         # doc printer against printDocToString, harvested and synthetic docs
node tests/stage3/infra/util-eval.mjs        # cleanDoc and the other doc utils against Prettier's
node tests/stage3/infra/text-eval.mjs        # text helpers against prettier.util
node tests/stage3/infra/path-eval.mjs        # the path API against Prettier's AstPath
node tests/stage3/infra/compare-docs.mjs     # --debug-doc against printToDoc on the json list
node tests/stage3/infra/mutants.mjs          # checks that broken printer infrastructure is reported
node tests/stage3/infra/bench-doc.mjs        # time to print one file's doc
node tests/stage3/printer/run.mjs            # printer snippets in cases.mjs, three option sets each
node tests/stage3/printer/run.mjs tests/stage3/printer/ts-cases.mjs   # the TypeScript snippets
node tests/stage3/printer/ts-mutants.mjs     # checks that broken TypeScript parse and print rules are reported
node tests/stage3/printer/sweep.mjs          # every JS and TS case of js-fixtures, real and ts-fixtures under 19 option sets
node tests/stage3/printer/check.mjs -e CODE  # one input against Prettier: output and first doc difference
node tests/stage3/comments/run.mjs           # JS comment attachment against Prettier: real, js-fixtures, cases.mjs
node tests/stage3/comments/run.mjs tests/stage3/comments/ts-cases.mjs   # the TypeScript handlers
node tests/stage3/comments/print-run.mjs     # printComment against Prettier's, comment by comment
node tests/stage3/comments/format-run.mjs    # the comment cases formatted end to end, where the printer handles them
node tests/stage3/comments/mutants.mjs       # checks that broken handlers and printComment are reported
node tests/stage3/printer/ts-parsers.mjs     # Prettier's typescript against its babel-ts output, real and ts-fixtures
node tests/stage3/printer/ts-both.mjs -e CODE    # one input through both of Prettier's TypeScript parsers
node tests/stage3/printer/ts-ast.mjs [--parser babel-ts] -e CODE   # the AST either parser hands the printer
node tests/stage3/comments/ts-parsers-fuzz.mjs --json f.json   # comments inserted into the TS cases where the parsers differ
node tests/stage3/comments/ts-parsers-check.mjs f.json   # the binary on those variants: refused or the typescript output
```

`run.mjs` runs Prettier's JSON fixtures under four file names, the snippets from their
`format.test.js` files and the cases in `edge-cases.mjs` through Prettier and the binary, and
reports identical, fallback or DIFFERENT. It exits 1 on any DIFFERENT. The oracle is
`node_modules/prettier` or `PRETTIER_CJS`, and its results are cached in
`build/oracle-cache.json`.

`tests/stage3/config/run.mjs` builds a directory tree per case, runs Prettier and the binary in
it, and reports identical, refused or DIFFERENT; it exits 1 on any DIFFERENT. Prettier's results
are cached in `build/stage3-config-oracle.json`. `fuzz.mjs` gets its expected output from
Prettier's `getFileInfo`, `resolveConfig` and `format`, the functions its CLI calls, so it can
try thousands of paths without starting Prettier for each.

`src/unicode_tables.s` is generated by `tests/stage1/gen-tables.mjs` from Prettier's own bundled
character data. The script checks the emoji trie against Prettier's `getStringWidth` before it
writes anything.

## Source layout

| File | What |
| --- | --- |
| `defs.inc` | constants, record layouts, the `FUNC`, `REFUSE` and `SDOC` macros |
| `sys.s` | raw syscalls and byte helpers |
| `arena.s` | the memory reservation, the bump arena, the scratch stack, growable lists |
| `io.s` | reading input, the output buffer |
| `cli.s` | `_start`, arguments, parser inference, refuse and fallback |
| `options.s` | format options and their flags |
| `config.s` | the config search, ignore files, options from config files |
| `config_parse.s` | JSON as `JSON.parse` reads it, the `key: value` YAML subset |
| `editorconfig.s` | `.editorconfig` parsing and editorconfig-to-prettier |
| `glob.s` | the editorconfig package's minimatch and the picomatch subset for `overrides` |
| `ignore.s` | gitignore rules as the `ignore` package compiles them |
| `core.s` | `coreFormat`: blank input, parse, attach comments, print |
| `text.s` | BOM and line-ending handling, Prettier's `skip*` and `hasNewline` helpers |
| `lex.s` | tokens, string and template cooking, comments |
| `json_parse.s` | Babel's `parseExpression` plus `assertJsonNode`, for JSON's node types |
| `parse_js_lex.s` | the JS tokenizer |
| `parse_js.s` | the JS parser's entry, helpers and statements |
| `parse_js_expr.s` | JS expressions |
| `parse_js_pat.s` | binding patterns, `toAssignable`, `checkLVal` |
| `parse_js_class.s` | functions, arrow functions, methods, classes |
| `parse_js_module.s` | `import` and `export` |
| `parse_js_post.s` | Prettier's postprocess of the babel AST |
| `parse_js_dump.s` | `--debug-ast` and `--debug-parse` |
| `parse_ts.s` | TypeScript types, type parameters, modifiers, signatures, decorators, TypeScript's expression cases |
| `parse_ts_decl.s` | TypeScript declarations: interface, type, enum, namespace, `declare`, `import x =` |
| `parse_js.inc` | macros, context bits and TypeScript state bits of the parse_js and parse_ts files |
| `ast_types.s` | generated: node type names, fields, visitor keys, keywords, operators |
| `comments.s` | comment attachment and printing (src/main/comments), the estree comment methods for JSON's types |
| `pjs_comments.s` | the JS comment handlers (`handle-comments.js`), `--debug-comments`, `--debug-comment-docs` |
| `pjs_comment_print.s` | the JS printer's other comment methods, `printComment`, the ignore utils |
| `doc.s` | doc builders, `propagateBreaks`, `willBreak`, `canBreak` |
| `docutils.s` | the other doc builders and utils: `mapDoc`, `cleanDoc`, `stripTrailingHardline`, ... |
| `docprint.s` | `printDocToString`, `fits`, fill, `generateInd`, end of line |
| `debugdoc.s` | the doc text form: `--debug-doc`, its reader, `--debug-doc-eval` |
| `ptrmap.s` | a hash map keyed by pointers |
| `path.s` | `AstPath` |
| `astdoc.s` | the main print loop (`mainPrint`, `callPluginPrintFunction`, `printIgnored`) |
| `width.s` | `getStringWidth` |
| `literal.s` | `printString`, `makeString`, `getPreferredQuote`, `printNumber` |
| `print_estree.s` | the estree printer for JSON's node types |
| `print_json.s` | the `estree-json` printer used by `json-stringify` |
| `pjs.inc`, `pjs_*.s` | the JavaScript printer, one file per Prettier source file (see JS printer) |
| `unicode_tables.s` | generated: wide characters, the emoji trie, ES5 identifier characters |

## Conventions

Functions use the SysV AMD64 convention: arguments in rdi, rsi, rdx, rcx, r8 and r9, results in
rax (and rdx for a second value), rbx, rbp and r12 to r15 preserved. `FUNC` and `ENDF` set up a
frame pointer and CFI, so gdb backtraces work. Return with `leave; ret`. Globals are `g_*` and
addressed RIP-relative.

Memory is one `MAP_NORESERVE` reservation split into 1 GiB regions (`R_*` in `defs.inc`).
`alloc` bumps through the arena, returns zeroed memory and never frees. Lists of unknown length
are built on the scratch stack: take `ss_mark`, `ss_push` items, then `ss_to_vec` or
`ss_to_array`. An inner list must finish before the outer one pushes again.

AST nodes are `NODE_SIZE` records: type, flags, start, end, attributes, comments, then fields
`N_F0` to `N_F7` whose meaning per type is in the spec in `tests/stage3/parser/gen-ast-types.mjs`
(see JS parser below). `N_DOC` caches the printed doc, as Prettier's `mainPrint` does. A `VEC` is
a count followed by pointers.

Docs are records tagged by a `DK_*` byte. A pointer is a doc's identity, so a shared subtree stays
shared and `propagateBreaks` visits a shared group once. The pointer 0 is the empty doc. `SDOC`
defines a static string doc; `d_line`, `d_softline`, `d_hardline` and the other constant docs
live in `doc.s`. A group that `ifBreak` refers to by id comes from `doc_group_with_id`.

Printing goes through the main print loop in `astdoc.s` (see Printer infrastructure below). A
JSON node type has a handler in `estree_handlers` (`print_estree.s`); a JS node type has one in
`estree_cases` (`pjs_estree.s`).

## Adding a node type

These steps are for JSON. For a JS node type, steps 1 and 2 hold, its printer goes in
`estree_cases` in `pjs_estree.s`, its comment handlers in `pjs_comments*.s`, and its cases in
`tests/stage3/printer/cases.mjs`.

1. Add the type and its fields to the spec in `tests/stage3/parser/gen-ast-types.mjs` and run it.
2. Build it in the parser with `js_node` (or `new_node` for JSON), with Babel's start and end.
3. Add its visitor keys to `visitor_keys` in `comments.s` (`ast_visitor_keys` has them all).
4. Add its printer to `estree_handlers` in `print_estree.s`.
5. Add the Prettier comment handlers that can match it to `handlers_own_line`,
   `handlers_end_of_line` and `handlers_remaining`, in Prettier's order.
6. Add cases to `tests/stage1/edge-cases.mjs` and get DIFFERENT to zero.

## JS parser

`js_parse(flags)` turns JS source into the AST Prettier's `babel` parser hands the printer: Babel's
node types, fields and ranges under Prettier's parse options (sourceType module, or script for
`.cjs` and `.cts`; `createParenthesizedExpressions`; `errorRecovery` with Prettier's list of
allowed error codes; the `decorators` plugin), then Prettier's postprocess. Babel's recursive
descent is followed function by function, with the same names (`parseMaybeAssign` is
`jpe_maybe_assign`). The tokenizer reads one token at a time; the parser asks for a regular
expression where an expression starts and for a template continuation after a substitution's `}`.
`js_source_is_script` gives the flags from the file name: `JS_SRC_SCRIPT` for `.cjs` and `.cts`,
`JS_SRC_TS` for `.ts`, `.mts` and `.cts`; it refuses `.tsx`.

TypeScript files get the tree Prettier's `babel-ts` parser gives (Babel's typescript plugin, then
the same postprocess), not the typescript-estree tree of Prettier's default `typescript` parser,
so the printer sees one shape. Prettier's babel-ts first tries the jsx and typescript plugins
together; this parser gives the typescript-only result and refuses a file where that first try
could succeed (a `<` that starts an expression with a matching closing tag later in the text). A
`.d.ts` file is parsed as a `.ts` file, as Prettier does; `declare` makes an ambient context.
Where the two parsers disagree, the input is refused (see TypeScript refusals below).

Refused, with a reason: JSX and TSX, Flow (a `@flow` pragma sends Prettier to babel-flow), the
Babel proposals Prettier turns on other than decorators and auto accessors (`using`, pipelines,
`do`, `::`, partial application, `throw` expressions, module expressions, import phases,
`export v from`, destructuring private names, optional chaining assignment, V8 intrinsics),
identifiers that are not ASCII or hold escapes, and every syntax error. Strict mode errors that
Prettier allows (octal literals, `with`, `delete x`, reserved words as identifiers, duplicate
parameters, redeclarations, `const` without initializer) give the tree Babel gives, as do the
allowed TypeScript errors (empty type argument and parameter lists, type parameters on a
constructor, parameter properties with patterns, optional patterns, initializers on ambient class
fields, `import type A, { B }`, a trailing comma after a rest element).

Where Babel tries one parse and falls back to another (`tryParse`: `<T>(x) => x` against
`<T>x`, `f<T>(x)` against `f < T > (x)`, arrow return types, modifiers, mapped types), `js_try`
runs the attempt with the parser state saved. A `REFUSE` whose reason starts with "syntax error"
unwinds to the innermost `js_try`, which restores the state; `js_lookahead` and `js_try_parse` are
Babel's `tsLookAhead` and `tsTryParse`. Other refusals end the run even inside an attempt.

The node record:

| Offset | Field |
| --- | --- |
| 0 | `N_TYPE` u16, `T_*` |
| 2 | `N_FLAGS` u16, printer state |
| 4, 8 | `N_START`, `N_END` u32, byte offsets into the text |
| 12 | `N_ATTR` u32, `NA_*` bits: Babel's booleans (`async`, `computed`, ...) and `extra.parenthesized`, `extra.deprecatedAssertSyntax` |
| 16 | `N_COMMENTS` |
| 24 to 80 | `N_F0` to `N_F7`, per type |
| 88, 96 | `N_DOC`, `N_KIDS`, printer caches |

The spec in `tests/stage3/parser/gen-ast-types.mjs` lists each type's fields and slots. It
generates `src/ast_types.s` (names, field descriptors, visitor keys in Prettier's order, keyword
buckets, operator strings, binary precedence) and the constants between the markers in
`defs.inc`. Related types share slots: functions keep id or key in F0, params in F1, body in F2,
kind in F3, and a pattern made from an expression keeps the expression's slots. The JSON types
keep their stage 1 numbers and slots.

TypeScript slots: F4 holds type parameters, or type arguments (which Babel 7 also calls
`typeParameters`, on calls, `new`, tagged templates and type references); F5 holds a function's
`returnType` or any `typeAnnotation`; F6 holds `decorators`; F7 holds `accessibility`. Classes keep
`superTypeParameters` in F3 and `implements` in F5. `importKind` and `exportKind` are kind slots,
set in TypeScript files only. Babel's TypeScript booleans (`abstract`, `declare`, `readonly`,
`override`, `definite`, `const`, `in`, `out`, `asserts`, `isExport`, `global`) are `NA_*` bits.
TSMappedType's `readonly` and `optional` are true, `"+"` or `"-"` (field kind `tri`).

Values: operators are token codes (`J_*`): a one-character operator is its ASCII code, the
others start at 0x80, and `ast_codes` has the strings. Kinds are `KD_*` codes in the same table.
An Identifier's name is its source text, except where its range is wider than the name: F7 then
holds the name's byte length (a parameter's `?` and type annotation are inside its range) and F0,
when set, holds 1 + the name's offset (a TSTypeParameter's name starts where its `in`, `out` or
`const` does, and a decorated parameter starts at its first decorator).

A string field is a pointer and a byte length in two
slots: StringLiteral's cooked value (UTF-8, with lone surrogates as 3-byte sequences), RegExp
pattern and flags (into the text), BigInt's digits, TemplateElement's cooked value (pointer 0
when an escape is invalid: Babel's `cooked: null`). DirectiveLiteral's value is its text between
the quotes. NumericLiteral has no value; the printer reads the raw text. A VEC field may be 0 or
`js_empty_vec` where Babel has an empty array. Comments are the `g_comments` list; a hashbang is
a `CT_INTERPRETER` comment, which Prettier prints as a line comment.

Positions are byte offsets. `--debug-ast` writes them as UTF-16 offsets, as JavaScript counts.
`N_START` is Prettier's `locStart`: postprocess moves the start of a node with decorators to the
first decorator (Babel does that itself for classes and class members, and for parameters only
outside TypeScript), and the start of an export declaration to its class's first decorator.

To add a node type: add it to the spec, run the generator, build it with `js_node` and `FINISH`
(Babel's `startNode` and `finishNode`), and add cases to `tests/stage3/parser/cases.mjs`.

`--debug-ast --stdin-filepath x.js` writes the tree in the canonical form described at the top
of `tests/stage3/parser/babel-ast.mjs`, which prints the same form from
`prettier.__debug.parse` with the `babel` parser, or `babel-ts` for a TypeScript file name (that
is the parse plus postprocess, before printing). `--debug-parse` parses without output, for
timing. `tests/stage3/parser/run.mjs` compares the two over case
lists. `tests/stage3/parser/build.sh` links `build/js-parse`, the parser with a minimal entry,
for when the rest of `src/` does not build.

## Printer infrastructure

What the JS printer port builds on. Names follow Prettier's; each function's comment names its
arguments and results.

### Doc printer

`print_doc_to_string(doc, options)` is `printDocToString(doc, options).formatted`: it returns
the text in rax (pointer, in the arena) and rdx (length). `options` is a `PO_*` record:
`PO_WIDTH` (`PW_INFINITY` is `Number.POSITIVE_INFINITY`), `PO_TAB_WIDTH`, `PO_USE_TABS`,
`PO_EOL` (`EOL_LF`, `EOL_CRLF`, `EOL_CR`). It can run at any time, also while another print is
running: each call saves the printer's globals, puts its command stacks and output above the
ones in use, and restores them. `print_doc(doc)` is the top-level print with the format options;
it leaves the text at the end of the output buffer. `g_print_eol` holds its end of line, `lf`
until `--end-of-line` is ported.

Everything `printer.js` does is ported except cursors: `trim` in the printer and in `fits`,
`align` with numbers, strings, negative numbers, `-Infinity` and `{type: "root"}`, with spaces
or tabs (`generateInd`'s flush rules), fill, conditional groups, line suffixes, group ids,
`indentIfBreak` with `negate`, CRLF and CR. Indentation records memoize `makeIndent` and the
last `makeAlign`, so a doc does not allocate an indentation per `indent` it meets.

### Docs

A doc pointer of 0 is `""`. `ss_to_array` drops `""` items; the printer does not care, but use
`ss_to_array_keep` where Prettier's array positions matter (fill parts, `[a, "", b]` that
`cleanDoc` or `stripTrailingHardline` will look at). `doc_array2` and `doc_array3` drop `""` too;
`doc_array3_keep` does not.

A group id is a record with `GID_MODE` and `GID_GEN`: a `DK_GROUP_ID` record from
`doc_group_id_new` (Prettier's `Symbol(...)`), or a group made by `doc_group_with_id`, which is
its own id. A group's `G_ID` and an `ifBreak` or `indentIfBreak`'s group field point at it, so
copies made by `mapDoc` keep the id as Prettier's spread keeps the symbol. `GF_PROPAGATED` marks
`break: "propagated"`.

Labels are bit sets (`LB_*`): `{embed: true}`, `{hug: false}`, `{hug: true}`,
`{memberChain: true}`, `{tagged: true}`, which are all the estree printer uses.

| Prettier | Here |
| --- | --- |
| `indent`, `align`, `group`, `fill`, `ifBreak`, `indentIfBreak`, `lineSuffix`, `label` | `doc.s`: `doc_indent`, `doc_align`, `doc_group`, `doc_fill`, `doc_if_break`, `doc_indent_if_break`, `doc_line_suffix`, `doc_label` |
| `group(..., {shouldBreak, id})`, `conditionalGroup` | `docutils.s`: `doc_group_ex`, `doc_conditional_group`, `doc_group_id_new`; `doc.s`: `doc_group_with_id` |
| `dedent`, `dedentToRoot`, `markAsRoot`, `align(n)`, `align("s")` | `docutils.s`: `doc_dedent`, `doc_dedent_to_root`, `doc_mark_as_root`, `doc_align_n`, `doc_align_str` |
| `label(l, doc)` (doc itself when `l` is falsy) | `docutils.s`: `doc_label_or` |
| `join`, `addAlignmentToDoc` | `docutils.s`: `doc_join` (takes a VEC), `add_alignment_to_doc` |
| `line`, `softline`, `hardline`, `literalline`, `hardlineWithoutBreakParent`, `literallineWithoutBreakParent`, `breakParent`, `lineSuffixBoundary`, `trim`, `cursor` | `doc.s`: `d_line`, `d_softline`, `d_hardline`, `d_literalline`, `d_hardline_nb`, `d_literalline_nb`, `d_break_parent`, `d_line_suffix_boundary`, `d_trim`, `d_cursor` |
| `propagateBreaks`, `willBreak`, `canBreak` | `doc.s`: `propagate_breaks`; `docutils.s`: `will_break`, `can_break` |
| `mapDoc`, `traverseDoc`, `findInDoc`, `inheritLabel` | `docutils.s`: `map_doc`, `traverse_doc`, `find_in_doc`, `inherit_label` |
| `cleanDoc`, `stripTrailingHardline`, `removeLines`, `replaceEndOfLine`, `isEmptyDoc` | `docutils.s`: `clean_doc`, `strip_trailing_hardline`, `remove_lines`, `replace_end_of_line_doc` (and `replace_end_of_line` for a string), `is_empty_doc` |
| `printDocToString` | `docprint.s`: `print_doc_to_string` |

Prettier 3.6.2 has no `getDocParts`, `normalizeDoc` or `normalizeParts`; arrays are the parts.
`map_doc` caches results by doc address where Prettier's `Map` caches strings by value, so two
equal strings can map to two equal results where Prettier shares one; printing is the same.

### Callbacks

A callback is a function pointer and a context pointer, passed side by side. The function gets
the context in rdi and its other arguments after it: `fn(ctx, doc)` for `map_doc` and
`inherit_label`, `on_enter(ctx, doc)` for `traverse_doc` (eax 0 skips the children, as
`return false` does), `fn(ctx, doc)` returning rax and edx 1 when defined for `find_in_doc`,
`fn(ctx, node, index)` for the path functions. `path_match` predicates are plain
`pred(node, key, index)` functions, 0 for `undefined`.

### Main print and args

`astdoc.s` ports `ast-to-doc.js`. `g_printer` points at the printer record (`PR_*`, below).
`print_ast_root(root)` starts the path and prints the root. Inside a printer:

- `main_print_here(args)` is `print()`: the node at the top of the path.
- `print_field(offset, key, args)` is `print("key")`.
- `print_elem(vec, index, key, args)` is `print(["key", index])`.
- `print_map(offset, key, args)` is `path.map(print, "key")`; it returns a VEC of docs.
- `main_print(node, key, index, args)` prints a node the caller found.

`args` is 0 for `undefined`, or a pointer to an `ARGS_*` record: `ARGS_EXPAND_FIRST_ARG`,
`ARGS_EXPAND_LAST_ARG` and `ARGS_ASSIGNMENT_LAYOUT` (`AL_*`, 0 for undefined), the only args
the estree printer passes. `args_for_layout(layout)` returns a static `{assignmentLayout}`
record. Only `args` 0 is cached (`N_DOC`). `call_plugin_print` runs the printer's
`hasPrettierIgnore` (or `print`), then `printComments` unless `willPrintOwnComments` says no.
`print_ignored` is `printIgnored`; `ensure_all_comments_printed` refuses where Prettier throws.

### Path

`path.s` ports `AstPath`. An entry is a value with its key (`K_*`, 0 for null), its index (-1
for null), its siblings (a VEC or LIST) and `PEF_ARRAY` when the value is an array. Getters:
`path_value` (`path.node`), `path_key`, `path_index`, `path_parent`, `path_grandparent`,
`path_node(n)` (`getNode`), `path_parent_node(n)`, `path_siblings`, `path_is_in_array`,
`path_is_first`, `path_is_last`, `path_previous`, `path_next`, `path_is_root`, `path_root`.
Calls: `path_call(fn, ctx, key, offset)`, `path_call_node(fn, ctx, node, key)` for a value found
by the caller, `path_each(fn, ctx, key, offset)`, `path_each_vec(fn, ctx, key, vec)`,
`path_map(fn, ctx, key, offset)` and `path_map_vec` (both return a VEC), `path_match(predicates,
count)`, `path_find_ancestor(pred, ctx)`, `path_has_ancestor`, `path_call_parent(fn, ctx, count)`.
`path_push`, `path_push_array` and `path_pop` work the stack directly. Keys are `K_*` ids; the
JS port needs one per Babel field name, which the parser's generator can emit.

### Printer record and comment hooks

`g_printer` points at a `PR_*` record of function pointers, 0 for a method the printer does not
have: `print`, `hasPrettierIgnore`, `willPrintOwnComments`, `printComment`, `isBlockComment`,
`canAttachComment` (0: no comments are attached), `getCommentChildNodes` (returns a VEC, or 0 for
`undefined`), the visitor keys table and its length (the format of `ast_visitor_keys`), the
`ownLine`, `endOfLine` and `remaining` handler lists, and `isGap(start, end)` (0, 1, or -1 for
`undefined`). A handler is `handler(comment, is_last_comment)`; the comment's `CM_ENCL`,
`CM_PREC` and `CM_FOLL` are the context Prettier passes. `estree_printer` in `print_estree.s` is
the record for JSON; the JS port fills its own.

`comments.s` has the generic part complete: `get_sorted_child_nodes`, `decorate_comment` (with
the template literal rule), `attach_comments` with the tie-break through `isGap` or
`/^[\s(]*$/`, `add_leading`, `add_trailing`, `add_dangling(node, comment, marker)`,
`print_comments`, `print_comments_separately` (leading and trailing arrays, ecx 0 when there is
nothing to print), `print_dangling_comments_ex(flags, marker, filter, ctx)` with `DC_INDENT`,
`has_comment` and `get_comments` with `CC_*` flags. Comments are printed with the comment pushed
on the path, as `path.each(..., "comments")` does. Prettier's `locStart` moves a node's start to
its first decorator; the parser's postprocess sets `N_START` that way, so the generic code can
read `N_START`.

### Text helpers

`text.s` ports `skip`, `skipSpaces`, `skipToLineEnd`, `skipEverythingButNewLine`,
`skipWhitespace`, `skipNewline`, `skipInlineComment`, `skipTrailingComment`, `hasNewline`,
`hasNewlineInRange`, `hasSpaces`, `isNextLineEmpty`, `isPreviousLineEmpty`,
`getNextNonSpaceNonCommentCharacterIndex`, `getNextNonSpaceNonCommentCharacter`,
`getAlignmentSize`, `getIndentSize`, `getMaxContinuousCount` and
`getMinNotPresentContinuousCount`, plus `trim_start_bytes` and `trim_end_bytes` for
`String#trimStart` and `trimEnd`. They read `g_text` (or a string they are given). Offsets are
bytes. A forward scan takes and returns the offset of a character's first byte; a backward scan
takes and returns the offset of a character's last byte, so `locStart(node) - 1` works as in
Prettier. U+2028 and U+2029 are line breaks where Prettier's regexes and `skipNewline` say so.
`next_nonspace_noncomment_char` returns a code point where `charAt` returns a UTF-16 unit; they
differ only for astral characters. `/\s/` is `is_js_space_cp`.

### Doc text and debug flags

`--debug-doc` writes the doc the printer would print, in the text form below, instead of the
formatted text. `--debug-doc-exact` writes the exact form. `tests/stage3/infra/debug-doc.mjs
<file>` writes the same form from `prettier.__debug.printToDoc`, and `compare-docs.mjs` compares
the two over a case list.

```
doc      = string | "[" doc* "]" | leaf | "(" head ... ")" | "$" N "=" doc | "$" N
leaf     = line | soft | hard | lit | bp | lsb | trim | cursor
           (hard and lit are the lines without their breakParent)
(indent D)  (lsuffix D)  (label "k=v,..." D)
(align N D)        N: an integer, "string", -inf or root
(group FLAGS D)    FLAGS: break or pbreak ("propagated"), #N for the id
(cgroup FLAGS S0 S1 ...)        conditionalGroup; its contents are S0
(cgroup* FLAGS C S0 S1 ...)     contents C that are not S0 (stripTrailingHardline makes these)
(fill P0 P1 ...)  (ifbreak B F [#N])  (iib [negate] [#N] D)
(tostr W TW TABS EOL D)        in eval input only: printDocToString(D) as a string
```

Strings are JSON strings as `JSON.stringify` writes them. The normalized form flattens arrays,
drops `""` and merges adjacent strings; an array left with one item is that item. The exact form
keeps arrays and strings and labels shared arrays too. A container referenced more than once is
written `$N=(...)` the first time and `$N` after; group ids are `#N`. Both are numbered in order
of first appearance, so equal docs give equal text.

`--debug-doc-eval <file>` runs the commands in a file and writes each result as `<length>\n<bytes>\n`:
`(doc D)`, `(print W TW TABS EOL)`, `(bench N W TW TABS EOL)`, `(dump)`, `(dumpx)`,
`(util NAME)` (a doc util applied to the current doc), `(pred NAME)`, `(text "...")` and
`(t NAME args...)` (a text helper), `(pathwalk)` (the path API over the json5 AST of the text).
The infra tests are made of these.

## JS printer

The port of `src/language-js/` for JavaScript and TypeScript lives in `src/pjs_*.s`, one file per Prettier
source file. A node type without a case refuses with `printer: node type not ported`; the parser
builds no Flow or JSX nodes.

### File map

| Prettier (`src/language-js/`) | Here | Status |
| --- | --- | --- |
| `printer.js`, `print/index.js` | `pjs_printer.s` | ported |
| `print/estree.js` | `pjs_estree.s` | ported |
| `print/statement.js` | `pjs_statement.s` | ported |
| `print/block.js` | `pjs_block.s` | ported |
| `print/expression-statement.js` | `pjs_expression_statement.s` | ported |
| `print/semicolon.js` | `pjs_semicolon.s` | ported |
| `print/misc.js` | `pjs_misc.s` | ported for babel's and babel-ts's node types |
| `print/literal.js` | `pjs_literal.s` | ported |
| `needs-parens.js` | `pjs_needs_parens.s` | ported for babel's and babel-ts's node types |
| `utils/index.js`, `utils/*.js` | `pjs_utils.s` | ported for babel's and babel-ts's node types |
| `print/call-expression.js` | `pjs_call_expression.s` | ported |
| `print/call-arguments.js` | `pjs_call_arguments.s` | ported, `ArgExpansionBailout` as a real catch (`pjs_try_print_call_argument`) |
| `print/member.js` | `pjs_member.s` | ported |
| `print/member-chain.js` | `pjs_member_chain.s` | ported |
| `print/assignment.js` | `pjs_assignment.s` | ported |
| `print/binaryish.js` | `pjs_binaryish.s` | ported, `experimentalOperatorPosition` included |
| `print/ternary.js` | `pjs_ternary.s` | ported, `experimentalTernaries` included |
| `print/ternary-old.js` | `pjs_ternary_old.s` | ported (no JSX mode) |
| `print/function.js` | `pjs_function.s` | ported |
| `print/function-parameters.js` | `pjs_function_parameters.s` | ported |
| `print/arrow-function.js` | `pjs_arrow_function.s` | ported |
| `print/object.js` | `pjs_object.s` | ported |
| `print/property.js` | `pjs_property.s` | ported; a number-like string key with 16 or 17 significant digits refuses |
| `print/array.js` | `pjs_array.s` | ported |
| `print/class.js` | `pjs_class.s` | ported |
| `print/module.js` | `pjs_module.s` | ported, `with` and `assert` attributes |
| `print/template-literal.js` | `pjs_template_literal.s` | ported, jest each tables included; `printTemplateExpression(s)` and the escape helpers are only used by embedders and are not ported |
| `embed/` | `pjs_embed.s` | detection ported: returns "``" for a blank embedded literal and refuses where Prettier would format CSS, GraphQL, HTML or Markdown |
| `comments/`, `print/comment.js` | `pjs_comments*.s` | see the comments port |
| `print/decorators.js` | `pjs_decorators.s` | ported, with `ClassAccessorProperty` (`accessor`) in `pjs_class.s` |
| `print/typescript.js` | `pjs_typescript.s` | ported; its `ts_cases` table follows `estree_cases` in `pjs_print_estree` |
| `print/type-annotation.js` | `pjs_type_annotation.s` | ported for babel-ts's node types |
| `print/type-parameters.js` | `pjs_type_parameters.s` | ported |
| `print/mapped-type.js` | `pjs_mapped_type.s` | ported for TSMappedType |
| `print/interface.js` | `pjs_interface.s` | ported for TSInterfaceDeclaration |
| `print/enum.js` | `pjs_enum.s` | ported; babel-ts builds no computed members |
| `print/cast-expression.js` | `pjs_cast_expression.s` | ported; `as`, `satisfies` or `!` on an object pattern refuses |
| `print/flow.js`, `print/jsx.js` | none | not ported: the parser builds no Flow or JSX nodes |

### JS printer hooks

`pjs_printer` in `pjs_printer.s` is the printer record for the JavaScript and TypeScript files. The comment
methods come from `src/language-js/comments/` and `print/comment.js`, ported in
`src/pjs_comments*.s`. The record names each symbol below as a weak reference: a hook that is
not linked in is 0, and the printer refuses a file with comments while any required hook is 0.

| Hook (`PR_*`) | Prettier | Symbol | Signature | Owner |
| --- | --- | --- | --- | --- |
| `PR_PRINT` | `print` (`print/index.js`) | `pjs_print` | `(node, args) -> rax doc` | printer |
| `PR_HAS_PRETTIER_IGNORE` | none (estree checks in `print`) | 0 | | |
| `PR_WILL_PRINT_OWN_COMMENTS` | `willPrintOwnComments` | `pjs_will_print_own_comments` | `() -> eax`, reads the path | comments |
| `PR_PRINT_COMMENT` | `printComment` | `pjs_print_comment` | `(comment) -> rax doc`, the comment is the path's top | comments |
| `PR_IS_BLOCK_COMMENT` | `isBlockComment` | `pjs_is_block_comment` | `(comment) -> eax` | comments |
| `PR_CAN_ATTACH_COMMENT` | `canAttachComment` | `pjs_can_attach_comment` | `(node) -> eax` | comments |
| `PR_GET_COMMENT_CHILD_NODES` | `getCommentChildNodes` | `pjs_get_comment_child_nodes` | `(node) -> rax VEC or 0`; 0 (undefined) for babel, so it may stay unlinked | comments |
| `PR_VISITOR_KEYS`, `PR_VISITOR_COUNT` | `getVisitorKeys` | `ast_visitor_keys`, `T_COUNT` | | generator |
| `PR_OWN_LINE` | `handleComments.ownLine` | `pjs_handlers_own_line` | 0-terminated list of `handler(comment, is_last) -> eax` | comments |
| `PR_END_OF_LINE` | `handleComments.endOfLine` | `pjs_handlers_end_of_line` | same | comments |
| `PR_REMAINING` | `handleComments.remaining` | `pjs_handlers_remaining` | same | comments |
| `PR_IS_GAP` | `isGap` | `pjs_is_gap` | `(start, end) -> eax`; undefined for babel, so it may stay unlinked | comments |

The utilities of `src/language-js/utils/` are in `pjs_utils.s`, named `pjs_` plus the Prettier
name in snake case (`isCallLikeExpression` is `pjs_is_call_like_expression`). The comment
handlers call them under those names. `hasComment` and `getComments` are `has_comment` and
`get_comments` in `comments.s`.

### Writing a print function

- A Prettier function `printFooBar` in `print/foo.js` is `pjs_print_foo_bar` in `pjs_foo.s`.
  `FUNC` makes every function global, so a file's private helpers carry a prefix of their own.
- A print function is `fn(node, args) -> rax doc`, the node being the top of the path. Functions
  that Prettier calls with the path alone read it with `path_value`, `path_parent` and so on.
- `pjs.inc` has the macros: `PROLOGUE n` and `EPILOGUE` save the callee-saved registers and give
  `n` quadword locals at `[rsp]`; `DMARK`, `DPUSH`, `DPUSHL` and `DARRAY` build an array on the
  scratch stack; `GROUP_RAX` and `INDENT_RAX` wrap `rax`; `PRINT off, key` is `print("key")`;
  `TYPE`, `ATTR` and `VLEN` test a node.
- `print("key", args)` is `print_field(offset, K_key, args)`; `print(["key", i])` is `print_elem`;
  `path.map(print, "key")` is `print_map`. A static args record (`ARGS_*`) stands for
  `{expandLastArg: true}` and the like; only args 0 is cached.
- Shared string docs are the `ps_*` globals in `pjs_printer.s`; others are `SDOC`s in the file.
- Keep Prettier's doc shape: the same groups, indents, lines and array nesting where `cleanDoc`,
  `stripTrailingHardline` or a `===` comparison looks at it, and the same doc pointer where
  Prettier reuses a printed doc. `--debug-doc` shows a divergence.
- Anything not ported refuses with `REFUSE "printer: <Prettier function or case>"`.
- `tests/stage3/printer/build.sh NAME` links a private `build/NAME/prettier-asm`;
  `tests/stage3/printer/check.mjs -e CODE` compares one input with Prettier, output and doc.

## JS comments

`pjs_comments.s` ports `src/language-js/comments/handle-comments.js` and `pjs_comment_print.s`
the rest of the JS printer's comment methods: `canAttachComment`, `getCommentChildNodes`,
`willPrintOwnComments`, `isGap`, `isBlockComment` (`printer-methods.js`), `printComment`
(`print/comment.js`), and `isLineComment`, `isTypeCastComment`, `isPrettierIgnoreComment` and
`hasNodeIgnoreComment` from `utils/`. Prettier's JS printer sets
`experimentalFeatures.avoidAstMutation`, so its handlers get the context in an object instead of
on the comment. Here the context stays in the comment's `CM_ENCL`, `CM_PREC` and `CM_FOLL`; no
print code of Prettier's reads those properties, so the output is the same.

The handler lists, in Prettier's order (a `-` entry is a gap: its node types are not parsed):

| `pjs_handlers_own_line` | `pjs_handlers_end_of_line` | `pjs_handlers_remaining` |
| --- | --- | --- |
| ignore | closure type cast | ignore |
| conditional expression | last function arg | if statement |
| last function arg | conditional expression | while |
| - last component arg (Flow) | module specifiers | object property assignment |
| member expression | if statement | comment in empty parens |
| if statement | while | method name |
| while | try statement | only comments |
| try statement | class | comment after arrow params |
| class | labeled statement | function name |
| for | call expression | break and continue |
| union type | property | TS function trailing |
| only comments | only comments | |
| module specifiers | variable declarator | |
| assignment pattern | break and continue | |
| method name | switch default case | |
| labeled statement | last union element in expression | |
| break and continue | last binary operator operand | |
| nested conditional expression | TS mapped type | |
| comments in destructuring pattern | | |
| TS mapped type | | |

Inside the handlers, branches for node types the parser does not build are marked `GAP` with the
types: Flow (`FunctionTypeParam`, `TypeAlias`, `ObjectTypeAnnotation`, `DeclareClass`,
`InterfaceDeclaration`, `mixins`, the union, intersection, conditional and array type
annotations, the component types), JSX (`willPrintOwnComments`), and the estree node types that
only the `typescript`, `flow` and other estree parsers give (`Property`, `MethodDefinition`,
`TSAbstractMethodDefinition`, `PropertyDefinition`, `TSEmptyBodyFunctionExpression`,
`ChainExpression`, and `getCommentChildNodes`, which returns a list only for those parsers).
`isGap` is defined for the Flow parsers only, so `pjs_is_gap` returns -1 (undefined).

A handler that sets Prettier's `node.prettierIgnore` sets `NF_PRETTIER_IGNORE` in `N_FLAGS`;
`comment.unignore` is `CF_UNIGNORE`. `is_prettier_ignore_comment` and `has_comment` with
`CC_PrettierIgnore` skip an unignored comment, and `pjs_has_ignore_comment` (Prettier's
`hasNodeIgnoreComment`) checks the flag and the comments. Dangling comments with a marker point
`CM_MARKER` at `pjs_marker_implements` or `pjs_marker_extends`; pass the same address to
`print_dangling_comments_ex`.

`--debug-comments --stdin-filepath x.js` parses the file, attaches its comments with the JS
hooks and writes one line per comment in source order:

```
<start> <end> <Block|Line|Interp> <ownLine|endOfLine|remaining> <leading|trailing|dangling> <NodeType> <nodeStart> <nodeEnd>[ marker=<m>][ unignore]
<start> <end> <type> <placement> unattached[ unignore]
prettierIgnore <NodeType> <start> <end>
```

The second form is a comment a handler took without attaching it (`handleIgnoreComments`); the
`prettierIgnore` lines list the nodes a handler flagged. Positions are UTF-16 offsets.
`--experimental-ternaries` sets the option for the handlers that read it.
`tests/stage3/comments/oracle.mjs` writes the same from Prettier: a plugin supplies Prettier's
`babel` (or `babel-ts`) parser and the estree printer with `print` wrapped, so the first print
call, made after `attachComments`, walks the AST and reads each node's `comments`.

`--debug-comment-docs` writes, per comment, its range and `printComment`'s doc printed alone and
inside `indent([hardline, doc])`, each as `<byte length>\n<text>\n`;
`tests/stage3/comments/print-run.mjs` compares that with the estree printer's `printComment`.

## TypeScript refusals

Prettier's CLI formats TypeScript with its `typescript` parser. The binary parses as `babel-ts`
does, so it refuses input where the two parsers disagree. On real and ts-fixtures the two give the
same output wherever both succeed (`tests/stage3/printer/ts-parsers.mjs`).
`tests/stage3/comments/ts-parsers-fuzz.mjs` inserts comments into those cases to find more
disagreements, and `ts-parsers-check.mjs` checks the binary on what it finds.

Accepted by babel-ts, rejected by the typescript parser (Prettier exits 2, the binary 3):

- a definite assignment assertion `x!` with an initializer or without a type
- a decorator on a method overload, a parameter property in a constructor overload
- a decorated parameter anywhere but a method, constructor or setter with a body in a class
  declaration, and a decorated `this`
- a generator or async function signature
- `<<` opening a superclass's type arguments
- a line break after a modifier following `export`

Accepted by both, with trees that print differently:

- a `<` that starts an expression and has a matching closing tag later, which babel-ts first
  tries to read as JSX
- `export default abstract` before a line break, an expression for typescript-estree
- `as`, `satisfies` or `!` on an object pattern (`({ a } as T) = b`), an ObjectExpression for
  typescript-estree
- `new` of an optional call inside parentheses or `!`, a ChainExpression for typescript-estree
- a comment in a method's signature after its key, in a template literal type, between a type
  parameter's modifiers and its name, in `export * as ns`, between `export` and `import`, in or
  next to an optional chain, or between a superclass's type arguments, a line break and
  `implements` (`pjs_check_ts_comments` in `pjs_comment_print.s`)

Accepted by the typescript parser, rejected by babel-ts: these are syntax errors here. In
ts-fixtures they are `static` with `abstract`, modifiers out of order or repeated, a parameter
after a rest parameter, computed enum members, an index signature with more than one parameter,
JSDoc types such as `?T` and `T!`, and `await` in a namespace. `readonly` on a type
that is not an array or tuple is another.

## Refusing

`REFUSE "reason"` never returns. Nothing is written to stdout before the whole file is formatted,
so refusing anywhere is safe. Refuse whenever the port would have to guess: syntax it does not
print, a comment it would not print, a Prettier error, text whose width it cannot measure.

## Not ported yet

- The config formats and options listed as refused above, and every CLI option not listed.
- Identifiers and whitespace outside strings and comments that are not ASCII. Comments that hold
  non-ASCII whitespace.
- `json-stringify` numbers that need a full double conversion: more than 15 significant
  digits, or magnitudes from 1e300 to 1e309 and from 1e-324 to 1e-300.
- HTML-style comments (`<!--`, `-->`), which Babel accepts in JSON files.
- Nesting deeper than 100. Prettier itself runs out of stack near 200 nested objects.
- Cursors (`cursor` docs, `cursorOffset`). The doc printer refuses a `cursor` doc.
- `printString`'s `__isInHtmlAttribute` case.
