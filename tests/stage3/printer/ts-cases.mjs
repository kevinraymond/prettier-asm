// TypeScript snippets for run.mjs: a string, or [code, flags]. Each runs at the default width, at
// --print-width 40 and with --no-semi, as case.ts. Most were added for a mutant of
// ts-mutants.mjs that the fixtures did not notice.
export const filepath = "case.ts";
export default [
  // printTypeAnnotationProperty: a leading comment on the annotation gets a space before it
  "let x /* c */: string;\nfunction f(a /* c */: string) {}\ninterface A {\n  a /* c */: string;\n}",
  // enum members named by strings
  "enum A { 'a' = 1, \"b-c\", 'd' }",
  // parameter decorators: the typescript parser takes them on a class declaration's methods,
  // constructors and setters with a body, and throws elsewhere, where babel-ts does not
  "class A { m(@dec a, @dec() b) {} }\nexport class B {\n  constructor(@dec private a: string, @dec c = 1) {}\n  set x(@dec v) {}\n  static #m(this: B, @dec a) {}\n}",
  "function f(@dec a) {}",
  "const A = class { m(@dec a) {} };",
  "class A { m(@dec this) {} }",
  "abstract class A { abstract m(@dec a): void }",
  "class A { m(@dec a); m(a) {} }",
  "interface A { m(@dec a): void }",
  "class A { m() { return { n(@dec a) {} }; } }",
  // `extends B<T>` and a line break make a TSInstantiationExpression for babel-ts
  "class A extends B<T> // c\nimplements C {}",
  "class A extends B<T> // c\n{}",
];
