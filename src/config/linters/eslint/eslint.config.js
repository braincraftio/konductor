// ESLint flat config
// Simplified version that works with Nix-managed global packages

export default [
  {
    // Global ignores
    ignores: [
      "**/node_modules/**",
      "**/dist/**",
      "**/build/**",
      "**/coverage/**",
      "**/*.min.js",
      "**/*.generated.*",
      "**/.next/**",
      "**/.nuxt/**",
      "**/public/**",
      "**/tmp/**",
      "**/.cache/**",
      "**/.npm-global/**",
      "**/.pnpm-store/**",
    ],
  },
  {
    // Base config for all JavaScript files
    files: ["**/*.js", "**/*.jsx", "**/*.mjs", "**/*.cjs"],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "module",
      globals: {
        // Browser globals
        window: "readonly",
        document: "readonly",
        navigator: "readonly",
        console: "readonly",
        // Node.js globals
        global: "readonly",
        process: "readonly",
        Buffer: "readonly",
        __dirname: "readonly",
        __filename: "readonly",
        exports: "writable",
        module: "writable",
        require: "readonly",
      },
      parserOptions: {
        ecmaFeatures: {
          jsx: true,
        },
      },
    },
    rules: {
      // Code quality rules (Biome handles formatting)
      "no-console": ["warn", { allow: ["warn", "error", "info"] }],
      "no-debugger": "error",
      "no-unused-vars": [
        "error",
        {
          argsIgnorePattern: "^_",
          varsIgnorePattern: "^_",
        },
      ],
      "no-use-before-define": [
        "error",
        {
          functions: false,
          classes: true,
          variables: true,
        },
      ],
      "prefer-const": "error",
      "no-var": "error",
      eqeqeq: ["error", "always", { null: "ignore" }],
      curly: ["error", "all"],
      "no-throw-literal": "error",
      "no-implicit-coercion": "error",
      "no-param-reassign": [
        "error",
        {
          props: true,
          ignorePropertyModificationsFor: [
            "acc",
            "accumulator",
            "e",
            "ctx",
            "req",
            "request",
            "res",
            "response",
            "$scope",
          ],
        },
      ],
      "no-shadow": "error",
      "no-return-await": "error",
      "require-await": "error",
      "no-async-promise-executor": "error",
      "no-promise-executor-return": "error",
    },
  },
  {
    // Test files config
    files: ["**/*.test.{js,ts}", "**/*.spec.{js,ts}"],
    languageOptions: {
      globals: {
        // Jest globals
        describe: "readonly",
        it: "readonly",
        test: "readonly",
        expect: "readonly",
        beforeEach: "readonly",
        afterEach: "readonly",
        beforeAll: "readonly",
        afterAll: "readonly",
        jest: "readonly",
      },
    },
    rules: {
      "no-console": "off",
      "@typescript-eslint/no-non-null-assertion": "off",
    },
  },
  {
    // CLI tools and bin scripts config
    files: [".config/bin/**/*.js", "**/bin/**/*.js"],
    rules: {
      "no-console": "off", // CLI tools need console.log for output
    },
  },
];
