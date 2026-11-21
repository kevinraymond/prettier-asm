// CLI flags of the corpus cases -> Prettier options.
export function flagsToOptions(args) {
  const o = {};
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    const next = () => args[++i];
    switch (a) {
      case "--stdin-filepath": o.filepath = next(); break;
      case "--no-semi": o.semi = false; break;
      case "--single-quote": o.singleQuote = true; break;
      case "--jsx-single-quote": o.jsxSingleQuote = true; break;
      case "--trailing-comma": o.trailingComma = next(); break;
      case "--arrow-parens": o.arrowParens = next(); break;
      case "--print-width": o.printWidth = Number(next()); break;
      case "--tab-width": o.tabWidth = Number(next()); break;
      case "--use-tabs": o.useTabs = true; break;
      case "--no-bracket-spacing": o.bracketSpacing = false; break;
      case "--bracket-same-line": o.bracketSameLine = true; break;
      case "--quote-props": o.quoteProps = next(); break;
      case "--object-wrap": o.objectWrap = next(); break;
      case "--end-of-line": o.endOfLine = next(); break;
      case "--experimental-ternaries": o.experimentalTernaries = true; break;
      case "--experimental-operator-position": o.experimentalOperatorPosition = next(); break;
      case "--parser": o.parser = next(); break;
      default: throw new Error("flag not mapped: " + a);
    }
  }
  return o;
}
