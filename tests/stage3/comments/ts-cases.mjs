// Targeted cases for the handlers and branches of handle-comments.js that need TypeScript node
// types. They run through babel-ts on Prettier's side (see oracle.mjs).
const cases = [
  // handleIgnoreComments, handleTSMappedTypeComments
  ["mapped-ignore", "type A = {\n  // prettier-ignore\n  [K in keyof T]:   T[K];\n};\n"],
  ["mapped-ignore-remaining", "type A = { /* prettier-ignore */ [K in keyof T]: T[K] };\n"],
  ["mapped-dangling", "type A = {\n  // c\n  [K in keyof T]: T[K];\n};\n"],
  ["mapped-dangling-eol", "type A = { // c\n  [K in keyof T]: T[K];\n};\n"],
  ["mapped-after-key", "type A = {\n  [K in keyof T]: // c\n  T[K];\n};\n"],
  // handleUnionTypeComments, handleLastUnionElementInExpression
  ["union-ownline", "type A =\n  | B\n  // c\n  | C;\n"],
  ["union-ignore", "type A =\n  | B\n  // prettier-ignore\n  | C<   D >;\n"],
  ["union-ignore-first", "type A =\n  // prettier-ignore\n  | B<  C >\n  | D;\n"],
  ["union-last-array", "type Foo = (\n  | \"thing1\" // Comment1\n  | \"thing2\" // Comment2\n)[];\n"],
  ["union-last-intersection", "type Foo = (\n  | \"thing1\" // Comment3\n  | \"thing2\" // Comment4\n) & Bar;\n"],
  // handleMethodNameComments
  ["declare-method-name", "class A {\n  m /* c */ (): void;\n}\n"],
  ["decorator-member", "class A {\n  @dec\n  // c\n  m() {}\n}\n"],
  ["decorator-member-eol", "class A {\n  @dec // c\n  p = 1;\n}\n"],
  ["decorator-member-block", "class A {\n  @dec /* c */ p = 1;\n}\n"],
  ["decorator-param-property", "class A {\n  constructor(@dec // c\n  private a: string) {}\n}\n"],
  // handleCommentsInDestructuringPattern
  ["destructuring-ownline", "const {\n  a,\n  // c\n}: Foo = foo();\n"],
  ["destructuring-empty", "const {\n  // c\n}: Foo = foo();\n"],
  ["destructuring-array", "const [\n  a,\n  // c\n]: Foo = foo();\n"],
  // handleTSFunctionTrailingComments
  ["method-signature", "interface A {\n  m(): void /* c */;\n}\n"],
  ["declare-function", "declare function f(): void /* c */;\n"],
  // isRealFunctionLikeNode for TS types, TSParameterProperty
  ["signature-last-param", "interface A {\n  m(\n    a: string,\n    // c\n  ): void;\n}\n"],
  ["function-type-empty-parens", "type F = (/* c */) => void;\n"],
  ["constructor-type-param", "type F = new (a: string // c\n) => void;\n"],
  ["call-signature", "interface A {\n  (a // c\n  ): void;\n}\n"],
  ["param-property-last", "class A {\n  constructor(private a: string // c\n  ) {}\n}\n"],
  // handleClassComments: decorators, typeParameters, implements, interfaces
  ["class-decorator", "@dec\n// c\nclass A {}\n"],
  ["class-decorator-before-decorator", "@a\n// c\n@b\nclass A {}\n"],
  ["class-type-params-extends", "class A<T> // c\nextends B {}\n"],
  ["class-implements", "class A // c\nimplements B {}\n"],
  ["class-implements-after-extends", "class A extends B // c\nimplements C {}\n"],
  ["class-implements-dangling", "class A extends B<T> // c\nimplements C {}\n"],
  ["interface-extends", "interface A // c\nextends B {}\n"],
  ["interface-type-params-extends", "interface A<T> // c\nextends B {}\n"],
  ["interface-body", "interface A // c\n{ a: string }\n"],
  ["interface-empty", "interface A {\n  // c\n}\n"],
  // handleConditionalExpressionComments with a conditional type
  ["conditional-type", "type A = B extends C\n  // c\n  ? D\n  : E;\n"],
  ["conditional-type-alt", "type A = B extends C\n  ? D\n  // c\n  : E;\n"],
  // handleVariableDeclaratorComments with type aliases
  ["type-alias-literal", "type A = // c\n  { a: string };\n"],
  ["type-alias-block", "type A = /* c */\n  string;\n"],
  ["type-alias-line", "type A = // c\n  string;\n"],
  // willPrintOwnComments: union members print their own comments
  ["union-member-comments", "type A =\n  /* a */ | B\n  /* b */ | C;\n"],
];
export default cases.map(([name, text]) => ({ name, text, filepath: `${name}.ts` }));
