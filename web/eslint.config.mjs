export default [
  {
    files: ["**/*.js", "**/*.mjs"],
    languageOptions: {
      ecmaVersion: 2023,
      sourceType: "module",
      globals: {
        window: "readonly", document: "readonly", navigator: "readonly",
        localStorage: "readonly", indexedDB: "readonly", console: "readonly",
        setTimeout: "readonly", clearTimeout: "readonly", setInterval: "readonly",
        requestAnimationFrame: "readonly", cancelAnimationFrame: "readonly",
        fetch: "readonly", Blob: "readonly", URL: "readonly", performance: "readonly",
        crypto: "readonly", CustomEvent: "readonly", Event: "readonly",
        EventTarget: "readonly", Response: "readonly", caches: "readonly",
        self: "readonly", confirm: "readonly", alert: "readonly",
        L: "readonly", process: "readonly",
      },
    },
    rules: {
      "no-undef": "error",
      "no-unused-vars": ["warn", { args: "none", varsIgnorePattern: "^_" }],
      "no-dupe-keys": "error",
      "no-dupe-class-members": "error",
      "no-unreachable": "error",
      "no-constant-condition": "warn",
    },
  },
];
