// Generates the JS parser's tables from one spec:
//   src/ast_types.s       node type names, per-type field descriptors, keyword buckets,
//                         operator and kind strings
//   src/defs.inc          the block between the "generated" markers: T_*, NA_*, J_*, KW_*
// Run after changing the spec: node tests/stage3/parser/gen-ast-types.mjs
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");

// AST boolean attributes (N_ATTR bits). The key is Babel's property name.
const ATTRS = ["parenthesized", "async", "generator", "computed", "shorthand", "optional", "static",
  "prefix", "tail", "method", "delegate", "await", "deprecatedAssertSyntax",
  // TypeScript
  "abstract", "declare", "readonly", "override", "definite", "const", "in", "out", "asserts", "isExport",
  "global"];

// Field kinds:
//   node F      child node in slot F (0 = absent)
//   vec F       VEC of child nodes in slot F (0 or empty = absent; 0 items are holes)
//   bool NAME   N_ATTR bit
//   flag F      0/1 in slot F (BooleanLiteral.value, kept where the JSON printer reads it)
//   op F        operator code in slot F (string from ast_codes)
//   kind F      kind code in slot F (string from ast_codes)
//   str F       string: pointer in slot F, byte length in slot F+1 (pointer 0 = null)
//   tri F       0 absent, 1 true, else a code whose string is the value (TSMappedType's "+" and "-")
//   name        Identifier.name: the source text of the node's range, except that F7, when set,
//               is the name's byte length (the range takes in `?` or a type annotation) and F0,
//               when set, is 1 + the name's offset (TSTypeParameter.name, whose range starts
//               at the parameter's modifiers)
//   inner       the node's source text without its first and last byte (DirectiveLiteral.value)
// Babel's `extra.parenthesized` and `extra.deprecatedAssertSyntax` are bool attributes.
const EXPR = [["parenthesized", "bool"]];
// TypeScript slots: F4 typeParameters (declared, or the type arguments Babel also calls
// typeParameters), F5 returnType or typeAnnotation, F6 decorators, F7 accessibility.
const TPARAMS = ["typeParameters", "node", 4];
const FN_TS = [TPARAMS, ["returnType", "node", 5]];
const BINDING_TS = [["typeAnnotation", "node", 5], ["decorators", "vec", 6], ["optional", "bool"]];
const MEMBER_TS = [["decorators", "vec", 6], ["accessibility", "kind", 7], ["abstract", "bool"], ["override", "bool"],
  ["optional", "bool"]];
const PROP_TS = [["typeAnnotation", "node", 5], ...MEMBER_TS, ["declare", "bool"], ["readonly", "bool"], ["definite", "bool"]];
const CLASS_TS = [["superTypeParameters", "node", 3], TPARAMS, ["implements", "vec", 5], ["decorators", "vec", 6],
  ["abstract", "bool"], ["declare", "bool"]];
const SIGNATURE = [["parameters", "vec", 1], TPARAMS, ["typeAnnotation", "node", 5]];
const types = [
  // Stage 1 types keep their numbers and slots: the JSON printer reads them.
  ["JsonRoot", ["node", "node", 0]],
  ["ObjectExpression", ["properties", "vec", 0], ...EXPR],
  ["ArrayExpression", ["elements", "vec", 0], ...EXPR],
  ["ObjectProperty", ["key", "node", 0], ["value", "node", 1], ["computed", "bool"], ["shorthand", "bool"]],
  ["UnaryExpression", ["argument", "node", 0], ["operator", "op", 1], ["prefix", "bool"], ...EXPR],
  ["StringLiteral", ["value", "str", 0], ...EXPR],
  ["NumericLiteral", ...EXPR],
  ["NullLiteral", ...EXPR],
  ["BooleanLiteral", ["value", "flag", 0], ...EXPR],
  ["Identifier", ["name", "name"], ...BINDING_TS, ...EXPR],
  ["TemplateLiteral", ["quasis", "vec", 0], ["expressions", "vec", 1], ...EXPR],
  ["TemplateElement", ["cooked", "str", 0], ["tail", "bool"]],
  // JS
  ["File", ["program", "node", 0]],
  ["Program", ["body", "vec", 0], ["directives", "vec", 1], ["sourceType", "kind", 2]],
  ["InterpreterDirective"],
  ["Directive", ["value", "node", 0]],
  ["DirectiveLiteral", ["value", "inner"]],
  ["BlockStatement", ["body", "vec", 0], ["directives", "vec", 1]],
  ["EmptyStatement"],
  ["DebuggerStatement"],
  ["ExpressionStatement", ["expression", "node", 0]],
  ["IfStatement", ["test", "node", 0], ["consequent", "node", 1], ["alternate", "node", 2]],
  ["LabeledStatement", ["label", "node", 0], ["body", "node", 1]],
  ["BreakStatement", ["label", "node", 0]],
  ["ContinueStatement", ["label", "node", 0]],
  ["WithStatement", ["object", "node", 0], ["body", "node", 1]],
  ["SwitchStatement", ["discriminant", "node", 0], ["cases", "vec", 1]],
  ["SwitchCase", ["test", "node", 0], ["consequent", "vec", 1]],
  ["ReturnStatement", ["argument", "node", 0]],
  ["ThrowStatement", ["argument", "node", 0]],
  ["TryStatement", ["block", "node", 0], ["handler", "node", 1], ["finalizer", "node", 2]],
  ["CatchClause", ["param", "node", 0], ["body", "node", 1]],
  ["WhileStatement", ["test", "node", 0], ["body", "node", 1]],
  ["DoWhileStatement", ["test", "node", 0], ["body", "node", 1]],
  ["ForStatement", ["init", "node", 0], ["test", "node", 1], ["update", "node", 2], ["body", "node", 3]],
  ["ForInStatement", ["left", "node", 0], ["right", "node", 1], ["body", "node", 2]],
  ["ForOfStatement", ["left", "node", 0], ["right", "node", 1], ["body", "node", 2], ["await", "bool"]],
  ["VariableDeclaration", ["declarations", "vec", 0], ["kind", "kind", 1], ["declare", "bool"]],
  ["VariableDeclarator", ["id", "node", 0], ["init", "node", 1], ["definite", "bool"]],
  // Functions share slots: F0 id or key, F1 params, F2 body, F3 kind.
  ["FunctionDeclaration", ["id", "node", 0], ["params", "vec", 1], ["body", "node", 2], ["async", "bool"], ["generator", "bool"],
    ...FN_TS, ["declare", "bool"]],
  ["FunctionExpression", ["id", "node", 0], ["params", "vec", 1], ["body", "node", 2], ["async", "bool"], ["generator", "bool"],
    ...FN_TS, ...EXPR],
  ["ArrowFunctionExpression", ["params", "vec", 1], ["body", "node", 2], ["async", "bool"], ...FN_TS, ...EXPR],
  ["ObjectMethod", ["key", "node", 0], ["params", "vec", 1], ["body", "node", 2], ["kind", "kind", 3],
    ["async", "bool"], ["generator", "bool"], ["computed", "bool"], ["method", "bool"], ...FN_TS],
  ["ClassMethod", ["key", "node", 0], ["params", "vec", 1], ["body", "node", 2], ["kind", "kind", 3],
    ["async", "bool"], ["generator", "bool"], ["computed", "bool"], ["static", "bool"], ...FN_TS, ...MEMBER_TS],
  ["ClassPrivateMethod", ["key", "node", 0], ["params", "vec", 1], ["body", "node", 2], ["kind", "kind", 3],
    ["async", "bool"], ["generator", "bool"], ["static", "bool"], ...FN_TS, ...MEMBER_TS],
  ["ClassProperty", ["key", "node", 0], ["value", "node", 1], ["computed", "bool"], ["static", "bool"], ...PROP_TS],
  ["ClassPrivateProperty", ["key", "node", 0], ["value", "node", 1], ["static", "bool"], ...PROP_TS],
  ["StaticBlock", ["body", "vec", 0]],
  ["ClassBody", ["body", "vec", 0]],
  ["ClassDeclaration", ["id", "node", 0], ["superClass", "node", 1], ["body", "node", 2], ...CLASS_TS],
  ["ClassExpression", ["id", "node", 0], ["superClass", "node", 1], ["body", "node", 2], ...CLASS_TS, ...EXPR],
  ["PrivateName", ["id", "node", 0]],
  // Patterns reuse the slots of the expressions they are converted from.
  ["ObjectPattern", ["properties", "vec", 0], ...BINDING_TS, ...EXPR],
  ["ArrayPattern", ["elements", "vec", 0], ...BINDING_TS, ...EXPR],
  ["AssignmentPattern", ["left", "node", 0], ["right", "node", 1], ...BINDING_TS, ...EXPR],
  ["RestElement", ["argument", "node", 0], ...BINDING_TS],
  ["SpreadElement", ["argument", "node", 0]],
  // Expressions
  ["ThisExpression", ...EXPR],
  ["Super"],
  ["RegExpLiteral", ["pattern", "str", 0], ["flags", "str", 2], ...EXPR],
  ["BigIntLiteral", ["value", "str", 0], ...EXPR],
  ["ParenthesizedExpression", ["expression", "node", 0], ...EXPR],
  ["SequenceExpression", ["expressions", "vec", 0], ...EXPR],
  ["UpdateExpression", ["argument", "node", 0], ["operator", "op", 1], ["prefix", "bool"], ...EXPR],
  ["BinaryExpression", ["left", "node", 0], ["right", "node", 1], ["operator", "op", 2], ...EXPR],
  ["LogicalExpression", ["left", "node", 0], ["right", "node", 1], ["operator", "op", 2], ...EXPR],
  ["AssignmentExpression", ["left", "node", 0], ["right", "node", 1], ["operator", "op", 2], ...EXPR],
  ["ConditionalExpression", ["test", "node", 0], ["consequent", "node", 1], ["alternate", "node", 2], ...EXPR],
  ["CallExpression", ["callee", "node", 0], ["arguments", "vec", 1], TPARAMS, ...EXPR],
  ["OptionalCallExpression", ["callee", "node", 0], ["arguments", "vec", 1], ["optional", "bool"], TPARAMS, ...EXPR],
  ["NewExpression", ["callee", "node", 0], ["arguments", "vec", 1], TPARAMS, ...EXPR],
  ["MemberExpression", ["object", "node", 0], ["property", "node", 1], ["computed", "bool"], ...EXPR],
  ["OptionalMemberExpression", ["object", "node", 0], ["property", "node", 1], ["computed", "bool"], ["optional", "bool"], ...EXPR],
  ["TaggedTemplateExpression", ["tag", "node", 0], ["quasi", "node", 1], TPARAMS, ...EXPR],
  ["YieldExpression", ["argument", "node", 0], ["delegate", "bool"], ...EXPR],
  ["AwaitExpression", ["argument", "node", 0], ...EXPR],
  ["MetaProperty", ["meta", "node", 0], ["property", "node", 1], ...EXPR],
  ["ImportExpression", ["source", "node", 0], ["options", "node", 1], ...EXPR],
  // Modules
  // importKind and exportKind are set in TypeScript files only, as Babel does.
  ["ImportDeclaration", ["specifiers", "vec", 0], ["source", "node", 1], ["attributes", "vec", 2], ["deprecatedAssertSyntax", "bool"],
    ["importKind", "kind", 3]],
  ["ImportSpecifier", ["imported", "node", 0], ["local", "node", 1], ["importKind", "kind", 2]],
  ["ImportDefaultSpecifier", ["local", "node", 0]],
  ["ImportNamespaceSpecifier", ["local", "node", 0]],
  ["ImportAttribute", ["key", "node", 0], ["value", "node", 1]],
  ["ExportNamedDeclaration", ["declaration", "node", 0], ["specifiers", "vec", 1], ["source", "node", 2], ["attributes", "vec", 3], ["deprecatedAssertSyntax", "bool"],
    ["exportKind", "kind", 4]],
  ["ExportSpecifier", ["local", "node", 0], ["exported", "node", 1], ["exportKind", "kind", 2]],
  ["ExportNamespaceSpecifier", ["exported", "node", 0]],
  ["ExportDefaultDeclaration", ["declaration", "node", 0], ["exportKind", "kind", 1]],
  ["ExportAllDeclaration", ["source", "node", 0], ["attributes", "vec", 1], ["deprecatedAssertSyntax", "bool"], ["exportKind", "kind", 2]],
  // Decorators and TypeScript, in the shape Babel's typescript plugin gives after Prettier's
  // postprocess (TSParenthesizedType and one-member unions are gone, TSTypeParameter.name is an
  // Identifier, TSMappedType has key and constraint, TSEnumDeclaration has a TSEnumBody).
  ["Decorator", ["expression", "node", 0]],
  ["ClassAccessorProperty", ["key", "node", 0], ["value", "node", 1], ["computed", "bool"], ["static", "bool"], ...PROP_TS],
  ["TSParameterProperty", ["parameter", "node", 0], ["decorators", "vec", 6], ["accessibility", "kind", 7],
    ["readonly", "bool"], ["override", "bool"]],
  ["TSDeclareFunction", ["id", "node", 0], ["params", "vec", 1], ["async", "bool"], ["generator", "bool"], ...FN_TS,
    ["declare", "bool"]],
  ["TSDeclareMethod", ["key", "node", 0], ["params", "vec", 1], ["kind", "kind", 3], ["async", "bool"], ["generator", "bool"],
    ["computed", "bool"], ["static", "bool"], ...FN_TS, ...MEMBER_TS],
  ["TSQualifiedName", ["left", "node", 0], ["right", "node", 1]],
  ["TSCallSignatureDeclaration", ...SIGNATURE],
  ["TSConstructSignatureDeclaration", ...SIGNATURE],
  ["TSPropertySignature", ["key", "node", 0], ["typeAnnotation", "node", 5], ["computed", "bool"], ["optional", "bool"],
    ["readonly", "bool"]],
  ["TSMethodSignature", ["key", "node", 0], ...SIGNATURE, ["kind", "kind", 3], ["computed", "bool"], ["optional", "bool"]],
  ["TSIndexSignature", ["parameters", "vec", 1], ["typeAnnotation", "node", 5], ["readonly", "bool"], ["static", "bool"]],
  ["TSAnyKeyword"], ["TSBooleanKeyword"], ["TSBigIntKeyword"], ["TSIntrinsicKeyword"], ["TSNeverKeyword"],
  ["TSNullKeyword"], ["TSNumberKeyword"], ["TSObjectKeyword"], ["TSStringKeyword"], ["TSSymbolKeyword"],
  ["TSUndefinedKeyword"], ["TSUnknownKeyword"], ["TSVoidKeyword"], ["TSThisType"],
  ["TSFunctionType", ...SIGNATURE],
  ["TSConstructorType", ...SIGNATURE, ["abstract", "bool"]],
  ["TSTypeReference", ["typeName", "node", 0], TPARAMS],
  ["TSTypePredicate", ["parameterName", "node", 0], ["typeAnnotation", "node", 5], ["asserts", "bool"]],
  ["TSTypeQuery", ["exprName", "node", 0], TPARAMS],
  ["TSTypeLiteral", ["members", "vec", 0]],
  ["TSArrayType", ["elementType", "node", 0]],
  ["TSTupleType", ["elementTypes", "vec", 0]],
  ["TSOptionalType", ["typeAnnotation", "node", 5]],
  ["TSRestType", ["typeAnnotation", "node", 5]],
  ["TSNamedTupleMember", ["label", "node", 0], ["elementType", "node", 1], ["optional", "bool"]],
  ["TSUnionType", ["types", "vec", 0]],
  ["TSIntersectionType", ["types", "vec", 0]],
  ["TSConditionalType", ["checkType", "node", 0], ["extendsType", "node", 1], ["trueType", "node", 2], ["falseType", "node", 3]],
  ["TSInferType", ["typeParameter", "node", 0]],
  ["TSTypeOperator", ["typeAnnotation", "node", 5], ["operator", "kind", 1]],
  ["TSIndexedAccessType", ["objectType", "node", 0], ["indexType", "node", 1]],
  ["TSMappedType", ["key", "node", 0], ["constraint", "node", 1], ["nameType", "node", 2], ["typeAnnotation", "node", 5],
    ["readonly", "tri", 3], ["optional", "tri", 4]],
  ["TSLiteralType", ["literal", "node", 0]],
  ["TSExpressionWithTypeArguments", ["expression", "node", 0], TPARAMS],
  ["TSInterfaceDeclaration", ["id", "node", 0], ["extends", "vec", 1], ["body", "node", 2], TPARAMS, ["declare", "bool"]],
  ["TSInterfaceBody", ["body", "vec", 0]],
  ["TSTypeAliasDeclaration", ["id", "node", 0], TPARAMS, ["typeAnnotation", "node", 5], ["declare", "bool"]],
  ["TSInstantiationExpression", ["expression", "node", 0], TPARAMS, ...EXPR],
  ["TSAsExpression", ["expression", "node", 0], ["typeAnnotation", "node", 5], ...EXPR],
  ["TSSatisfiesExpression", ["expression", "node", 0], ["typeAnnotation", "node", 5], ...EXPR],
  ["TSTypeAssertion", ["expression", "node", 0], ["typeAnnotation", "node", 5], ...EXPR],
  ["TSNonNullExpression", ["expression", "node", 0], ...EXPR],
  ["TSEnumDeclaration", ["id", "node", 0], ["body", "node", 1], ["const", "bool"], ["declare", "bool"]],
  ["TSEnumBody", ["members", "vec", 0]],
  ["TSEnumMember", ["id", "node", 0], ["initializer", "node", 1]],
  ["TSModuleDeclaration", ["id", "node", 0], ["body", "node", 1], ["kind", "kind", 3], ["declare", "bool"], ["global", "bool"]],
  ["TSModuleBlock", ["body", "vec", 0]],
  ["TSImportType", ["argument", "node", 0], ["options", "node", 1], ["qualifier", "node", 2], TPARAMS],
  ["TSImportEqualsDeclaration", ["id", "node", 0], ["moduleReference", "node", 1], ["importKind", "kind", 3], ["isExport", "bool"]],
  ["TSExternalModuleReference", ["expression", "node", 0]],
  ["TSExportAssignment", ["expression", "node", 0]],
  ["TSNamespaceExportDeclaration", ["id", "node", 0]],
  ["TSTypeAnnotation", ["typeAnnotation", "node", 5]],
  ["TSTypeParameterInstantiation", ["params", "vec", 0]],
  ["TSTypeParameterDeclaration", ["params", "vec", 0]],
  ["TSTypeParameter", ["name", "node", 0], ["constraint", "node", 1], ["default", "node", 2], ["in", "bool"], ["out", "bool"],
    ["const", "bool"]],
  // Only while parsing: `(a: T)` before `=>` (Babel's TSTypeCastExpression), and `(T)` in a type,
  // which Prettier's postprocess replaces by T.
  ["TSTypeCastExpression", ["expression", "node", 0], ["typeAnnotation", "node", 5]],
  ["TSParenthesizedType", ["typeAnnotation", "node", 5]],
];

// Prettier's visitor keys (language-js/traverse/visitor-keys.evaluate.js), read from the object
// literal that the bundled estree plugin inlines. Comment attachment and the printer walk children
// in this order. A type Prettier does not know keeps the spec's order.
const VISIT = (() => {
  const src = fs.readFileSync(path.join(ROOT, "node_modules/prettier/plugins/estree.js"), "utf8");
  const at = src.indexOf('TSAsExpression:["expression","typeAnnotation"]');
  if (at < 0) throw new Error("visitor keys not found in prettier/plugins/estree.js");
  let i = at, depth = 0;
  for (; i > 0; i--) { if (src[i] === "}") depth++; else if (src[i] === "{") { if (!depth) break; depth--; } }
  let j = i;
  for (depth = 0; j < src.length; j++) { if (src[j] === "{") depth++; else if (src[j] === "}" && !--depth) break; }
  const keys = JSON.parse(src.slice(i, j + 1).replace(/([{,])([A-Za-z]\w*):/g, '$1"$2":'));
  if (!keys.Program || !keys.JsonRoot) throw new Error("visitor keys look wrong");
  return keys;
})();

// Token codes. Single-character punctuators are their ASCII code; the others start at 0x80.
// Operator codes in the AST are the token codes, so `+` is 0x2B in UnaryExpression.operator
// as the JSON printer expects.
const TOKENS = [["EOF", 0], ["NAME", 1], ["STRING", 2], ["NUM", 3], ["BIGINT", 4], ["TEMPLATE", 5],
  ["REGEX", 6], ["PRIVATE", 7]];
const SINGLE = { LPAREN: "(", RPAREN: ")", LBRACK: "[", RBRACK: "]", LBRACE: "{", RBRACE: "}", SEMI: ";",
  COMMA: ",", COLON: ":", QUESTION: "?", DOT: ".", AT: "@", HASH: "#", BANG: "!", TILDE: "~", PLUS: "+",
  MINUS: "-", STAR: "*", SLASH: "/", PERCENT: "%", LT: "<", GT: ">", EQ: "=", AMP: "&", PIPE: "|",
  CARET: "^", BACKQUOTE: "`" };
const MULTI = [["EQ2", "=="], ["NE", "!="], ["EQ3", "==="], ["NE2", "!=="], ["LE", "<="], ["GE", ">="],
  ["SHL", "<<"], ["SHR", ">>"], ["USHR", ">>>"], ["EXP", "**"], ["AND2", "&&"], ["OR2", "||"],
  ["NULLISH", "??"], ["INC", "++"], ["DEC", "--"], ["ARROW", "=>"], ["ELLIPSIS", "..."], ["QDOT", "?."],
  ["ADD_EQ", "+="], ["SUB_EQ", "-="], ["MUL_EQ", "*="], ["DIV_EQ", "/="], ["MOD_EQ", "%="],
  ["EXP_EQ", "**="], ["SHL_EQ", "<<="], ["SHR_EQ", ">>="], ["USHR_EQ", ">>>="], ["AND_EQ", "&="],
  ["OR_EQ", "|="], ["XOR_EQ", "^="], ["AND2_EQ", "&&="], ["OR2_EQ", "||="], ["NULLISH_EQ", "??="],
  // operator codes only (keywords)
  ["TYPEOF", "typeof"], ["VOID", "void"], ["DELETE", "delete"], ["IN", "in"], ["INSTANCEOF", "instanceof"],
];
// Kind strings share the code space, from 0xD0.
const KINDS = ["var", "let", "const", "get", "set", "method", "constructor", "module", "script",
  // TypeScript: accessibility, importKind and exportKind, TSModuleDeclaration.kind, TSTypeOperator.operator
  "private", "protected", "public", "value", "type", "typeof", "global", "namespace", "keyof", "unique", "readonly"];

// Keywords and contextual words the lexer recognizes. Words up to KW_LAST_RESERVED can never be
// identifiers.
const KEYWORDS = ["break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete",
  "do", "else", "export", "extends", "finally", "for", "function", "if", "import", "in", "instanceof",
  "new", "return", "super", "switch", "this", "throw", "try", "typeof", "var", "void", "while", "with",
  "null", "true", "false", "enum",
  "yield", "let", "static", "implements", "interface", "package", "private", "protected", "public",
  "await", "async", "of", "get", "set", "from", "as", "target", "meta", "constructor", "using", "module",
  "accessor", "source", "defer", "assert", "arguments", "eval", "prototype",
  // TypeScript
  "type", "namespace", "declare", "abstract", "readonly", "keyof", "unique", "infer", "is", "asserts",
  "satisfies", "global", "require", "override", "out", "intrinsic", "any", "unknown", "never", "string",
  "number", "boolean", "bigint", "symbol", "object", "undefined"];
const LAST_RESERVED = "enum";

// Binary precedence by token code (Babel's binop values); `**` is right-associative.
const PREC = { "??": 1, "||": 1, "&&": 2, "|": 3, "^": 4, "&": 5, "==": 6, "!=": 6, "===": 6, "!==": 6,
  "<": 7, ">": 7, "<=": 7, ">=": 7, in: 7, instanceof: 7, "<<": 8, ">>": 8, ">>>": 8, "+": 9, "-": 9,
  "*": 10, "/": 10, "%": 10, "**": 11 };

// ------------------------------------------------------------------ build
const codes = new Map(); // code -> string
const tokConsts = [];
for (const [n, v] of TOKENS) tokConsts.push([`J_${n}`, v]);
for (const [n, s] of Object.entries(SINGLE)) { tokConsts.push([`J_${n}`, s.charCodeAt(0)]); codes.set(s.charCodeAt(0), s); }
MULTI.forEach(([n, s], i) => { tokConsts.push([`J_${n}`, 0x80 + i]); codes.set(0x80 + i, s); });
if (0x80 + MULTI.length > 0xd0) throw new Error("token codes overflow");
KINDS.forEach((k, i) => { tokConsts.push([`KD_${k.toUpperCase()}`, 0xd0 + i]); codes.set(0xd0 + i, k); });
const codeOf = (s) => { for (const [c, v] of codes) if (v === s) return c; throw new Error(s); };

const jsSort = (a, b) => (a < b ? -1 : a > b ? 1 : 0);
const lines = [];
const out = (s = "") => lines.push(s);
out("# Generated by tests/stage3/parser/gen-ast-types.mjs. Do not edit.");
out('.include "defs.inc"');
out("");
out("    .section .rodata");
out("# Node type names, indexed by T_*.");
out("    .balign 8");
out("    .globl ast_type_names");
out("ast_type_names:");
out("    .quad 0");
types.forEach(([name]) => out(`    .quad tn_${name}`));
types.forEach(([name]) => out(`tn_${name}: .asciz "${name}"`));
out("");
out("# Field descriptors, indexed by T_*. Props, then a 0 byte, then children, then a 0 byte.");
out("# Each entry: kind byte (FK_*), argument byte (slot offset or attribute bit), key as asciz.");
out("# Both lists are sorted by key as JavaScript sorts strings.");
out("    .balign 8");
out("    .globl ast_type_fields");
out("ast_type_fields:");
out("    .quad td_none");
types.forEach(([name]) => out(`    .quad td_${name}`));
out("td_none: .byte 0, 0");
const FK = { bool: 1, flag: 2, op: 3, kind: 4, str: 5, name: 6, inner: 7, node: 8, vec: 9, tri: 10 };
for (const [name, ...fields] of types) {
  const props = fields.filter((f) => !["node", "vec"].includes(f[1])).sort((a, b) => jsSort(a[0], b[0]));
  const kids = fields.filter((f) => ["node", "vec"].includes(f[1])).sort((a, b) => jsSort(a[0], b[0]));
  out(`td_${name}:`);
  for (const f of [...props, null, ...kids, null]) {
    if (f === null) { out("    .byte 0"); continue; }
    const [key, kind, arg] = f;
    let a = 0;
    if (kind === "bool") { a = ATTRS.indexOf(key); if (a < 0) throw new Error(key); }
    else if (["flag", "op", "kind", "str", "node", "vec", "tri"].includes(kind)) a = 24 + 8 * arg;
    out(`    .byte ${FK[kind]}, ${a}`);
    out(`    .asciz "${key}"`);
  }
}
out("");
out("# Visitor keys in Prettier's order, indexed by T_*: child slot offsets (| 0x80 for a VEC),");
out("# 0-terminated. The same format as visitor_keys in comments.s.");
out("    .balign 8");
out("    .globl ast_visitor_keys");
out("ast_visitor_keys:");
out("    .quad vk_t_none");
types.forEach(([name]) => out(`    .quad vk_t_${name}`));
out("vk_t_none: .byte 0");
for (const [name, ...fields] of types) {
  const kids = fields.filter((f) => ["node", "vec"].includes(f[1]));
  const order = VISIT[name] ? VISIT[name].filter((k) => kids.some((f) => f[0] === k)) : kids.map((f) => f[0]);
  if (order.length !== kids.length || !kids.every((f) => order.includes(f[0]))) throw new Error(`visitor order of ${name}`);
  const bytes = order.map((k) => { const f = kids.find((x) => x[0] === k); return (24 + 8 * f[2]) | (f[1] === "vec" ? 0x80 : 0); });
  out(`vk_t_${name}: .byte ${[...bytes, 0].join(", ")}`);
}
out("");
out("# Operator and kind strings, indexed by code; 0 where a code has no string.");
out("    .balign 8");
out("    .globl ast_codes");
out("ast_codes:");
for (let c = 0; c < 256; c++) out(codes.has(c) ? `    .quad cs_${c}` : "    .quad 0");
for (const [c, s] of codes) out(`cs_${c}: .asciz "${s.replace(/\\/g, "\\\\")}"`);
out("");
out("# Binary operator precedence by token code (0: not a binary operator).");
out("    .globl ast_binop_prec");
out("ast_binop_prec:");
const prec = new Array(256).fill(0);
for (const [s, p] of Object.entries(PREC)) prec[codeOf(s)] = p;
for (let c = 0; c < 256; c += 16) out(`    .byte ${prec.slice(c, c + 16).join(", ")}`);
out("");
out("# Keywords by first letter: index of 26 pointers; each bucket holds entries");
out("# (length byte, KW_* byte, letters) and ends with a 0 length.");
out("    .balign 8");
out("    .globl kw_buckets");
out("kw_buckets:");
const letters = "abcdefghijklmnopqrstuvwxyz";
for (const l of letters) out(KEYWORDS.some((k) => k[0] === l) ? `    .quad kwb_${l}` : "    .quad kwb_empty");
out("kwb_empty: .byte 0");
for (const l of letters) {
  const ks = KEYWORDS.filter((k) => k[0] === l);
  if (!ks.length) continue;
  out(`kwb_${l}:`);
  for (const k of ks) out(`    .byte ${k.length}, ${KEYWORDS.indexOf(k) + 1}\n    .ascii "${k}"`);
  out("    .byte 0");
}
out("");
out("# ASCII character classes for the JS lexer (CC_*): 0 other, 1 space, 2 line feed,");
out("# 3 identifier start, 4 digit, 5 quote, 6 punctuator.");
out("    .globl js_char_class");
out("js_char_class:");
const cls = new Array(128).fill(0);
for (const c of [0x20, 0x09, 0x0b, 0x0c]) cls[c] = 1;
cls[0x0a] = 2; cls[0x0d] = 2;
for (let c = 0; c < 128; c++) {
  const ch = String.fromCharCode(c);
  if (/[A-Za-z$_]/.test(ch)) cls[c] = 3;
  else if (/[0-9]/.test(ch)) cls[c] = 4;
  else if (ch === '"' || ch === "'") cls[c] = 5;
  else if ("{}()[];,:?.@#!~+-*/%<>=&|^`".includes(ch)) cls[c] = 6;
}
for (let c = 0; c < 128; c += 16) out(`    .byte ${cls.slice(c, c + 16).join(", ")}`);
fs.writeFileSync(path.join(ROOT, "src/ast_types.s"), lines.join("\n") + "\n");

// defs.inc block
const d = [];
d.push("# BEGIN generated by tests/stage3/parser/gen-ast-types.mjs");
types.forEach(([name], i) => d.push(`.equ T_${name}, ${i + 1}`));
d.push(`.equ T_COUNT, ${types.length + 1}`);
ATTRS.forEach((a, i) => d.push(`.equ NA_${a.replace(/[A-Z]/g, (m) => "_" + m).toUpperCase()}, ${1 << i}`));
for (const [n, v] of tokConsts) d.push(`.equ ${n}, 0x${v.toString(16)}`);
KEYWORDS.forEach((k, i) => d.push(`.equ KW_${k.toUpperCase()}, ${i + 1}`));
d.push(`.equ KW_LAST_RESERVED, ${KEYWORDS.indexOf(LAST_RESERVED) + 1}`);
for (const [k, v] of Object.entries(FK)) d.push(`.equ FK_${k.toUpperCase()}, ${v}`);
// Path keys (K_*, path.key): one per child field name; the first ones keep their stage 1 numbers.
const KEYS = ["node", "properties", "elements", "key", "value", "argument", "quasis", "expressions", "comments"];
for (const [, ...fields] of types) for (const [k, kind] of fields) if ((kind === "node" || kind === "vec") && !KEYS.includes(k)) KEYS.push(k);
d.push(".equ K_ROOT, 0");
KEYS.forEach((k, i) => d.push(`.equ K_${k}, ${i + 1}`));
d.push(`.equ K_COUNT, ${KEYS.length + 1}`);
d.push("# END generated");
const defsPath = path.join(ROOT, "src/defs.inc");
const defs = fs.readFileSync(defsPath, "utf8");
const re = /# BEGIN generated by tests\/stage3\/parser\/gen-ast-types\.mjs\n[\s\S]*?# END generated\n/;
if (!re.test(defs)) throw new Error("markers missing in defs.inc");
fs.writeFileSync(defsPath, defs.replace(re, d.join("\n") + "\n"));
console.log(`${types.length} node types, ${KEYWORDS.length} keywords`);
