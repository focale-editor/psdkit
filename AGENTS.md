# AGENTS.md

## Hierarchy
* **Explicit hierarchy:** Explicit task instructions > AGENTS.md > existing project conventions > general Dart/Flutter conventions.

## Interaction Guidelines
* **Formatting:** Use the `dart_format` tool to ensure consistent code formatting.
* **Fixes:** Use the `dart_fix` tool to automatically fix many common errors, and to help code conform to configured analysis options.

## Project Structure
* **Immutability:** Prefer immutable data structures.
* **State Management:** Separate ephemeral state and app state. Use Riverpod for app state to handle the separation of concerns.
* **Logical Layers:** Organize the project into logical layers:
  * Domain (business logic classes).
  * Data (model classes, API clients).
  * Core (shared classes, utilities, and extension types).
* **Feature-based Organization:** Organize code by feature, where each feature has its own presentation, domain, and data subfolders. This improves navigability and scalability.

## Data Flow
* **Data Structures:** Define data structures (classes) to represent the data used in the application.
* **Data Abstraction:** Abstract data sources (e.g., API calls, database operations) using Repositories/Services to promote testability.

## Code Quality
* **General guideline:** the app code structure must stay organized, clear, optimized and maintainable.
* **Code structure:** Adhere to maintainable code structure and separation of concerns (e.g., UI logic separate from business logic).
* **Naming conventions:** Avoid abbreviations and use meaningful, consistent, descriptive names for variables, functions, and classes.
* **Conciseness:** Write code that is as short as it can be while remaining clear.
* **Simplicity:** Write straightforward code. Code that is clever or obscure is difficult to maintain.
* **Error Handling:** Anticipate and handle potential errors. Don't let your code fail silently.
* **Styling:**
  * Classes should use `PascalCase`.
  * Members/variables/functions/enums should use `camelCase`.
  * Files should use `snake_case`.
  * Constructors parameters should be named, and must have a trailing comma to ensure proper multiline formatting. Super parameters should go first.
  * You should prefer shorthands with constructors (eg `.zero` instead of `EdgeInsets.zero`, `.center` instead of `Alignment.center`). It improves readability and may reduce imports count.
* **Typing:**
  * Local variables should always be typed, unless special needs. They should be final.
  * Lambda parameters should not be typed.
  * Maps, sets, lists literals should not be typed, unless needed.

## Dart Best Practices
* **Async/Await:** Ensure proper use of `async`/`await` for asynchronous
  operations with robust error handling.
  * Use `Future`s, `async`, and `await` for asynchronous operations.
  * Use `Stream`s for sequences of asynchronous events.
* **Null Safety:** Write code that is soundly null-safe. Leverage Dart's null safety features. Avoid `!` unless the value is guaranteed to be non-null.
* **Switch Statements:** Prefer using exhaustive `switch` statements or expressions, which don't require `break` statements.
* **Exception Handling:** Use `try-catch` blocks for handling exceptions, and use exceptions appropriate for the type of exception. Use custom exceptions for situations specific to your code.
* **Arrow Functions:** Use arrow syntax for simple one-line functions.

## Comments
* **Document:** You should always document public and private members, functions, constructors. You don't need to document what's been overridden as it's already documented in the parent.
  * **`dartdoc`:** Write `dartdoc`-style comments for all public APIs.
  * **Use `///` for doc comments:** This allows documentation generation tools to pick them up.
  * **Document for the user:** Write documentation with the reader in mind. If you had a question and found the answer, add it to the documentation where you first looked. This ensures the documentation answers real-world questions.
  * **Start with a single-sentence summary:** The first sentence should be a concise, user-centric summary ending with a period.
  * **Separate the summary:** Add a blank line after the first sentence to create a separate paragraph. This helps tools create better summaries.
  * **Avoid redundancy:** Don't repeat information that's obvious from the code's context, like the class name or signature.
* **Comments:** Write clear comments for complex or non-obvious code. Avoid over-commenting.
* **Consistency is key:** Use consistent terminology throughout your documentation.
* **Be brief:** Write concisely.
* **Avoid jargon and acronyms:** Don't use abbreviations unless they are widely understood.
* **Use Markdown sparingly:** Avoid excessive markdown and never use HTML for formatting.
* **Use backticks for code:** Enclose code blocks in backtick fences, and specify the language.
* **Place doc comments before annotations:** Documentation should come before any metadata annotations.

## Package Management
* **Pub Tool:** To manage packages, use the `pub` tool, if available.
* **External Packages:** If a new feature requires an external package, identify the most suitable, stable and maintained package from pub.dev.
* **Adding Dependencies:** To add a regular dependency, run `flutter pub add <package_name>`.
* **Adding Dev Dependencies:** To add a development dependency, run `flutter pub add dev:<package_name>`.
* **Dependency Overrides:** To add a dependency override, run `flutter pub add override:<package_name>:1.0.0`.
* **Removing Dependencies:** To remove a dependency, run `dart pub remove <package_name>`.

## Logging
* **Structured Logging:** Use the `log` function from `dart:developer` for structured logging that integrates with Dart DevTools.

## Testing
* **Running Tests:** To run tests, use `flutter test`.
* **Unit Tests:** Use `package:test` for unit tests.
* **Integration Tests:** Use `package:integration_test` for integration tests.
* **Assertions:** Prefer using `package:checks` for more expressive and readable assertions over the default `matchers`.
* **Convention:** Follow the Arrange-Act-Assert (or Given-When-Then) pattern.
* **Unit Tests:** Write unit tests for domain logic, data layer, and state management.
* **Integration Tests:** For broader application validation, use integration tests to verify end-to-end user flows.
* **Mocks:** Prefer fakes or stubs over mocks. If mocks are absolutely necessary, use `mockito` to create mocks for dependencies.
* **Coverage:** Aim for high test coverage. Changes to domain logic, repositories, parsing or state behavior must include/update tests; pure visual changes do not require tests unless behavior changes.

## Code Generation
* **Code Generation Tasks:** Use `build_runner` for all code generation tasks, such as for `json_serializable`.
* **Running Build Runner:** After modifying files that require code generation, run the build command: `dart run build_runner build`.

## How to apply these instructions
* These rules apply to new and modified code.
* Do not refactor unrelated existing code solely to satisfy this file unless explicitly asked.
* When asked to bring the existing codebase into compliance, first identify violations and prioritize architectural/project-specific rules over stylistic cleanup.
* Preserve existing behavior unless the task explicitly requires a behavior change.
* Prefer the smallest coherent change that fully satisfies the task.

## Validation
* **At the end of a task:** Format, analyze and test.
  1. Run `dart format` to format modified Dart files.
  2. Run `dart analyze`.
  3. Run the tests relevant to the changed code.
  4. Run code generation when generated inputs changed.
  5. Do not consider the task complete while newly introduced analyzer errors or test failures remain.
