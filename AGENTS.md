# Swift code verification policy

After adding, modifying, or deleting Swift (`.swift`) files, including application code and test code:

1. Identify the affected behavior and its dependencies.
2. Add or update tests for new behavior and bug fixes.
3. Run all unit tests.
4. Run additional focused tests when appropriate.
5. Run UI tests when changes affect navigation, user interaction, persistence, or presentation behavior.
6. Inspect failures, fix their causes, and rerun affected tests.
7. After the final Swift code modification, rerun the necessary tests.
8. Report the executed tests, results, and limitations.

Do not claim that tests passed unless they were executed successfully. Do not weaken or remove tests merely to obtain a pass. If verification is impossible, explain the reason and what remains unverified.
