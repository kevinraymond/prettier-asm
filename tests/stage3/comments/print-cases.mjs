// Cases for printComment (print/comment.js): line comments with trailing whitespace, JSDoc
// blocks with mixed indentation, CRLF line ends, non-ASCII whitespace, hashbangs.
const NBSP = " ", EMSP = " ", IDSP = "　", BOM = "﻿";
const cases = [
  ["line-trailing-spaces", "// a   \nx;\n"],
  ["line-trailing-tab", "// a\t\t\nx;\n"],
  ["line-trailing-nbsp", `// a${NBSP}\nx;\n`],
  ["line-trailing-emsp", `// a${EMSP}${IDSP}\nx;\n`],
  ["line-trailing-feff", `// a${BOM}\nx;\n`],
  ["line-inner-nbsp", `// a${NBSP}b\nx;\n`],
  ["line-empty", "//\nx;\n"],
  ["line-only-spaces", "//    \nx;\n"],
  ["line-crlf", "// a  \r\nx;\r\n"],
  ["line-cr", "// a  \rx;\r"],
  ["hashbang", "#!/usr/bin/env node   \nx;\n"],
  ["hashbang-crlf", "#!/usr/bin/env node\r\nx;\r\n"],
  ["block-single", "/* a */ x;\n"],
  ["block-empty", "/**/ x;\n"],
  ["block-star-empty", "/***/ x;\n"],
  ["block-trailing-space-inside", "/* a   */ x;\n"],
  ["block-multiline-plain", "/* a\n   b\n c */\nx;\n"],
  ["block-multiline-blank", "/*\n\n*/\nx;\n"],
  ["jsdoc", "/**\n * a\n * b\n */\nx;\n"],
  ["jsdoc-mixed-indent", "/**\n     * a\n\t* b   \n  *  c\t\n */\nx;\n"],
  ["jsdoc-tabs", "\t/**\n\t * a\n\t */\nx;\n"],
  ["jsdoc-last-line-text", "/**\n * a\n * b */\nx;\n"],
  ["jsdoc-first-line-text", "/** a\n * b\n */\nx;\n"],
  ["jsdoc-one-line-missing-star", "/**\n * a\n b\n */\nx;\n"],
  ["jsdoc-trailing-spaces", "/**   \n * a   \n */\nx;\n"],
  ["jsdoc-crlf", "/**\r\n * a\r\n * b\r\n */\r\nx;\r\n"],
  ["block-crlf", "/* a\r\n   b */\r\nx;\r\n"],
  ["block-cr", "/* a\r   b */\rx;\r"],
  ["jsdoc-nbsp-indent", `/**\n${NBSP} * a\n${NBSP}*/\nx;\n`],
  ["jsdoc-emsp-trailing", `/**\n * a${EMSP}\n */\nx;\n`],
  ["block-nbsp", `/*${NBSP}a${NBSP}*/ x;\n`],
  ["block-ls", "/* a b */ x;\n"],
  ["block-ps-jsdoc", "/**  * a\n */\nx;\n"],
  ["line-ls-after", "x; // a y;\n"],
  ["jsdoc-unicode", "/**\n * 日本語 😀\n * ü\n */\nx;\n"],
  ["block-unicode", "/* 😀\n  ü */ x;\n"],
  ["star-lines-no-jsdoc", "/*\n * a\n */\nx;\n"],
  ["star-single-line", "/* * */ x;\n"],
  ["block-in-indent", "function f() {\n  /**\n   * a\n      * b\n   */\n  x;\n}\n"],
  ["many", "#!/x\n// a \n/* b */ /** c\n * d */\nx; // e\t\n/*\n f\n*/\n"],
];
export default cases.map(([name, text]) => ({ name, text, filepath: `${name}.js` }));
